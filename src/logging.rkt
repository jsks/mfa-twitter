#lang racket/base

(require racket/contract
         racket/date
         racket/function
         racket/logging
         racket/match)

(provide
 (contract-out
  [init-logger (-> log-level/c void?)]))

(date-display-format 'iso-8601)

(define stop-channel (make-channel))

(define (print-log data)
  (match-let ([(vector level msg data topic) data])
    (let ([timestamp (date->string (current-date) #t)])
      (printf "[~a] [~a] ~a\n" level timestamp msg))))

(define (make-receiver level)
  (when (not (eq? level 'debug))
    (current-logger (make-logger 'mfa)))
  (make-log-receiver (current-logger) level))

(define (make-receiver-thread receiver)
  (define (drain)
    (let loop ()
      (let ([data (sync/timeout 0 receiver)])
        (when data (print-log data) (loop)))))
  (thread
   (thunk
    (let loop ()
      (let ([data (sync receiver stop-channel)])
        (cond [(eq? data 'stop) (drain)]
              [else (print-log data)
                    (loop)]))))))

(define (init-logger level)
  (let* ([receiver (make-receiver level)]
         [receiver-thread (make-receiver-thread receiver)])
    (executable-yield-handler
     (lambda (_) (channel-put stop-channel 'stop)
             (thread-wait receiver-thread)))))
