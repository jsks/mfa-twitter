#lang racket/base

(require (for-syntax racket/base syntax/for-body syntax/parse)
         racket/async-channel
         racket/contract
         racket/function)

(provide
 for/thread
 (contract-out [max-threads (parameter/c exact-positive-integer?)]))

(define max-threads (make-parameter 4))
(define input-channel (make-async-channel))
(define threads '())

(define-syntax (for/thread stx)
  (syntax-parse stx
    [(_ (~optional (~seq #:max-threads num:expr) #:defaults ([num #'(max-threads)]))
        clauses body ...+)
     #:with ([pre ...] [post ...]) (split-for-body stx #'(body ...))
     #:with (ids ...) (for/fold ([aux '()])
                                ([clause (syntax->list #'clauses)])
                        (syntax-parse clause
                          [((ids ...) _) (append (syntax->list #'(ids ...)) aux)]
                          [(id _) (cons #'id aux)]))
     #'(begin
         (init-thread-pool (λ (ids ...) post ...) #:num-threads num)
         (for clauses
           pre ...
           (thread-pool-send ids ...))
         (stop-thread-pool))]))

(define (spawn-thread proc input-channel)
  (let ([thread-name (gensym)])
    (thread
     (λ ()
      (let loop ()
        (let ([data (async-channel-get input-channel)])
          (when (not (eq? data 'stop))
            (log-debug "thread ~a processing ~a" thread-name data)
            (apply proc data)
            (loop))))))))

(define (init-thread-pool proc #:num-threads num-threads)
  (log-debug "launching thread pool with ~a threads" num-threads)
  (set! threads (for/list ([_ (in-range num-threads)])
                  (spawn-thread proc input-channel))))

(define (thread-pool-send . data)
  (async-channel-put input-channel data))

;; TODO: set a timeout to kill running threads
(define (stop-thread-pool)
  (for ([thread (in-list threads)]) (async-channel-put input-channel 'stop))
  (for ([thread (in-list threads)]) (thread-wait thread)))
