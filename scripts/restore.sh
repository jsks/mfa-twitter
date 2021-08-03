#!/usr/bin/env zsh

source ${0:A:h}/base.sh

function help() {
<<EOF
$(usage)

Restores a database from a zstd archive to a running postgres instance.

Options:
    -d | --dbname       Database name to connect to.
    -h | --host         Host address for postgres instance.
    -p | --port         Port that postgres is listening on.
    -u | --user         Username to connect to postgres.
    -W | --password     Password to connect to postgres.
    --help              This help message.
EOF

exit 0
}

function usage() {
    print "Usage: $ZSH_SCRIPT [OPTION]... <archive>"
}

zparseopts -A lopts -E - -help || { usage >&2; exit 127 }
[[ -n ${(k)lopts[--help]} ]] && help

if [[ -f $1 ]]; then
    print "Restoring from $1"
    zstd -c -d $1 | pg_restore -d $PGDATABASE -O
else
    err "Invalid backup archive: $1"
fi
