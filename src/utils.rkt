#lang racket/base

(require racket/contract
         racket/match
         srfi/19)

(provide
 (contract-out
  [select (->* (hash?) () #:rest (listof any/c) any/c)]
  [symbol->number (-> symbol? (or/c number? false/c))]
  [twitter-date->srfi-date (-> string? date?)]))

(define (select tbl . keys)
  (match keys
    [(list head) (hash-ref tbl head)]
    [(list head tail ...) (apply select (hash-ref tbl head) tail)]))

(define (symbol->number sym)
  (string->number (symbol->string sym)))

(define (twitter-date->srfi-date str)
  (string->date str "~a ~b ~d ~H:~M:~S ~z ~Y"))
