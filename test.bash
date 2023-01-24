#!/usr/bin/bash

set -x

export N=10
export DATABASEID=$(doctl compute droplet create --wait --region sfo3 --ssh-keys ${SSH_KEYID} --size "so-32vcpu-256gb" --image 125035426 --no-header --format "ID" "${HOSTNAME}-db-2")
export PGHOST=$(doctl compute droplet get ${DATABASEID} -o json | jq -r '.[]|.networks.v4[]|select(.type=="public").ip_address')
export PGUSER=postgres
export PGPORT=5432
export PGDATABASE=postgres
export PGPASSWORD=postgrespassword
sleep 30
cat <<EOF | psql
select format('create table if not exists test_%1\$s (id uuid primary key default gen_random_uuid(), name text)', generate_series(1, ${N}));
\gexec
select format('insert into test_%1\$s (name) select name from (select generate_series(1, %2\$s) id, repeat(md5(random()::text), 2) name) sample', generate_series(1, ${N}), ${N});
\gexec
EOF
docker-compuse up -d -e PGHOST=${PGHOST} -e PGPORT=${PGPORT} -e PGUSER=${PGUSER} -e PGDATABASE=${PGDATABASE} -e PGPASSWORD=${PGPASSWORD}
# docker run -d --net=host -e HASURA_GRAPHQL_DATABASE_URL="postgres://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}" -e HASURA_GRAPHQL_ENABLE_CONSOLE=true hasura/graphql-engine:latest
sleep 10
curl -s -H 'Content-type: application/json' --data-binary @config.json "http://127.0.0.1:8080/v1/metadata" | jq -r '.'
seq 10 | xargs -I{} curl -s -H 'Content-type: application/json' --data '{"type":"pg_track_table","args":{"source":"default","table":"test_{}"}}' "http://127.0.0.1:8080/v1/metadata" | jq -r '.'
seq 10 | head -n1 | xargs -I{} curl -s -H 'Content-type: application/json' --data '{"query":{"query":"{test_{} {name}}"}}' "http://127.0.0.1:8080/v1/graphql/explain" | jq -r '.[]|.sql|"\(.);"' > test.sql
pgbench -n -T10 -c10 -j10 -f test.sql > pgbench.log
k6 run -u1 -d10s test.js --summary-export k6.log
docker ps -aq | xargs docker rm -f
doctl compute droplet delete -f ${DATABASEID}
