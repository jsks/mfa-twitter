#!/usr/bin/env zsh
#
# Bootstrap the database either by restoring from the last backup or creating
# all SQL artefacts from scratch.
###

setopt err_exit pipe_fail

root=$(git rev-parse --show-toplevel)
backup="$root/backups/*.tar.gz(om[1])"

# If we have a backup, grab the latest file and restore. Otherwise, create
# database from scratch.
if [[ -z $~backup ]]; then
    print "Restoring from $~backup"
    zstd -c -d $~backup | pg_restore -h localhost -U postgres -d postgres
    exit 0
else
    for i in {types,tables,triggers,views}; do
        f="sql/$i.sql"
        print "Executing $f"
        psql -U postgres -h localhost -f $f
    done

    # Populate accounts from ref file
    psql -h localhost -U postgres -f sql/populate_accounts.sql
fi
