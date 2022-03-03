#lang racket/base

(require (for-syntax racket/base racket/list syntax/for-body syntax/parse)
         racket/async-channel
         racket/contract)

(provide
 for/thread
 for/thread/list
 for/thread/sum
 (contract-out [num-threads (parameter/c exact-positive-integer?)]))

(define num-threads (make-parameter 4))
(struct thread-pool (threads input output) #:transparent)

(define-syntax (for/thread stx)
  (for_/thread/collect stx #'void (void)))

(define-syntax (for/thread/list stx)
  (for_/thread/collect stx #'cons '()))

(define-syntax (for/thread/sum stx)
  (for_/thread/collect stx #'+ 0))

(define-for-syntax (for_/thread/collect stx proc init)
  (define-splicing-syntax-class for-clause
    #:attributes (normalised)
    (pattern [var:id seq:expr]
             #:with normalised #'[(var) seq])
    (pattern [(var:id ...) seq:expr]
             #:with normalised #'[(var ...) seq])
    (pattern (~seq k:keyword e:expr)
             #:with normalised #'[k e]))

  (define (flatten-stx lst)
    (flatten (map syntax-e lst)))

  (define (filter-seq-ids clauses)
    (for/fold ([aux '()])
              ([clause (in-list clauses)])
      (syntax-parse clause
        [((ids ...+) _) (append (syntax->list #'(ids ...)) aux)]
        [_ aux])))

  (syntax-parse stx
    [(_ (~optional (~seq #:num-threads num)) (clauses:for-clause ...+) body ...+)
     #:declare num (expr/c #'exact-positive-integer?)
     #:with ([pre ...] [post ...]) (split-for-body stx #'(body ...))
     #:with (flat-clauses ...) (flatten-stx (syntax->list #'(clauses ...)))
     #:with (ids ...) (filter-seq-ids (syntax->list #'(clauses.normalised ...)))
     (syntax-protect
      #`(let* ([for-body #,(syntax/loc stx (λ (ids ...) post ...))]
               [pool (create-thread-pool (~? num.c (num-threads)) for-body)])
          (for (flat-clauses ...)
            pre ...
            (thread-pool-send pool ids ...))
          (thread
           (λ ()
             (stop-thread-pool pool)
             (async-channel-put (thread-pool-output pool) eof)))
          (collect-results (thread-pool-output pool) #,proc (quote #,init))))]))

(define (collect-results output-channel proc init)
  (let loop ([aux init])
    (define data (async-channel-get output-channel))
    (cond [(eof-object? data) aux]
          [else (loop (proc data aux))])))

(define (spawn-thread proc input-channel output-channel)
  (define thread-name (gensym))
  (thread
   (λ ()
     (let loop ()
       (define data (async-channel-get input-channel))
       (when (not (eof-object? data))
         (log-debug "thread ~a processing ~a" thread-name data)
         (async-channel-put output-channel (apply proc data))
         (loop))))))

(define (create-thread-pool num-threads proc)
  (log-debug "Creating pool with ~a threads" num-threads)
  (define input-channel (make-async-channel))
  (define output-channel (make-async-channel))
  (define threads (for/list ([_ (in-range num-threads)])
                    (spawn-thread proc input-channel output-channel)))
  (thread-pool threads input-channel output-channel))

(define (thread-pool-send pool . data)
  (async-channel-put (thread-pool-input pool) data))

(define (stop-thread-pool pool)
  (for ([_ (in-list (thread-pool-threads pool))])
    (async-channel-put (thread-pool-input pool) eof))
  (for ([th (in-list (thread-pool-threads pool))])
    (thread-wait th)))
