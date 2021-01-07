#lang at-exp racket/base

;; TODO: SSL

(require db
         db/util/datetime
         json
         racket/contract
         racket/format
         srfi/19)

(provide
 (contract-out
  [call-with-bound-transaction (-> (-> any) any)]
  [init-db (-> #:user string? #:password string? #:database string? void?)]
  [insert-tweet (-> jsexpr? void?)]
  [get-accounts (-> (listof vector?))]
  [get-tweet-ids (-> exact-nonnegative-integer? (listof integer?))]
  [touch-tweet (-> exact-positive-integer? void?)]
  [set-tweet-deleted (-> exact-positive-integer? void?)]
  [update-engagement (-> exact-positive-integer? exact-nonnegative-integer?
                         exact-nonnegative-integer? void?)]))

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

(define (get-accounts)
  (let ([today (srfi-date->sql-date (current-date))]
        [query @~a{select screen_name, user_id, max(tweet_id) from accounts
                   left join tweets using (user_id)
                   where accounts.deleted = false and
                       ((valid_to is null or valid_to >= $1) and
                        (valid_from is null or valid_from <= $1))
                   group by screen_name, user_id}])
    (for/list ([(screen_name user_id since_id) (in-query db-conn query today)])
      (vector screen_name user_id (sql-null->false since_id)))))

(define (get-tweet-ids n)
  (query-list
   db-conn @~a{select tweet_id from tweets
               where deleted is false and
                   last_checked < $1::timestamp - interval '7 days'
               limit $2}
   (srfi-date->sql-timestamp (current-date)) n))

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
   db-conn @~a{update tweets set last_checked = $1 where tweet_id = $2}
   (srfi-date->sql-timestamp (current-date)) tweet-id))

(define (update-engagement tweet-id favorite-count retweet-count)
  (query-exec
   db-conn @~a{insert into engagement (tweet_id, favorite_count, retweet_count)
               values ($1, $2, $3)
               on conflict (tweet_id) do update
               set favorite_count = EXCLUDED.favorite_count,
                   retweet_count = EXCLUDED.retweet_count}
   tweet-id favorite-count retweet-count))
