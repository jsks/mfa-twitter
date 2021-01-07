#lang racket/base

(require racket/contract
         racket/match)

(provide
 (contract-out
  [select (->* (hash?) () #:rest (listof any/c) any/c)]
  [symbol->number (-> symbol? number?)]))

(define (select tbl . keys)
  (match keys
    [(list head) (hash-ref tbl head)]
    [(list head tail ...) (apply select (hash-ref tbl head) tail)]))

(define (symbol->number sym)
  (string->number (symbol->string sym)))
