#lang racket/base

(require racket/contract
         racket/date
         racket/logging
         racket/match)

(provide
 (contract-out
  [init-logger (-> log-level/c void?)]))

(current-logger (make-logger 'mfa))
(date-display-format 'iso-8601)

(define stop-channel (make-channel))

(define (print-log data)
  (match-let ([(vector level msg data topic) data])
    (let ([timestamp (date->string (current-date) #t)])
      (printf "[~a] [~a] ~a\n" level timestamp msg))))

(define (make-receiver-thread receiver)
  (define (drain)
    (let ([data (sync/timeout 0 receiver)])
      (when data (print-log data) (drain))))
  (thread
   (λ ()
    (let loop ()
      (let ([data (sync receiver stop-channel)])
        (cond [(eq? data 'stop) (drain)]
              [else (print-log data)
                    (loop)]))))))

;; Creates log-receiver with the specified level of log verbosity.
(define (init-logger level)
  (let* ([receiver (make-log-receiver (current-logger) level)]
         [receiver-thread (make-receiver-thread receiver)])
    (executable-yield-handler
     (λ (_) (channel-put stop-channel 'stop)
        (thread-wait receiver-thread)))))
