#lang racket/base

(require rackunit)
(require/expose "../src/commands.rkt" (prune))

(define json (hash 'retweeted_status (hash 'check_str "120" 'check 120)
                   'user (hash 'id 20)
                   'id_str "120"
                   'id 120
                   'source "<a href=\"random\">Source</a>"
                   'foo "bar"))
(define pruned-json (prune json))

(test-begin
  (check-eq? (length (hash-keys pruned-json)) 5)
  (check-eq? (hash-ref pruned-json 'user_id) 20)
  (check-eq? (hash-ref pruned-json 'id) 120)
  (check-equal? (hash-ref pruned-json 'foo) "bar")
  (check-equal? (hash-ref pruned-json 'source) "Source")
  (check-equal? (hash-ref pruned-json 'retweeted_status) (hash 'check 120)))
