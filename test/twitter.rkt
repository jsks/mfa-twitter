#lang racket/base

(require net/url
         racket/generator
         racket/match
         rackunit)

(require "../src/twitter.rkt")
(require/expose "../src/twitter.rkt" (check-response
                                      get-lowest-id
                                      mk-api-url
                                      parse-http-status))

(test-begin
  (define port (open-input-string "HTTP/1.1 200 Ok\r\n\r\n"))
  (check-not-exn (λ () (check-response port))))

(test-begin
  (define port (open-input-string "HTTP/1.1 400 Bad Request\r\n\r\n"))
  (check-exn exn:fail:twitter? (λ () (check-response port))))

(test-begin
  (define port (open-input-string "HTTP/1.1 400 Bad Request\r\n\r\nHello World\r\n"))
  (check-exn #rx"^HTTP 400 Bad Request" (λ () (check-response port))))

(test-begin
  (define port
    (open-input-string
     "HTTP/1.1 400 Bad Request\r\n\r\n{\"errors\":[{\"code\":10,\"message\":\"foo\"}]}"))
  (check-exn #rx"^HTTP 400 Bad Request" (λ () (check-response port))))

(test-begin
  (define port
    (open-input-string
     "HTTP/1.1 400 Bad Request\r\nContent-type: application/json\r\n\r\n{\"errors\":[{\"code\":10,\"message\":\"foo\"}]}"))
   (check-exn #rx"^HTTP 400 Bad Request, twitter api 10 foo" (λ () (check-response port))))

(test-begin
  (define port
    (open-input-string
     "HTTP/1.1 400 Bad Request\r\nContent-type: application/json\r\n\r\n{\"errors\":[{\"msg\":1}]}"))
  (check-exn #rx"^HTTP 400 Bad Request" (λ () (check-response port))))

(check-eq? (get-lowest-id (list #hash((id . 100)) #hash((id . 1)))) 1)

(test-begin
  (define url (url->string (mk-api-url "endpoint" '((a . 1) (b . "foo") (c  . #f)))))
  (check-equal? url "https://api.twitter.com/1.1/endpoint?a=1&b=foo"))

(test-begin
  (define-values (status description) (parse-http-status "HTTP/1.1 200 Ok\r\n"))
  (check-eq? status 200)
  (check-equal? description "Ok"))

(test-begin
  (define-values (status description) (parse-http-status "HTTP/1.1 401 Not Authorized\r\n"))
  (check-eq? status 401)
  (check-equal? description "Not Authorized"))

(test-begin
  (define-values (status description)
    (parse-http-status "HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\nfoo: 0\r\n\r\n"))
  (check-eq? status 200)
  (check-equal? description "OK"))

(check-exn exn:misc:match? (λ () (parse-http-status "HTTP 200 Ok\r\n")))
