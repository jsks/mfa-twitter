# MFA Twitter Scraping

Project collecting tweets from officially verified foreign ministry
accounts.

## Database Setup

``` shell
$ psql -h <postgres-host> -U <postgres-user> -d postgres -f sql/init.sql
$ psql -h <postgres-host> -U <postgres-user> -d postgres <<EOF
\copy accounts (user_id, screen_name, country, valid_from, valid_to, account_type)
    from 'refs/accounts.csv' delimiter ',' csv header
EOF
```

## Running

``` shell
$ raco exe -o mfa src/main.rkt
$ ./mfa -c .env
```
