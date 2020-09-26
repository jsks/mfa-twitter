#lang at-exp racket/base

;; TODO: SSL

(require db
         json
         racket/contract
         racket/format)

(provide
 (contract-out
  [get-accounts (-> (listof vector?))]
  [insert-tweets (-> (listof jsexpr?) void?)]
  [db-user (parameter/c string?)]
  [db-password (parameter/c string?)]
  [db-database (parameter/c string?)]
  [call-with-bound-transaction (-> (-> any) any)]))

(define db-user (make-parameter ""))
(define db-password (make-parameter ""))
(define db-database (make-parameter ""))

(define db-conn
  (virtual-connection
   (connection-pool
    (lambda () (postgresql-connect #:user (db-user)
                                   #:database (db-database)
                                   #:password (db-password)))
    #:max-idle-connections 1)))

(define (call-with-bound-transaction proc)
  (call-with-transaction db-conn proc))

(define (get-accounts)
  (let ([query @~a{select screen_name, max(tweet_id) from accounts
                   left join tweets using (user_id)
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
