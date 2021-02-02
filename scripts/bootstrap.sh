#!/usr/bin/env zsh
#
# Bootstrap the database either by restoring from the last backup or creating
# all SQL artefacts from scratch.
###

emulate -R zsh
setopt err_exit pipe_fail

if [[ $ZSH_VERSION < 5.8 ]]; then
    print "$ZSH_SCRIPT requires >=zsh-5.8"
    exit 113
fi

zmodload zsh/zutil

export PGHOST="localhost"
export PGDATABASE="postgres"
export PGUSER="postgres"

readonly proj_root=${0:a:h:h}

function err() {
    print -u 2 $*
    exit 127
}

function help() {
<<EOF
$(usage)

Populate a running postgres instance. If DIR is provided, restore the latest
zst archive backup from the specified directory. Otherwise, create all SQL
artefacts from scratch using the scripts in $proj_root/sql.

Options:
    -c | --clear        Drop all objects before recreating database.
    -d | --dbname       Database name to connect to.
    -h | --host         Host address for postgres instance.
    -p | --port         Port that postgres is listening on.
    -t | --testing      Insert testing data intended for integration tests.
    -u | --user         Username to connect to postgres.
    -W | --password     Password to connect to postgres.
    --help              This help message.
EOF

exit
}

function usage() {
    print "Usage: $ZSH_SCRIPT [OPTION]... [DIR]"
}

zparseopts -A opts -D -E -F - -help c -clear t -testing u: -user: d: -dbname: \
    h: -host: p: -port: W: -password: || { usage >&2; exit 127 }

for i in ${(k)opts}; do
    case $i in
        ("--help")
            help;;
        ("--dbname"|"-d")
            export PGDATABASE=$opts[$i];;
        ("--host"|"-h")
            export PGHOST=$opts[$i];;
        ("--port"|"-p")
            if [[ $opts[$i] == <-> ]]; then
                export PGPORT=$opts[$i]
            else
                error "Invalid port number: $opts[$i]"
            fi;;
        ("--user"|"-u")
            export PGUSER=$opts[$i];;
        ("--password"|"-W")
            export PGPASSWORD=$opts[$i];;
    esac
done

if [[ ${(k)opts[(i)*-c*]} != "" ]]; then
    read -sq key\?"This is a destructive process. Continue? "
    printf '\n'
    dropdb -w $PGDATABASE
    createdb -w $PGDATABASE
fi

if [[ -n $1 && ${(k)opts[(i)*-t*]} == "" ]]; then
    [[ ! -d $1 ]] && err "Invalid backup directory : $1"

    backup="$1/*.zst(om[1])"
    [[ -z $~backup ]] && err "Unable to find *.zst backup in $1"

    print -- Restoring from $~backup
    zstd -c -d $~backup | pg_restore -w -C
else
    print "Creating database from scratch"
    ! psql -w -c '\q' 2>/dev/null && createdb -w $PGDATABASE
    for i in {types,tables,triggers,views}; psql -w -f sql/$i.sql

    if [[ ${(k)opts[(i)*-t*]} != "" ]]; then
        print "Bootstrapping testing instance"
        psql -w -f test/data/data.sql
    else
        psql -w -f sql/populate_accounts.sql
    fi
fi
