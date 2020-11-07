#!/usr/bin/env zsh
#
# Bootstrap the database either by restoring from the last backup or creating
# all SQL artefacts from scratch.
###

setopt err_exit pipe_fail

function err() {
    print $* >&2
    exit 127
}

# If we're given a directory, attempt to find the latest backup and restore.
# Otherwise, create database from scratch.
if [[ -z $1 ]]; then
    [[ ! -d $1 ]] && err "Invalid backup directory: $1"

    backup="$1/*.zst(om[1])"
    [[ -n $~backup ]] && err "Unable to find latest backup in $1"

    print "Restoring from $~backup"
    zstd -c -d $~backup | pg_restore -h localhost -U postgres -d postgres
else
    print "Creating database from scratch"
    for i in {types,tables,triggers,views}; do
        print "Executing $i.sql"
        psql -U postgres -h localhost -f sql/$i.sql
    done

    # Populate accounts from ref file
    psql -h localhost -U postgres -f sql/populate_accounts.sql
fi
