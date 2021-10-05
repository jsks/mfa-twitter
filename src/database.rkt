#lang at-exp racket/base

;; TODO: SSL

(require db
         db/util/datetime
         json
         racket/contract
         racket/format
         threading)

(require "utils.rkt")

(provide
 (contract-out
  [call-with-bound-transaction (-> (-> any) any)]
  [init-db (-> #:user string?
               #:password string?
               #:database string?
               #:socket (or/c path-string? 'guess #f)
               void?)]
  [insert-tweet (-> jsexpr? void?)]
  [get-accounts (-> (listof vector?))]
  [get-tweet-ids (-> exact-nonnegative-integer? (listof integer?))]
  [touch-tweet (-> exact-positive-integer? void?)]
  [set-tweet-deleted (-> exact-positive-integer? void?)]
  [update-engagement (-> exact-positive-integer? exact-nonnegative-integer?
                         exact-nonnegative-integer? void?)]
  [db-stats (-> hash?)]))

(struct db-settings (user database password socket) #:mutable)
(define creds (db-settings "" "" "" #f))

(define (init-db #:user user #:password password #:database database #:socket socket)
  (set-db-settings-user! creds user)
  (set-db-settings-password! creds password)
  (set-db-settings-database! creds database)
  (set-db-settings-socket! creds socket))

(define db-conn
  (virtual-connection
   (connection-pool
    (λ () (postgresql-connect #:user (db-settings-user creds)
                              #:database (db-settings-database creds)
                              #:password (db-settings-password creds)
                              #:socket (db-settings-socket creds))))))

(define (call-with-bound-transaction proc)
  (call-with-transaction db-conn proc))

(define (get-accounts)
  (let ([query @~a{select screen_name, user_id, max(tweet_id) from accounts
                   left join tweets using (user_id)
                   where accounts.deleted = false and
                       ((valid_to is null or valid_to >= current_date) and
                        (valid_from is null or valid_from <= current_date))
                   group by screen_name, user_id}])
    (for/list ([(screen_name user_id since_id) (in-query db-conn query)])
      (vector screen_name user_id (sql-null->false since_id)))))

(define (get-tweet-ids n)
  (query-list
   db-conn @~a{select tweet_id from tweets
               where deleted is false and
                   last_checked < current_date - interval '7 days'
               limit $1}
   n))

(define (insert-tweet tweet)
  (query-exec
   db-conn @~a{insert into tweets (tweet_id, user_id, json)
               values ($1, $2, cast($3::text as jsonb))
               on conflict do nothing}
   (hash-ref tweet 'id)
   (hash-ref tweet 'user_id)
   (jsexpr->string tweet)))


(define (set-tweet-deleted tweet-id)
  (query-exec
   db-conn @~a{update tweets set deleted = true where tweet_id = $1} tweet-id))

(define (touch-tweet tweet-id)
  (query-exec
   db-conn @~a{update tweets set last_checked = current_timestamp where tweet_id = $1}
   tweet-id))

(define (update-engagement tweet-id favorite-count retweet-count)
  (query-exec
   db-conn @~a{insert into engagement (tweet_id, favorite_count, retweet_count)
               values ($1, $2, $3)
               on conflict (tweet_id) do update
               set favorite_count = EXCLUDED.favorite_count,
                   retweet_count = EXCLUDED.retweet_count}
   tweet-id favorite-count retweet-count))

(define (db-stats)
  (define added-tweets
    (~> (query db-conn @~a{select count(*), to_char(added, 'Day') as day
                           from tweets
                           where added >= current_date - interval '7 days'
                           group by day})
        (rows->dict #:key "day" #:value "count")))

  (define checked-tweets
    (~> (query db-conn @~a{select count(*), to_char(added, 'Day') as day
                           from tweets
                           where last_checked >= current_date - interval '7 days'
                           group by day})
        (rows->dict #:key "day" #:value "count")))

  (define n-deleted (query-value db-conn @~a{select count(*) from tweets
                                             where deleted is true}))

  (define n-tweets (query-value db-conn @~a{select count(*) from tweets}))

  (define top-user
    (~> (query db-conn @~a{select screen_name, count(*)
                           from atweets
                           where cast(json->>'created_at' as timestamp) >
                               current_date - interval '7 days'
                           group by screen_name
                           order by count desc
                           limit 1})
        (rows->dict #:key "screen_name" #:value "count")))

  (hash 'latest-tweets added-tweets
        'checked-tweets checked-tweets
        'n-deleted n-deleted
        'n-tweets n-tweets
        'top-user top-user))
