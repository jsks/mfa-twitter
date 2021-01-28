#lang racket/base

(require "../src/utils.rkt"
         rackunit)

(check-eq? (select #hash((a . 1)) 'a) 1)
(check-eq? (select #hash(("key1" . #hash((1 . a)))) "key1" 1) 'a)

(check-exn exn:fail:contract? (λ () (select #hash((a . 1)) 'b)))

(check-eq? (symbol->number '|100|) 100)
(check-false (symbol->number 'foo))
