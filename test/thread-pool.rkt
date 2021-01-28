#lang racket/base

(require "../src/thread-pool.rkt"
         rackunit)

(check-eq? (for/thread/sum ([i 5]) i) 10)
(check-eq? (for/thread/sum ([i 5] [j (in-range 5 10)]) (+ i j)) 45)
(check-eq? (for/thread/sum ([i 10] #:when (even? i)) #:break (> i 5) (* i 2)) 12)

(check-eq? (for/thread/sum #:num-threads 10 ([i 5]) i) 10)
(check-eq? (for/thread/sum #:num-threads (add1 1) ([i 5]) i) 10)

(test-begin
  (define lst (for/thread/list ([i '(1 2 3)]) i))
  (check-eq? 3 (length lst))
  (check-equal? (sort lst <) '(1 2 3)))
