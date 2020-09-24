#lang racket/base

(require json
         net/uri-codec
         net/url
         racket/contract
         racket/match
         racket/string)

(require (for-syntax racket/base))

(define-logger twitter-api)

(provide
 (contract-out
  [get-tweets (->* (string?
                    procedure?)
                   (#:max_id (or/c (and/c integer? positive?) false/c)
                    #:since_id (or/c (and/c integer? positive?) false/c))
                   void?)]
  [access-token (parameter/c string?)]))

(define endpoint "https://api.twitter.com/1.1/statuses/user_timeline.json")

(define default-query
  '((count . "200")
    (trim_user . "true")
    (exclude_replies . "false")
    (tweet_mode . "extended")))

(define access-token
  (make-parameter "" (lambda (x) (format "Authorization: Bearer ~a" x))))

(define (http-get url)
  (log-twitter-api-debug "Fetching ~a" (url->string url))
  (get-impure-port url (list (access-token))))

(define (get-lowest-id tweets)
  (for/fold ([aux (hash-ref (car tweets) 'id)])
            ([tweet (in-list (cdr tweets))])
    (let ([id (hash-ref tweet 'id)])
      (if (< id aux) id
          aux))))

(define-syntax (make-url stx)
  (syntax-case stx ()
    [(_ param ...)
     #'(let* ([query (for/list ([sym (in-list '(param ...))]
                                [val (in-list (list param ...))]
                                #:when val)
                       `(,sym . ,(format "~a" val)))]
              [querystr (alist->form-urlencoded (append default-query query))])
         (string->url (format "~a?~a" endpoint querystr)))]))

(define (http-status header-str)
  (regexp-replace #px"HTTP/\\d\\.\\d\\s+(\\d+[^\r\n]+).*" header-str "\\1"))

(define (extract-err json)
  (match (hash-ref json 'errors)
    [(list (hash-table ('code code) ('message message)))
     (format "Error Code ~a, ~a" code message)]
    [_ "No twitter error found"]))

(define (handler port)
  (values (http-status (purify-port port))
          (read-json port)))

(define (get-tweets screen_name proc
                    #:max_id [max_id #f]
                    #:since_id [since_id #f])
  (let*-values ([(url) (make-url screen_name max_id since_id)]
                [(status tweets) (call/input-url url http-get handler)])
    (cond
      [(not (string=? status "200 OK"))
       (log-twitter-api-error "@~a ~a" screen_name (extract-err tweets))]
      [(> (length tweets) 0)
       (log-twitter-api-info "Downloaded ~a tweets from @~a" (length tweets) screen_name)
       (proc tweets)
       (get-tweets screen_name proc
                   #:max_id (- (get-lowest-id tweets) 1)
                   #:since_id since_id)])))
