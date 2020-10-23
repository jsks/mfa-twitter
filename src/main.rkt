#lang racket/base

(require racket/cmdline
         racket/function
         racket/list
         racket/match)

(require "config.rkt"
         "database.rkt"
         "logging.rkt"
         "thread-pool.rkt"
         "twitter.rkt")

(define cred-file (make-parameter ".env"))
(define num-threads (make-parameter 8))

(define cli-parser
  (command-line
   #:program "mfa"
   #:once-each
   [("-c" "--credential-file") file
    "Location of file containing twitter token and db credentials" (cred-file file)]
   [("-n" "--num-threads") num
    "Maximum number of concurrent threads" (num-threads (string->number num))]))

(define cred-args (load-config (cred-file)))

(define config-args (load-config (config-file)))
(access-token (hash-ref config-args 'access_token))
(db-user (hash-ref config-args 'pg_user))
(db-password (hash-ref config-args 'pg_password))
(db-database (hash-ref config-args 'pg_database))

(define (prune tweet)
  (for/hash ([(key value) (in-hash tweet)]
             #:when (not (regexp-match #rx"_str$" (symbol->string key))))
    (match key
      [(or 'retweeted_status 'quoted_status) (values key (prune value))]
      ['user (values 'user_id (hash-ref value 'id))]
      ['source (values key (regexp-replace* "<[^>]+>" value ""))]
      [_ (values key value)])))

(define (process-tweets tweets)
  (insert-tweets (map prune tweets)))

(define (get-and-process-tweets account)
  (match-let ([(vector screen_name since_id) account])
    (log-info "Processing @~a" screen_name)
    (call-with-bound-transaction
     (thunk (get-tweets screen_name process-tweets #:since_id since_id)))))

(init-thread-pool get-and-process-tweets #:num-threads (num-threads))

(define accounts (get-accounts))
(for ([account (in-list accounts)])
  (thread-pool-send account))

(stop-thread-pool)
