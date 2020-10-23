#!/usr/bin/env zsh
#
# Backup script for Postgres DB.
###

setopt err_exit pipe_fail

root=$(git rev-parse --show-toplevel)
backup="$root/backups/db_$(date +'%Y-%m-%d').zst"

print "Creating ${(D)backup}"
pg_dump -Fc -U postgres -h localhost -Z 0 | zstdmt -T0 -16 > $backup
