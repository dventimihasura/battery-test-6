#!/usr/bin/bash

set -x				# Turn on debug output.
set -e				# Exit if a pipeline fails.
set -o pipefail			# Exit status of a pipeline is the last command.
set -m				# Turn on job control.

# Set up the environment.

export N=10

# Start the database.

export DATABASEID=$(doctl compute droplet create --wait --region sfo3 --ssh-keys ${SSH_KEYID} --size "so-32vcpu-256gb" --image 125035426 --no-header --format "ID" "${HOSTNAME}-db-2")

# Get the database credentials.

export PGHOST=$(doctl compute droplet get ${DATABASEID} -o json | jq -r '.[]|.networks.v4[]|select(.type=="public").ip_address')
export PGUSER=postgres
export PGPORT=5432
export PGDATABASE=postgres
export PGPASSWORD=postgrespassword

# Wait for the database to become available.

sleep 30

# Create the database tables and insert generated data.

cat <<EOF | psql
select format('create table if not exists test_%1\$s (id uuid primary key default gen_random_uuid(), name text)', generate_series(1, ${N}));
\gexec
select format('insert into test_%1\$s (name) select name from (select generate_series(1, %2\$s) id, repeat(md5(random()::text), 2) name) sample', generate_series(1, ${N}), ${N});
\gexec
EOF

# Start the services.

docker run -d --net=host -e HASURA_GRAPHQL_DATABASE_URL="postgres://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}" -e HASURA_GRAPHQL_ENABLE_CONSOLE=true hasura/graphql-engine:latest

# Apply the Hasura metadata config, after the health check passes.

while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://localhost:8082/healthz)" != "200" ]]; do sleep 5; done
curl -s -H 'Content-type: application/json' --data-binary @config.json "http://127.0.0.1:8080/v1/metadata" | jq -r '.'

# Track the tables.

seq 10 | xargs -I{} curl -s -H 'Content-type: application/json' --data '{"type":"pg_track_table","args":{"source":"default","table":"test_{}"}}' "http://127.0.0.1:8080/v1/metadata" | jq -r '.'

# Generate the GraphQL to SQL translations.

seq 10 | head -n1 | xargs -I{} curl -s -H 'Content-type: application/json' --data '{"query":{"query":"{test_{} {name}}"}}' "http://127.0.0.1:8080/v1/graphql/explain" | jq -r '.[]|.sql|"\(.);"' > test.sql

# Run the pgbench load test scripts.

pgbench -n -T10 -c10 -j10 -f test.sql > pgbench.log

# Run the k6 load test scripts.

k6 run -u1 -d10s test.js --summary-export k6.log

# Extract the relevant metrics into a log file.

cat test_1.json | jq -r '"graphql-engine-1: \(.metrics.http_req_duration)"' >> k6.log

# Stop the services.

docker ps -aq | xargs docker rm -f

# Stop the database.

doctl compute droplet delete -f ${DATABASEID}
