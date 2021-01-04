#lang racket/base

(require racket/cmdline
         racket/function
         racket/list
         racket/match
         racket/runtime-path)

(require "config.rkt"
         "database.rkt"
         "logging.rkt"
         "thread-pool.rkt"
         "twitter.rkt")

(define-runtime-path default-cred-file "../.env")

(define cred-file (make-parameter default-cred-file))
(define log-level (make-parameter 'info))

(define command
  (command-line
   #:program "mfa"
   #:once-each
   [("-c" "--credential-file") file
    "Location of credential file [default: .env]" (cred-file file)]
   [("-l" "--log-level") level
    "Verbosity level for log messages [default: info]" (log-level (string->symbol level))]
   [("-n" "--num-threads") num
    "Maximum number of concurrent threads [default: 4]" (max-threads (string->number num))]))

(init-logger (log-level))
(define config-args (load-config (cred-file)))

(access-token (hash-ref config-args 'access_token))
(init-db #:user (hash-ref config-args 'pg_user)
         #:password (hash-ref config-args 'pg_password)
         #:database (hash-ref config-args 'pg_database))

(define (prune tweet)
  (for/hash ([(key value) (in-hash tweet)]
             #:when (not (regexp-match #rx"_str$" (symbol->string key))))
    (match key
      [(or 'retweeted_status 'quoted_status) (values key (prune value))]
      ['user (values 'user_id (hash-ref value 'id))]
      ['source (values key (regexp-replace* "<[^>]+>" value ""))]
      [_ (values key value)])))

(define (get-and-process-tweets account)
  (match-let ([(vector screen_name user_id since_id) account])
    (with-handlers
      ([exn:fail? (λ (e) (log-error "@~a ~a" screen_name (exn-message e)))])
      (call-with-bound-transaction
       (λ ()
         (let ([tweet-generator (get-timeline user_id #:since_id since_id)])
           (for ([tweets (in-producer tweet-generator)]
                 #:break (not tweets))
             (log-info "@~a -> downloaded ~a tweet(s)" screen_name (length tweets))
             (insert-tweets (map prune tweets)))))))))

(for/thread ([account (in-list (get-accounts))])
  (get-and-process-tweets account))
