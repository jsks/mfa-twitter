#lang racket/base

(require racket/cmdline
         racket/runtime-path)

(require "commands.rkt"
         "config.rkt"
         "logging.rkt")

(define-runtime-path default-cred-file "../.env")

(define cred-file (make-parameter default-cred-file))
(define log-level (make-parameter 'info))

(module+ main
  (define command
    (command-line
     #:program "mfa"
     #:once-each
     [("-c" "--credential-file") file
      "Location of credential file [default: .env]"
      (cred-file file)]
     [("-l" "--log-level") level
      "Verbosity level for log messages [default: info]"
      (log-level (string->symbol level))]
     [("-n" "--num-threads") num
      "Maximum number of concurrent threads [default: 4]"
      (max-threads (string->number num))]
     #:ps "Available sub-commands: help, db-status, sync-timelines, scan-tweets, rate-status"
     #:args (sub-command)
     sub-command))

  (init-logger (log-level))
  (dispatch command (load-config (cred-file))))
