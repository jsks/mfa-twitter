#!/usr/bin/env zsh
#
# Bootstrap SQL structures in database.
###

source ${0:A:h}/base.sh

function help() {
<<EOF
$(usage)

Populate a running postgres instance with sql artefacts.

Options:
    -a | --accounts     Reference file for target accounts.
    -d | --dbname       Database name to connect to.
    -h | --host         Host address for postgres instance.
    -p | --port         Port that postgres is listening on.
    -s | --sql          Data directory for sql artefacts.
    -t | --testing      Insert testing data intended for integration tests.
                        NOTE: this is a destructive process!
    -u | --user         Username to connect to postgres.
    -W | --password     Password to connect to postgres.
    --help              This help message.
EOF

exit 0
}

function usage() {
    print "Usage: $ZSH_SCRIPT [OPTION]... [DIR]"
}

zparseopts -A lopts -D -E - -help t -testing a: -accounts: s: -sql: \
    || { usage >&2; exit 127 }
[[ ${(k)lopts[--help]} ]] && help

accounts_file=${(v)lopts[(i)*-a*]:-refs/accounts.csv}
[[ ! -f $accounts_file ]] && err "Invalid accounts file: $accounts_file"

sql_dir=${(v)lopts[(i)*-s*]:-sql}
[[ ! -d $sql_dir ]] && err "Invalid sql directory: $sql_dir"

! psql -w -c '\q' && createdb -w $PGDATABASE
for i in {types,tables,triggers,views,roles}; do
    psql -w -f $sql_dir/$i.sql
done

if [[ ${(k)lopts[(i)*-t*]} != "" ]]; then
    print "Populating database with test data"
    psql -w -f test/data/data.sql
else
    psql -v accounts_file=$accounts_file -w -f $sql_dir/populate_accounts.sql
fi
