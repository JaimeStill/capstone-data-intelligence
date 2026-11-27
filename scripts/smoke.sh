#!/usr/bin/env bash
# smoke proves each service of the running compose stack does its job, using only the tools inside
# the service's own container, and exits non-zero at the first proof that fails. nats creates a
# JetStream stream on file storage and deletes it, speaking JetStream's API over the NATS text
# protocol through the container's busybox nc. postgres-bunrei and postgres-mikoshi each create the
# vector extension through the container's psql inside a transaction they roll back, then confirm
# the server kept no vector extension. seaweedfs creates a bucket and puts an object through the
# container's curl, signing each request with --aws-sigv4, recreates the service's container so
# only its volume carries the object, reads the object back, and deletes both; a bucket left by an
# earlier failed run is emptied and deleted first.
# Run it through `mise run stack:smoke` once `mise run stack:up` has the stack healthy.
#
# usage: scripts/smoke.sh
set -euo pipefail
cd "$MISE_PROJECT_ROOT"

fail() {
	echo "smoke: $1" >&2
	exit 1
}

nats_request() {
	local subject=$1 payload=$2 line reply="" fd
	coproc NATS { docker compose exec -T nats nc 127.0.0.1 4222; }
	printf 'CONNECT {"verbose":false}\r\nSUB _INBOX.smoke 1\r\nPUB %s _INBOX.smoke %d\r\n%s\r\n' \
		"$subject" "${#payload}" "$payload" >&"${NATS[1]}"
	while IFS= read -r -t 10 line <&"${NATS[0]}"; do
		if [[ $line == MSG\ * ]]; then
			IFS= read -r -t 10 reply <&"${NATS[0]}" || true
			break
		fi
	done
	fd=${NATS[1]}
	exec {fd}>&-
	wait "$NATS_PID" || true
	echo "${reply%$'\r'}"
}

smoke_nats() {
	local config='{"name":"SMOKE","subjects":["smoke.>"],"storage":"file"}' reply
	reply=$(nats_request "\$JS.API.STREAM.CREATE.SMOKE" "$config")
	if [ -z "$reply" ] || [[ $reply == *'"error"'* ]] || [[ $reply != *'"storage":"file"'* ]]; then
		fail "nats: stream create failed: ${reply:-no reply}"
	fi
	reply=$(nats_request "\$JS.API.STREAM.DELETE.SMOKE" '')
	if [[ $reply != *'"success":true'* ]]; then
		fail "nats: stream delete failed: ${reply:-no reply}"
	fi
	echo "smoke: nats: JetStream created and deleted a file-storage stream"
}

psql_app() {
	local service=$1
	shift
	docker compose exec -T "$service" psql -h 127.0.0.1 -U app -d app -v ON_ERROR_STOP=1 -qAt "$@"
}

smoke_postgres() {
	local service version kept
	for service in postgres-bunrei postgres-mikoshi; do
		version=$(psql_app "$service" -c 'BEGIN' -c 'CREATE EXTENSION vector' \
			-c "SELECT extversion FROM pg_extension WHERE extname = 'vector'" -c 'ROLLBACK' 2>&1) ||
			fail "$service: CREATE EXTENSION vector failed: $version"
		kept=$(psql_app "$service" -c "SELECT count(*) FROM pg_extension WHERE extname = 'vector'" 2>&1) ||
			fail "$service: extension query failed: $kept"
		if [ "$kept" != 0 ]; then
			fail "$service: the vector extension outlived its rollback: $kept"
		fi
		echo "smoke: $service: pgvector $version created and rolled back"
	done
}

s3() {
	docker compose exec -T seaweedfs curl --silent --show-error --fail \
		--aws-sigv4 aws:amz:us-east-1:s3 --user admin:secret "$@"
}

smoke_seaweedfs() {
	local bucket=http://127.0.0.1:8333/smoke content="smoke $$ $RANDOM" output
	s3 --output /dev/null -X DELETE "$bucket/object" 2>/dev/null || true
	s3 --output /dev/null -X DELETE "$bucket" 2>/dev/null || true
	output=$(s3 -X PUT "$bucket" 2>&1) || fail "seaweedfs: bucket create failed: $output"
	output=$(s3 -X PUT --data-binary "$content" "$bucket/object" 2>&1) ||
		fail "seaweedfs: object put failed: $output"
	output=$(docker compose up -d --wait --force-recreate seaweedfs 2>&1) ||
		fail "seaweedfs: not healthy after recreate: $output"
	output=$(s3 "$bucket/object" 2>&1) || fail "seaweedfs: object get failed: $output"
	if [ "$output" != "$content" ]; then
		fail "seaweedfs: object read back as '$output', not '$content'"
	fi
	output=$(s3 -X DELETE "$bucket/object" 2>&1) || fail "seaweedfs: object delete failed: $output"
	output=$(s3 -X DELETE "$bucket" 2>&1) || fail "seaweedfs: bucket delete failed: $output"
	echo "smoke: seaweedfs: an object survived its container's recreation, then it and its bucket were deleted"
}

smoke_nats
smoke_postgres
smoke_seaweedfs
