#lang at-exp racket/base

;; TODO: SSL

(require db
         db/util/datetime
         json
         racket/contract
         racket/format
         threading)

(require "utils.rkt")

(provide
 (contract-out
  [call-with-bound-transaction (-> (-> any) any)]
  [init-db (->* ()
                (#:user string?
                 #:password string?
                 #:database string?
                 #:socket (or/c path-string? 'guess #f))
               void?)]
  [connect-friend (-> exact-positive-integer? exact-positive-integer? void?)]
  [insert-profile (-> jsexpr? void?)]
  [profile-exists? (-> exact-positive-integer? (or/c exact-positive-integer? false/c))]
  [get-lapsed-profile (-> (or/c exact-positive-integer? false/c))]
  [insert-tweet (-> jsexpr? void?)]
  [get-accounts (-> (listof vector?))]
  [get-tweet-ids (-> exact-nonnegative-integer? (listof integer?))]
  [touch-tweet (-> exact-positive-integer? void?)]
  [set-tweet-deleted (-> exact-positive-integer? void?)]
  [update-engagement (-> exact-positive-integer? exact-nonnegative-integer?
                         exact-nonnegative-integer? void?)]
  [db-stats (-> hash?)]))

(struct db-settings (user database password socket) #:mutable)
(define creds (db-settings "" "" "" #f))

(define (init-db #:user [user "postgres"]
                 #:password [password "postgres"]
                 #:database [database "postgres"]
                 #:socket [socket #f])
  (set-db-settings-user! creds user)
  (set-db-settings-password! creds password)
  (set-db-settings-database! creds database)
  (set-db-settings-socket! creds socket))

(define db-conn
  (virtual-connection
   (connection-pool
    (λ () (postgresql-connect #:user (db-settings-user creds)
                              #:database (db-settings-database creds)
                              #:password (db-settings-password creds)
                              #:socket (db-settings-socket creds))))))

(define (call-with-bound-transaction proc)
  (call-with-transaction db-conn proc))

(define (get-accounts)
  (let ([query @~a{select screen_name, user_id, max(tweet_id) from accounts
                   left join tweets using (user_id)
                   where accounts.deleted = false and
                       ((valid_to is null or valid_to >= current_date) and
                        (valid_from is null or valid_from <= current_date))
                   group by screen_name, user_id}])
    (for/list ([(screen_name user_id since_id) (in-query db-conn query)])
      (vector screen_name user_id (sql-null->false since_id)))))

(define (get-lapsed-profile)
  (query-maybe-value db-conn @~a{select user_id from full_accounts
                                 where last_checked is null or
                                     last_checked < current_date - interval '1 day'
                                 limit 1}))

(define (get-tweet-ids n)
  (query-list db-conn @~a{select tweet_id from tweets
                          where deleted is false and
                              last_checked < current_date - interval '7 days'
                          limit $1}
              n))

(define (insert-tweet tweet)
  (query-exec db-conn @~a{insert into tweets (tweet_id, user_id, json)
                          values ($1, $2, cast($3::text as jsonb))
                          on conflict do nothing}
              (hash-ref tweet 'id)
              (hash-ref tweet 'user_id)
              (jsexpr->string tweet)))

(define (set-tweet-deleted tweet-id)
  (query-exec db-conn @~a{update tweets set deleted = true where tweet_id = $1} tweet-id))

(define (touch-tweet tweet-id)
  (query-exec db-conn @~a{update tweets set last_checked = current_timestamp where tweet_id = $1} tweet-id))

(define (update-engagement tweet-id favorite-count retweet-count)
  (query-exec db-conn @~a{insert into engagement (tweet_id, favorite_count, retweet_count)
                          values ($1, $2, $3)
                          on conflict (tweet_id) do
                              update set favorite_count = EXCLUDED.favorite_count,
                                         retweet_count = EXCLUDED.retweet_count}
              tweet-id favorite-count retweet-count))

(define (profile-exists? user_id)
  (query-maybe-value db-conn @~a{select user_id from profiles where user_id = $1 limit 1} user_id))

(define (insert-profile user)
  (query-exec db-conn @~a{insert into profiles (user_id, name, screen_name, description,
                                                verified, friends_count, followers_count,
                                                statuses_count, created_at)
                          values ($1, $2, $3, $4, $5, $6, $7, $8, $9)}
   (hash-ref user 'id)
   (hash-ref user 'name)
   (hash-ref user 'screen_name)
   (hash-ref user 'description)
   (hash-ref user 'verified)
   (hash-ref user 'friends_count)
   (hash-ref user 'followers_count)
   (hash-ref user 'statuses_count)
   (srfi-date->sql-timestamp (twitter-date->srfi-date (hash-ref user 'created_at)))))

(define (connect-friend user_id friend_id)
  (query-exec db-conn @~a{insert into friends (user_profile_id, friend_profile_id)
                          values ((select profile_id from profiles where user_id = $1
                                   order by profile_id desc limit 1),
                                  (select profile_id from profiles where user_id = $2
                                   order by profile_id desc limit 1))
                          on conflict do nothing}
              user_id friend_id))

(define (db-stats)
  (define added-tweets
    (~> (query db-conn @~a{select count(*), to_char(added, 'Day') as day
                           from tweets
                           where added >= current_date - interval '7 days'
                           group by day})
        (rows->dict #:key "day" #:value "count")))

  (define checked-tweets
    (~> (query db-conn @~a{select count(*), to_char(added, 'Day') as day
                           from tweets
                           where last_checked >= current_date - interval '7 days'
                           group by day})
        (rows->dict #:key "day" #:value "count")))

  (define n-deleted (query-value db-conn @~a{select count(*) from tweets
                                             where deleted is true}))

  (define n-tweets (query-value db-conn @~a{select count(*) from tweets}))

  (define top-user
    (~> (query db-conn @~a{select screen_name, count(*)
                           from atweets
                           where cast(json->>'created_at' as timestamp) >
                               current_date - interval '7 days'
                           group by screen_name
                           order by count desc
                           limit 1})
        (rows->dict #:key "screen_name" #:value "count")))

  (hash 'latest-tweets added-tweets
        'checked-tweets checked-tweets
        'n-deleted n-deleted
        'n-tweets n-tweets
        'top-user top-user))
