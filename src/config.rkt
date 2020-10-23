#lang racket/base

(require racket/contract
         racket/match
         racket/string)

(provide
 (contract-out
  [load-config (-> path-string? hash?)]))

(define required-fields '(access_token
                          pg_user
                          pg_password
                          pg_database))

(define (strip-quotes str)
  (string-trim str "\""))

(define (split-once pattern str)
  (match (regexp-match-positions pattern str)
    [(list (cons a b))
     (values (string->symbol (substring str 0 a))
             (substring str b (string-length str)))]
    [_ (values str #f)]))

(define (config-line? str)
  (and (non-empty-string? str)
       (not (char=? (string-ref (string-trim str #:right? #f) 0) #\#))))

(define (validate config-args)
  (for ([key (in-list required-fields)]
        #:when (not (hash-has-key? config-args key)))
    (raise-user-error 'load-config "Missing argument in configuration file: ~a" key)))

(define (load-config file)
  (define config-args (make-hash))
  (call-with-input-file file
    (lambda (port)
      (for ([line (in-lines port)]
            #:when (config-line? line))
        (let-values ([(key value) (split-once #rx" *= *" line)])
          (hash-set! config-args key (strip-quotes value))))))
  (validate config-args)
  config-args)