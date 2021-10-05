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

  (define db-conn
    (postgresql-connect #:user "test" #:password "postgres" #:database "postgres"))

  (define (n-tweets)
    (hash-ref (db-stats) 'n-tweets))

  (define (n-deleted)
    (hash-ref (db-stats) 'n-deleted))

  (define (n-latest-tweets)
    (apply + (hash-values (hash-ref (db-stats) 'latest-tweets))))

  (define (n-checked-tweets)
    (apply + (hash-values (hash-ref (db-stats) 'checked-tweets))))

  (check-eq? (length (get-accounts)) 2)
  (check-eq? (n-tweets) 2)

  (define tweet
    (string->jsexpr
     (format "{\"id\":300,\"user_id\":1,\"created_at\":\"~a\"}"
             (date->string (current-date)))))

  (test-case
      "Insert tweet"
   (insert-tweet tweet)

    (check-eq? (n-tweets) 3)
    (check-equal? (sort (get-tweet-ids 3) <) '(1)))

  (test-case
      "Check latest/checked tweets, and top user"
    (check-eq? (n-latest-tweets) 2)
    (check-eq? (n-checked-tweets) 2)
    (check-equal? (hash-ref (db-stats) 'top-user) #hash(("a" . 1)))

    (touch-tweet 1)
    (check-eq? (n-latest-tweets) 2)
    (check-eq? (n-checked-tweets) 3))

  (test-case
      "Set a tweet as deleted from twitter"
    (check-eq? (n-deleted) 0)
    (set-tweet-deleted 1)
    (check-eq? (n-deleted) 1)
    (check-eq? (get-tweet-ids 3) '()))

  (test-case
      "Insert invalid tweet"
    (check-exn
     exn:fail?
     (λ ()
       (call-with-bound-transaction
        (λ ()
          (insert-tweet (string->jsexpr "{\"id\":99,\"user_id\":1}"))
          (raise (exn:fail "fail" (current-continuation-marks)))))))
    (check-eq? (n-tweets) 3))

  (test-case
      "Test updating likes/retweet stats"
    (update-engagement 2 3 0)
    (check-equal? (query-row db-conn "select * from engagement") #(2 3 0))

    (update-engagement 2 5 10)
    (check-equal? (query-row db-conn "select * from engagement") #(2 5 10)))

  (test-case
      "Test retrieving tweet"
    (check-equal?
     (query-value db-conn @~a{select json from tweets where tweet_id = 300})
     tweet))

  (test-case
      "Check database tweet timestamps"
    (check-true
     (query-value
      db-conn @~a{select added > current_date from tweets where tweet_id = 300}))

    (check-true
     (query-value
      db-conn @~a{select last_checked > current_date from tweets where tweet_id = 300}))

    (check-true
     (query-value
      db-conn @~a{select last_checked > current_date from tweets where tweet_id = 1})))

  (disconnect db-conn))
