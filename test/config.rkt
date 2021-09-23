#lang racket/base

(require rackunit)
(require/expose "../src/config.rkt" (config-line? load-config parse-line))

(check-pred config-line? "pg_database = test")
(check-pred config-line? "pg_database = \"test\" # Comment")
(check-false (config-line? "# pg_database = test"))

(define-syntax-rule (check-config-line line key value)
  (test-case (string-append "Config line -> " line)
    (let-values ([(k v) (parse-line line)])
      (check-equal? k key)
      (check-equal? v value))))

(check-config-line "pg_user = \"database\"" 'pg_user "database")
(check-config-line "pg_user user" '|pg_user user| #f)
(check-config-line "= user" '|| "user")
(check-config-line "pg_user = " 'pg_user "")
(check-config-line "pg_user=user" 'pg_user "user")

(check-config-line "pg_socket = \"true\"" 'pg_socket 'guess)
(check-config-line "pg_socket = false" 'pg_socket #f)
(check-config-line "pg_socket = \"/tmp/pg.socket\"" 'pg_socket "/tmp/pg.socket")

(check-not-exn (λ () (load-config "data/test.conf")))
(check-pred hash? (load-config "data/test.conf"))
(check-exn exn:fail:user? (λ () (load-config "data/test-bad.conf")))
