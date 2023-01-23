#!/usr/bin/bash

set-x

export DATABASEID=$(doctl compute droplet create --wait --region sfo3 --ssh-keys ${KEYID} --size "so-32vcpu-256gb" --image 125035426 --no-header --format "ID" "${HOSTNAME}-db-2")
export PGHOST=$(curl -s -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" "https://api.digitalocean.com/v2/droplets/${DATABASEID}" | jq -r '.droplet.networks.v4[]|select(.type=="public").ip_address')
export PGUSER=postgres
export PGPORT=5432
export PGDATABASE=postgres
export PGPASSWORD=postgrespassword
docker run -d --net=host -e HASURA_GRAPHQL_DATABASE_URL=postgres://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE} -e HASURA_GRAPHQL_ENABLE_CONSOLE=true hasura/graphql-engine:latest
sleep 10
cat <<EOF | psql
select format('create table if not exists test_%1\$s (id uuid primary key default gen_random_uuid(), name text)', generate_series(1, ${N}));
\gexec
select format('insert into test_%1\$s (name) select name from (select generate_series(1, %2\$s) id, repeat(md5(random()::text), 2) name) sample', generate_series(1, ${N}), ${N});
\gexec
EOF
curl -s -H 'Content-type: application/json' --data-binary @config.json "http://127.0.0.1:8080/v1/metadata" | jq -r '.'
seq 10 | xargs -I{} curl -s -H 'Content-type: application/json' --data '{"type":"pg_track_table","args":{"source":"default","table":"test_{}"}}' "http://127.0.0.1:8080/v1/metadata" | jq -r '.'
seq 10 | xargs -I{} curl -s -H 'Content-type: application/json' --data '{"query":{"query":"{test_{} {name}}"}}' "http://127.0.0.1:8080/v1/graphql/explain" | jq -r '.[]|.sql|"\(.);"' > test.sql
pgbench -n -T10 -j10 -c10 -Msimple -f test.sql >> pgbench.log
pgbench -n -T10 -j10 -c10 -Mextended -f test.sql >> pgbench.log
pgbench -n -T10 -j10 -c10 -Mprepared -f test.sql >> pgbench.log
k6 run -u50 -d10s test.js --summary-export k6.log
docker ps -aq | xargs docker rm -f
curl -s -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" -X DELETE "https://api.digitalocean.com/v2/droplets/${DATABASEID}"

