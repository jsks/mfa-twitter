#lang racket/base

(require json
         net/head
         net/url
         racket/contract
         racket/format
         racket/generator
         racket/list
         racket/match
         racket/port
         racket/string)

(require "utils.rkt")

(provide
 (struct-out exn:fail:twitter)
 (contract-out
  [access-token (parameter/c string?)]
  [get-timeline (->* (exact-positive-integer?)
                     (#:since_id (or/c exact-positive-integer? false/c))
                     generator?)]
  [get-tweets-by-id (-> (listof exact-positive-integer?) hash?)]
  [get-media (-> string? path-string? void?)]
  [rate-limit-status (->* () ((or/c (listof string?) false/c)) jsexpr?)]))

(define access-token
  (make-parameter "" (λ (x) (format "Authorization: Bearer ~a" x))))

(define api-base-url "https://api.twitter.com/1.1/")

;;; API Utility Functions

;; API error
(struct exn:fail:twitter exn:fail
  (http-code
   http-description
   api-code
   api-message) #:transparent)

;; Returns the twitter API error code and message
(define (extract-error-message json)
  (match json
    [(hash-table ('errors (list (hash-table ('code code) ('message message)))))
     (values code message)]
    [_ (values #f #f)]))

(define (raise-api-error status description [body #f])
  (define-values (api-code api-msg) (extract-error-message body))
  (define error-msg
    (cond [(or api-code api-msg)
           (format "HTTP ~a ~a, twitter api ~a ~a" status description api-code api-msg)]
          [else (format "HTTP ~a ~a" status description)]))
  (raise (exn:fail:twitter error-msg (current-continuation-marks)
                           status description api-code api-msg)))

(define (check-response response)
  (define headers (purify-port response))
  (define-values (status description) (parse-http-status headers))
  (when (not (= status 200))
    (define content-type (extract-field "content-type" headers))
    (cond [(and content-type (string=? content-type "application/json"))
           (raise-api-error status description (read-json response))]
          [else (raise-api-error status description)])))

;; Returns http status code and description from a single header string
(define (parse-http-status http-header)
  (match http-header
    [(pregexp "^HTTP/\\d[.]\\d\\s+(\\d+)\\s+(.*?)\\s*\r\n"
              (list _ code description))
     (values (string->number code) (string-trim description))]))

;; Returns a url for a specified twitter api endpoint
(define (mk-api-url endpoint [params '()])
  (define url (string->url (string-append api-base-url endpoint)))

  ;; Filter parameters that are #f and ensure that query values are strings
  (set-url-query! url (filter-map (match-lambda [(cons k v) (and v (cons k (~a v)))]) params))
  url)

;; Returns port from GET http request to url or raises an exception if
;; the status code is not 200.
(define (http-impure-get url)
  (log-debug (format "Fetching ~a" (url->string url)))
  (get-impure-port url `(,(access-token))))

;; Wrapper function to call http-impure-get.
(define (call/input-url-get url proc)
  (call/input-url url http-impure-get (λ (p) (check-response p) (proc p))))

;; Returns the lowest tweet_id from a list of tweets
(define (get-lowest-id tweets)
  (for/fold ([aux (hash-ref (car tweets) 'id)])
            ([tweet (in-list (cdr tweets))])
    (let ([id (hash-ref tweet 'id)])
      (if (< id aux) id aux))))

;;; API functions

;; Returns a list with maximum 200 tweets for a given user
(define (get-tweets user_id [since_id #f] [max_id #f])
  (define url (mk-api-url "statuses/user_timeline.json"
                          `((count . "200")
                            (trim_user . "true")
                            (exclude_replies . "false")
                            (tweet_mode . "extended")
                            (user_id . ,user_id)
                            (since_id . ,since_id)
                            (max_id . ,max_id))))
  (call/input-url-get url read-json))

;; Returns a generator to automatically traverse the timeline of a
;; given user.
(define (get-timeline user_id #:since_id [since_id #f])
  (generator ()
    (let loop ([max_id #f])
      (define tweets (get-tweets user_id since_id max_id))
      (when (> (length tweets) 0)
        (yield tweets)
        (loop (sub1 (get-lowest-id tweets)))))))

;; Downloads media asset to a given file.
(define (get-media media_url file_path)
  (let ([media (call/input-url-get (string->url media_url) port->bytes)])
    (call-with-output-file file_path (λ (p) write-bytes media p))))

(define (get-tweets-by-id tweet-ids)
  (define ids (string-join (map number->string tweet-ids) ","))
  (define url (mk-api-url "statuses/lookup.json"
                          `((include_entities . "false")
                            (trim_user . "true")
                            (map . "true")
                            (include_ext_alt_text . "false")
                            (include_card_uri . "false")
                            (id . ,ids))))
  (call/input-url-get url read-json))

;; Returns a jsexpr hash table of the current rate limit status for
;; the given resources
(define (rate-limit-status [resources #f])
  (define url
    (mk-api-url "application/rate_limit_status.json"
                `((resources . ,(and resources (string-join resources ","))))))
  (call/input-url-get url read-json))
