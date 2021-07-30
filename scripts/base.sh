#!/usr/bin/env zsh

emulate -R zsh
setopt err_exit pipe_fail

zmodload zsh/zutil

export PGHOST="localhost"
export PGDATABASE="postgres"
export PGUSER="postgres"

function err() {
    print -u 2 $*
    exit 127
}

zparseopts -A opts -D -E - u: -user: d: -dbname: h: -host: p: -port: W: -password:

for i in ${(k)opts}; do
    case $i in
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
