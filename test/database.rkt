#lang at-exp racket/base

(module+ integration
  (require db
           json
           racket/date
           racket/file
           racket/format
           rackunit
           "../src/database.rkt")

  (date-display-format 'iso-8601)

  (init-db #:user "test"
           #:password "postgres"
           #:database "postgres"
           #:socket #f)

  (check-eq? (length (get-accounts)) 2)
  (check-eq? (n-tweets) 2)

  (define tweet
    (string->jsexpr
     (format "{\"id\":300,\"user_id\":1,\"created_at\":\"~a\"}"
             (date->string (current-date)))))
  (insert-tweet tweet)

  (check-eq? (n-tweets) 3)
  (check-equal? (sort (get-tweet-ids 3) <) '(1))
  (check-equal? (activity) #(1 0))
  (check-equal? (user-stats) '(#("a" 1)))

  (touch-tweet 1)
  (check-equal? (activity) #(1 1))

  (check-eq? (n-deleted) 0)
  (set-tweet-deleted 1)
  (check-eq? (n-deleted) 1)
  (check-eq? (get-tweet-ids 3) '())

  (check-exn
   exn:fail?
   (λ ()
     (call-with-bound-transaction
      (λ ()
        (insert-tweet (string->jsexpr "{\"id\":99,\"user_id\":1}"))
        (raise (exn:fail "fail" (current-continuation-marks)))))))
  (check-eq? (n-tweets) 3)

  (define db-conn
    (postgresql-connect #:user "test" #:password "postgres" #:database "postgres"))

  (check-equal?
   (query-value db-conn @~a{select json from tweets where tweet_id = 300})
   tweet)

  (check-true
   (query-value
    db-conn @~a{select added > current_date from tweets where tweet_id = 300}))

  (check-true
   (query-value
    db-conn @~a{select last_checked > current_date from tweets where tweet_id = 300}))

  (check-true
   (query-value
    db-conn @~a{select last_checked > current_date from tweets where tweet_id = 1}))

  (update-engagement 2 3 0)
  (check-equal? (query-row db-conn "select * from engagement") #(2 3 0))

  (update-engagement 2 5 10)
  (check-equal? (query-row db-conn "select * from engagement") #(2 5 10))

  (disconnect db-conn))
