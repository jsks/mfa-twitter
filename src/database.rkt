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
  [get-accounts (-> (listof vector?))]
  [init-db (-> #:user string? #:password string? #:database string? void?)]
  [insert-tweets (-> (listof jsexpr?) void?)]))

(struct db-settings (user database password) #:mutable)
(define credentials (db-settings "" "" ""))

(define (init-db #:user user #:password password #:database database)
  (set-db-settings-user! credentials user)
  (set-db-settings-password! credentials password)
  (set-db-settings-database! credentials database))

(define db-conn
  (virtual-connection
   (connection-pool
    (lambda () (postgresql-connect #:user (db-settings-user credentials)
                                   #:database (db-settings-database credentials)
                                   #:password (db-settings-password credentials)))
    #:max-idle-connections 1)))

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

(define (insert-tweets tweets)
  (for ([tweet (in-list tweets)])
    (query-exec db-conn
                @~a{insert into tweets (tweet_id, user_id, json)
                    values ($1, $2, cast($3::text as jsonb))
                    on conflict do nothing}
                (hash-ref tweet 'id)
                (hash-ref tweet 'user_id)
                (jsexpr->string tweet))))
