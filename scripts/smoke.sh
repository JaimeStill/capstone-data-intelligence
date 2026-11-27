#!/usr/bin/env bash
# smoke proves each service of the running compose stack does its job, using only the tools inside
# the service's own container, and exits non-zero at the first proof that fails. nats creates a
# JetStream stream on file storage and deletes it, speaking JetStream's API over the NATS text
# protocol through the container's busybox nc. postgres-bunrei and postgres-mikoshi each create the
# vector extension through the container's psql inside a transaction they roll back, so neither
# server keeps it.
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

smoke_postgres() {
	local service output
	for service in postgres-bunrei postgres-mikoshi; do
		if ! output=$(docker compose exec -T "$service" psql -h 127.0.0.1 -U app -d app -v ON_ERROR_STOP=1 -qAt \
			-c 'BEGIN' -c 'CREATE EXTENSION vector' -c "SELECT extversion FROM pg_extension WHERE extname = 'vector'" \
			-c 'ROLLBACK' 2>&1); then
			fail "$service: CREATE EXTENSION vector failed: $output"
		fi
		echo "smoke: $service: pgvector $output created and rolled back"
	done
}

smoke_nats
smoke_postgres
