#lang at-exp racket/base

(require json
         racket/date
         racket/format
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
    [("db-status") (handle-db-status)]
    [("sync-timelines") (handle-sync-timelines)]
    [("scan-tweets") (handle-scan-tweets)]
    [("rate-status") (handle-rate-status)]
    [else
     (displayln (format "Unknown command: ~a, see 'mfa help'" command)
                (current-error-port))
     (exit 1)]))

(define (handle-help)
  (displayln
   @~a{Available sub-commands:
       help               Show this message.
       db-status          Brief overview of database statistics
       sync-timelines     Update timeline store for all accounts in database.
       scan-tweets        Check if any stored tweets have been deleted and update
                          engagement numbers
       rate-status        List current rate limits}))

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

;;; Rate limit status

(define (handle-rate-status)
  (define resources (rate-limit-status '("statuses" "application")))
  (define endpoints '(/statuses/user_timeline
                      /statuses/lookup
                      /application/rate_limit_status))

  (define max-endpoint-len
    (~>> endpoints
        (map (λ (sym) (string-length (symbol->string sym))))
        (apply max)))

  (define (extract-api-family sym)
    (string->symbol (first (string-split (symbol->string sym) "/"))))

  (for ([endpoint (in-list endpoints)])
    (let ([l (select resources 'resources (extract-api-family endpoint) endpoint)])
      (printf "~a : ~a\n" (~a endpoint #:min-width max-endpoint-len)
              (format-rate-limit l)))))

(define (format-rate-limit tbl)
  (match tbl
    [(hash-table ('limit limit) ('remaining remaining) ('reset reset))
     (format "~a expires ~a" (~a remaining "/" limit #:min-width 10)
             (date->string (seconds->date reset) #t))]))

;;; Database status

(define (handle-db-status)
  (match-define (vector added checked) (activity))
  (match-define (vector screen_name n) (first (user-stats)))

  (displayln @~a{Total tweets: @(n-tweets)
                 Total deleted tweets: @(n-deleted)
                 Total active accounts: @(length (get-accounts))

                 Added in the past 7 days: @added
                 Checked in the past 7 days: @checked
                 Most active user in the past 7 days: @"@"@screen_name, @n tweets}))
