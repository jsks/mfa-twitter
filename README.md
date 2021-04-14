# MFA Twitter Scraping

![ci workflow](https://github.com/jsks/mfa-twitter/actions/workflows/ci.yml/badge.svg)

Project collecting tweets from officially verified foreign ministry
accounts.

## Database Setup

``` shell
$ podman run -p 5432:5432 -d postgres
$ scripts/bootstrap.sh
```

## Running

``` shell
$ raco make src/main.rkt
$ raco exe -l -o mfa src/main.rkt
$ ./mfa -c .env
```
