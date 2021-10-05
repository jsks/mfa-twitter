#lang at-exp racket/base

(require json
         racket/date
         racket/format
         racket/function
         racket/contract
         racket/list
         racket/match
         racket/sequence
         racket/string
         threading)

(require "database.rkt"
         "thread-pool.rkt"
         "twitter.rkt"
         "utils.rkt")

(provide
 num-threads
 (contract-out [dispatch (-> string? hash? void?)]))

(date-display-format 'iso-8601)

(define (dispatch command args)
  (access-token (hash-ref args 'access_token))
  (init-db #:user (hash-ref args 'pg_user)
           #:password (hash-ref args 'pg_password)
           #:database (hash-ref args 'pg_database)
           #:socket (hash-ref args 'pg_socket))

  (case command
    [("help") (handle-help)]
    [("sync-timelines") (handle-sync-timelines)]
    [("sync-profiles") (handle-sync-profiles)]
    [("scan-tweets") (handle-scan-tweets)]
    [("status") (handle-status)]
    [else
     (displayln (format "Unknown command: ~a, see 'mfa help'" command)
                (current-error-port))
     (exit 1)]))

(define (handle-help)
  (displayln
   @~a{Available sub-commands:
       help               Show this message.
       sync-timelines     Update timeline store for all accounts in database.
       sync-profiles      Update account profiles and followers.
       scan-tweets        Check if any stored tweets have been deleted and update
                              engagement numbers
       status             List current rate limits}))

;;; Sync Timelines

(define (handle-sync-timelines)
  (for/thread ([account (in-list (get-accounts))])
    (match-define (vector screen_name user_id since_id) account)
    (with-handlers
      ([exn:fail:twitter? (λ (e) (log-error "@~a ~a" screen_name (exn-message e)))])
      (let ([total (process-timeline user_id since_id)])
         (when (> total 0)
           (log-info "@~a -> downloaded ~a tweet(s)" screen_name total))))))

(define (process-timeline user_id since_id)
  (call-with-bound-transaction
   (λ ()
     (for/sum ([tweets (in-producer (gen/timeline user_id #:since_id since_id) (void))])
       (for ([tweet (in-list tweets)])
         (insert-tweet (prune tweet))
         (update-engagement (select tweet 'id)
                            (select tweet 'favorite_count)
                            (select tweet 'retweet_count)))
       (length tweets)))))

(define (prune tweet)
  (for/hash ([(key value) (in-hash tweet)]
             #:when (not (regexp-match #rx"_str$" (symbol->string key))))
    (match key
      [(or 'retweeted_status 'quoted_status) (values key (prune value))]
      ['user (values 'user_id (hash-ref value 'id))]
      ['source (values key (regexp-replace* "<[^>]+>" value ""))]
      [_ (values key value)])))

;;; Scan tweets

(define (handle-scan-tweets)
  (define n (~> (rate-limit-status '("statuses"))
                (select 'resources 'statuses '/statuses/lookup 'remaining)
                (* 100)))
  (cond [(= n 0) (log-error "Rate limit exceeded")]
        [else
         (log-info "Scanning ~a tweets" n)
         (scan-tweets n)]))

(define (scan-tweets n)
  (for/thread ([tweet-ids (in-slice 100 (get-tweet-ids n))])
    (with-handlers
      ([exn:fail:twitter? (λ (e) (log-error (exn-message e)))])
      (call-with-bound-transaction (λ () (process-batch tweet-ids))))))

(define (process-batch tweet-ids)
  (for ([(k tweet) (in-hash (select (get-tweets-by-id tweet-ids) 'id))])
    (define id (symbol->number k))
    (touch-tweet id)
    (cond [(eq? tweet (json-null)) (set-tweet-deleted id)]
          [else (update-engagement id
                                   (select tweet 'favorite_count)
                                   (select tweet 'retweet_count))])))

;;; Update user profiles and friends list

(define (handle-sync-profiles)
  (define user_id (get-lapsed-profile))
  (with-handlers
    ([exn:fail:twitter? (λ (e) (log-error (exn-message e)))])
    (call-with-bound-transaction (λ () (process-profile user_id)))))

;; TODO: Rate limits capped at 6000 followers for friends/list.json endpoint
(define (process-profile user_id)
  (define user (get-user user_id))
  (log-info "Syncing profile data for @~a" (select user 'screen_name))
  (insert-profile user)
  (for ([friends (in-producer (gen/friends user_id) (void))])
    (for ([friend (in-list friends)])
      (unless (profile-exists? (select friend 'id))
        (insert-profile friend))
      (connect-friend user_id (select friend 'id)))))

;;; Rate limit status
(define (handle-status)
  (define stats (db-stats))
  (displayln
   @~a{Total tweets: @(hash-ref stats 'n-tweets)
       Total deleted tweets: @(hash-ref stats 'n-deleted)
       Total active accounts: @(length (get-accounts))

       In the past 7 days...
       Added: @(apply + (hash-values (hash-ref stats 'latest-tweets)))
       Checked: @(apply + (hash-values (hash-ref stats 'checked-tweets)))
       Top user: @(match (hash-ref stats 'top-user)
                    [(hash-table (k v)) (format "@~a, ~a tweets" k v)])

       })

  (for ([key '(latest-tweets checked-tweets)])
    (let ([min_v (apply min (hash-values (hash-ref stats key)))]
          [max_v (apply max (hash-values (hash-ref stats key)))])
      (printf "~a: (min ~a, max ~a)\n\n"
              (if (eq? key 'latest-tweets) "Added tweets per day"
                  "Checked tweets per day")
              min_v max_v)
      (bar-chart (hash-ref stats key)))
    (printf "~a\n\n" (make-string 13 #\-)))

  (define rate-limits (current-rate-limits))
  (define max-endpoint-len (~>> (hash-keys rate-limits)
                                (map (λ (sym) (string-length (symbol->string sym))))
                                (apply max)))

  (displayln "Twitter API rate limits...")
  (for ([(endpoint tbl) (in-hash rate-limits)])
    (printf "~a : ~a\n" (~a endpoint #:min-width max-endpoint-len)
            (format-rate-limit tbl))))

(define (bar-chart stats)
  (define weekdays '(Sunday Monday Tuesday Wednesday Thursday Friday Saturday))

  ;; Sort the bars based on the current day of the week so that today
  ;; is last
  (define ordered-days
    (let-values ([(head tail) (split-at weekdays (+ (date-week-day (current-date)) 1))])
      (append tail head)))

  (define interval (~>> (hash-values stats)
                        (apply max)
                        (/ _ 20)
                        (ceiling)))
  (define lens
    (for/hash ([(day n) (in-hash stats)])
      (values (string->symbol (string-trim day)) (quotient n interval))))

  (for ([row (in-list (reverse (inclusive-range 1 5)))])
    (for ([day (in-list ordered-days)])
      (let ([len (hash-ref lens day 0)])
        (if (>= len (* row 4)) (printf "█")
            (match (- (* row 4) len)
              [3 (printf "▆")]
              [2 (printf "▄")]
              [1 (printf "▂")]
              [_ (printf " ")]))
        (printf " ")))
    (printf "\n")))

(define (current-rate-limits)
  (define resources (rate-limit-status '("statuses" "friends" "application")))
  (define endpoints '(/statuses/user_timeline
                      /statuses/lookup
                      /friends/list
                      /application/rate_limit_status))

  (define (extract-api-family sym)
    (string->symbol (first (string-split (symbol->string sym) "/"))))

  (for/hash ([endpoint (in-list endpoints)])
    (let ([tbl (select resources 'resources (extract-api-family endpoint) endpoint)])
      (values endpoint tbl))))

(define (format-rate-limit tbl)
  (match tbl
    [(hash-table ('limit limit) ('remaining remaining) ('reset reset))
     (format "~a expires ~a" (~a remaining "/" limit #:min-width 10)
             (date->string (seconds->date reset) #t))]))
