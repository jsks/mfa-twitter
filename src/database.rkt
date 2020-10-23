#lang at-exp racket/base

;; TODO: SSL

(require db
         json
         racket/contract
         racket/format)

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
  (let ([query @~a{select screen_name, max(tweet_id) from accounts
                   left join tweets using (user_id)
                   where accounts.deleted = false
                   group by screen_name}])
    (for/list ([(screen_name since_id) (in-query db-conn query)])
      (vector screen_name (sql-null->false since_id)))))

(define (insert-tweets tweets)
  (for ([tweet (in-list tweets)])
    (query-exec db-conn
                @~a{insert into tweets (tweet_id, user_id, json)
                    values ($1, $2, cast($3::text as jsonb))
                    on conflict do nothing}
                (hash-ref tweet 'id)
                (hash-ref tweet 'user_id)
                (jsexpr->string tweet))))
