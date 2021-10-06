#lang at-exp racket/base

(module+ integration
  (require db
           json
           racket/date
           racket/file
           racket/format
           rackunit
           "../src/database.rkt")
  (require/expose "../src/database.rkt" (db-conn))

  (date-display-format 'iso-8601)

  (init-db #:user "test")

  ;;; Utility Functions
  (define (db-value query)
    (query-value db-conn query))

  (define (db-row query)
    (query-row db-conn query))

  (define (n-tweets)
    (hash-ref (db-stats) 'n-tweets))

  (define (n-deleted)
    (hash-ref (db-stats) 'n-deleted))

  (define (n-latest-tweets)
    (apply + (hash-values (hash-ref (db-stats) 'latest-tweets))))

  (define (n-checked-tweets)
    (apply + (hash-values (hash-ref (db-stats) 'checked-tweets))))

  ;;; Tests
  (test-case
      "Check insertation of test data"
    (check-eq? (length (get-accounts)) 2)
    (check-eq? (n-tweets) 2))

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
    (check-equal? (db-row "select * from engagement") #(2 3 0))

    (update-engagement 2 5 10)
    (check-equal? (db-row "select * from engagement") #(2 5 10)))

  (test-case
      "Test retrieving tweet"
    (check-equal? (db-value "select json from tweets where tweet_id = 300") tweet))

  (test-case
      "Check database tweet timestamps"
    (check-true (db-value "select added > current_date from tweets where tweet_id = 300"))

    (check-true (db-value "select last_checked > current_date from tweets where tweet_id = 300"))

    (check-true
     (db-value "select last_checked > current_date from tweets where tweet_id = 1")))

  (test-case
      "Connect existing profiles"
    (connect-friend 1 100)
    (check-eq? (db-value "select count(*) from friends") 1)
    (check-eq?
     (db-value @~a{select B.user_id from friends
                   join profiles as A on friends.user_profile_id = A.profile_id
                   join profiles as B on friends.friend_profile_id = B.profile_id
                   where A.user_id = 1}) 100))

  (test-case
      "Insert new profile data"
    (check-eq? (db-value "select count(*) from profiles") 2)
    (insert-profile (hash 'id 99
                          'name "new_friend"
                          'screen_name "generic_name"
                          'description "foobar"
                          'verified #f
                          'friends_count 100
                          'followers_count 20
                          'statuses_count 98
                          'created_at "Tue Mar 29 08:11:25 +0000 2011"))
    (check-eq? (db-value "select count(*) from profiles") 3)
    (check-not-false (profile-exists? 99))
    (check-equal? (db-value "select name from profiles where user_id = 99") "new_friend"))

  (test-case
      "Check lapsed profile"
    ;; There should be two accounts in the account table; first update
    ;; one since get-lapsed-profile will only return one user_id
    (insert-profile (hash 'id 1
                          'name "test_name"
                          'screen_name "a"
                          'description "a test description"
                          'verified #t
                          'friends_count 1
                          'followers_count 1
                          'statuses_count 1
                          'created_at "Mon May 28 00:00:00 +0000 2011"))
    (check-eq? (db-value "select count(*) from profiles") 4)
    (check-eq? (get-lapsed-profile) 2)))
