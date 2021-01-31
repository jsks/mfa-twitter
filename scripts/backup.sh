#!/usr/bin/env zsh
#
# Backup script for Postgres DB.
###

emulate -R zsh
setopt err_exit pipe_fail

if [[ $ZSH_VERSION < 5.8 ]]; then
    print "$ZSH_SCRIPT requires >=zsh-5.8"
    exit 113
fi

zmodload zsh/zutil

PG_OPTS='-h ${PGHOST:-localhost} -U ${PGUSER:-postgres} -p ${PORT:-5432}
         -d ${DBNAME:-postgres}'

function err() {
    print -u 2 $*
    exit 127
}

function help() {
<<EOF
$(usage)

Back up a running postgres instance to a zst archive saved in the
given directory.

Options:
    -d | --dbname       Database name to connect to.
    -h | --host         Host address for postgres instance.
    -p | --port         Port that postgres is listening on.
    -u | --user         Username to connect to postgres.
    -W | --password     Password to connect to postgres.
    --help              This help message.
EOF

exit
}

function usage() {
    print "Usage: $ZSH_SCRIPT [OPTION]... [DIR]"
}

zparseopts -A opts -D -E -F - -help u: -user: d: -dbname:  h: -host: \
           p: -port: W: -password: || { usage >&2; exit 127 }

for i in ${(k)opts}; do
    case $i in
        ("--help")
            help;;
        ("--dbname"|"-d")
            DBNAME=$opts[$i];;
        ("--host"|"-h")
            PGHOST=$opts[$i];;
        ("--port"|"-p")
            if [[ $opts[$i] == <-> ]]; then
                PORT=$opts[$i]
            else
                error "Invalid port number: $opts[$i]"
            fi;;
        ("--user"|"-u")
            PGUSER=$opts[$i];;
        ("--password"|"-W")
            PGPASS=$opts[$i]
            PG_OPTS+=' -W $PGPASS';;
    esac
done

[[ ! -d $1 ]] && err "Invalid backup directory: $1"
backup="$1/db_$(date +'%Y-%m-%d').zst"

print "Creating ${(D)backup}"
pg_dump -Fc ${(e)=PG_OPTS} -Z 0 | zstdmt -T0 -16 > $backup
