# MFA Twitter Scraping

![ci workflow](https://github.com/jsks/mfa-twitter/actions/workflows/test-and-release.yml/badge.svg)

Project collecting tweets from officially verified foreign ministry
accounts.

## Running Locally

Start PostgreSQL in a local container instance.

```shell
$ podman -p 5432:5432 -e POSTGRES_PASSWORD=<password> -d postgres
```

Add the password to the `.env` credential file as `pg_password` and
ensure that `pg_socket` is `false`. Finally, populate the database
with the necessary SQL artefacts.

```shell
$ scripts/bootstrap.sh --password <password>
$ racket src/main.rkt help
```

## Deployment to Production

Production should be hardcoded as `mfa` in `~/.ssh/config`. To deploy:

```shell
$ make deploy
```

This will first create a distributable bundle with a standalone
executable and necessary shared libraries and runtime files. To ensure
glibc compatibility, the actual `raco exe/distribute` commands will be
run in a [Debian container](https://github.com/jsks/mfa-infra/pkgs/container/racket-build).
Deployment to the remote production server is then handled by ansible
with the `deploy.yml` playbook.

Note, each invocation will rebuild the release tarball from scratch
since `raco` doesn't track changes in source files.

## Tests

Unit tests can be invoked with `Make`.

```shell
$ make test
```

Integration tests targeting the database code are run with the
integration submodule. This requires first a test instance of
PostgreSQL populated with fake data.

```shell
$ podman -p 5432:5432 -e POSTGRES_PASSWORD=<password> -d postgres
$ scripts/bootstrap.sh --testing --password <password>
$ raco test --submodule integration test
```
