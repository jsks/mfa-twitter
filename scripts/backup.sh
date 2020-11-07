#!/usr/bin/env zsh
#
# Backup script for Postgres DB.
###

setopt err_exit pipe_fail

if [[ ! -d $1 ]]; then
    print "Invalid backup directory: $1"
    exit 127
fi

backup="$1/db_$(date +'%Y-%m-%d').zst"

print "Creating ${(D)backup}"
pg_dump -Fc -U postgres -h localhost -Z 0 | zstdmt -T0 -16 > $backup
