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

(provide
 (contract-out
  [access-token (parameter/c string?)]
  [deleted? (-> (listof exact-positive-integer?) (listof boolean?))]
  [get-timeline (->* (exact-positive-integer?)
                     (#:since_id (or/c exact-positive-integer? false/c))
                     generator?)]
  [get-media (-> string? path-string? void?)]
  [rate-limit-status (-> (or/c (listof string?) false/c) jsexpr?)]))

(define access-token
  (make-parameter "" (λ (x) (format "Authorization: Bearer ~a" x))))

(define api-base-url "https://api.twitter.com/1.1/")

;;; Utility Functions

;; Returns a url for a specified twitter api endpoint
(define (mk-api-url endpoint [params '()])
  (define url (string->url (string-append api-base-url endpoint)))

  ;; Filter parameters that are #f and ensure that query values are strings
  (set-url-query! url (filter-map (match-lambda [(cons k v) (and v (cons k (~a v)))]) params))
  url)

;; Returns the http status code from a single header string
(define (parse-http-status http-header)
  (string->symbol (second (string-split http-header " "))))

;; Returns port from GET http request to url or raises an exception if
;; the status code is not 200.
(define (http-impure-get url)
  (log-debug (format "Fetching ~a" (url->string url)))
  (get-impure-port url `(,(access-token))))

;; Wrapper function to call http-impure-get.
(define (call/input-url-get url proc)
  (call/input-url
   url http-impure-get
   (λ (port)
     (let ([status (parse-http-status (purify-port port))])
       (if (eq? status '|200|)
           (proc port)
           (error (format "(http status ~a) ~a" status (extract-api-error port))))))))

;; Returns the lowest tweet_id from a list of tweets
(define (get-lowest-id tweets)
  (for/fold ([aux (hash-ref (car tweets) 'id)])
            ([tweet (in-list (cdr tweets))])
    (let ([id (hash-ref tweet 'id)])
      (if (< id aux) id aux))))

;; Returns the twitter API error code and message as a string
(define (extract-api-error port)
  (match (hash-ref (read-json port) 'errors #f)
    [(list (hash-table ('code code) ('message message)))
     (format "error code ~a -> ~a" code message)]
    [_ "no associated twitter API error code"]))

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
      (let ([tweets (get-tweets user_id since_id max_id)])
        (cond [(> (length tweets) 0)
               (yield tweets)
               (loop (sub1 (get-lowest-id tweets)))]
              [else (yield #f)])))))

;; Downloads media asset to a given file.
(define (get-media media_url file_path)
  (let* ([url (string->url media_url)]
         [media (call/input-url-get url port->bytes)])
    (call-with-output-file file_path (λ (p) write-bytes media p))))

;; Returns a list of booleans whether a tweet has been deleted
(define (deleted? tweet-ids)
  (define ids (string-join (map number->string tweet-ids) ","))
  (define url (mk-api-url "statuses/lookup.json"
                          `((include_entities . "false")
                            (trim_user . "true")
                            (map . "true")
                            (include_ext_alt_text . "false")
                            (include_card_uri . "false")
                            (id . ,ids))))
  (let ([results (call/input-url-get url read-json)])
    (hash-map (hash-ref results 'id) (λ (k v) (eq? v (json-null))))))

;; Returns a jsexpr hash table of the current rate limit status for
;; the given resources
(define (rate-limit-status [resources #f])
  (define url (mk-api-url "application/rate_limit_status.json"
                          `((resources . ,(and resources (string-join resources ","))))))
  (call/input-url-get url read-json))
