#lang racket/base

(require racket/async-channel
         racket/contract
         racket/function)

(provide
 (contract-out
  [init-thread-pool (-> (-> vector? any)
                        #:num-threads (and/c integer? positive?)
                        void?)]
  [thread-pool-send (-> any/c void?)]
  [stop-thread-pool (-> void?)]))

(define-logger thread-pool)

(define input-channel (make-async-channel))
(define threads '())

(define (spawn-thread proc input-channel)
  (thread
   (thunk
    (let loop ()
      (let ([data (async-channel-get input-channel)])
        (cond [(eq? data 'stop) (log-thread-pool-debug "thread exit")]
              [else (proc data) (loop)]))))))

(define (init-thread-pool proc #:num-threads num-threads)
  (set! threads
        (for/list ([_ (in-range num-threads)])
          (spawn-thread proc input-channel))))

(define (thread-pool-send data)
  (async-channel-put input-channel data))

(define (stop-thread-pool)
  (for ([thread (in-list threads)]) (async-channel-put input-channel 'stop))
  (for ([thread (in-list threads)]) (thread-wait thread)))
