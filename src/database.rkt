#lang at-exp racket/base

;; TODO: SSL

(require db
         json
         racket/contract
         racket/format)

(provide
 (contract-out
  [call-with-bound-transaction (-> (-> any) any)]
  [init-db (-> #:user string? #:password string? #:database string? void?)]
  [activity (-> vector?)]
  [insert-tweet (-> jsexpr? void?)]
  [get-accounts (-> (listof vector?))]
  [get-tweet-ids (-> exact-nonnegative-integer? (listof integer?))]
  [n-deleted (-> exact-nonnegative-integer?)]
  [n-tweets (-> exact-nonnegative-integer?)]
  [touch-tweet (-> exact-positive-integer? void?)]
  [set-tweet-deleted (-> exact-positive-integer? void?)]
  [update-engagement (-> exact-positive-integer? exact-nonnegative-integer?
                         exact-nonnegative-integer? void?)]
  [user-stats (-> (listof vector?))]))

(struct db-settings (user database password) #:mutable)
(define credentials (db-settings "" "" ""))

(define (init-db #:user user #:password password #:database database)
  (set-db-settings-user! credentials user)
  (set-db-settings-password! credentials password)
  (set-db-settings-database! credentials database))

(define db-conn
  (virtual-connection
   (connection-pool
    (λ () (postgresql-connect #:user (db-settings-user credentials)
                              #:database (db-settings-database credentials)
                              #:password (db-settings-password credentials))))))

(define (call-with-bound-transaction proc)
  (call-with-transaction db-conn proc))

(define (activity)
  (vector
   (query-value db-conn @~a{select count(*) from tweets
                            where cast(json->>'created_at' as timestamp) >
                                current_date - interval '7 days'})
   (query-value db-conn @~a{select count(*) from tweets
                            where last_checked >= current_date - interval '7 days' and
                                added < current_date - interval '7 days'})))

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

(define (n-tweets)
  (query-value db-conn @~a{select count(*) from tweets}))

(define (n-deleted)
  (query-value db-conn @~a{select count(*) from tweets where deleted is true}))

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

(define (user-stats)
  (query-rows
   db-conn
   @~a{select screen_name, count(*) as N
       from atweets
       where cast(json->>'created_at' as timestamp) >
           current_date - interval '7 days'
       group by screen_name
       order by N desc}))
