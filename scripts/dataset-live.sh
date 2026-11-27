#!/usr/bin/env bash
# dataset-live proves the dataset's tree load and reset against a real Mikoshi: it runs
# `dataset tree load`, a second `tree load` that creates nothing, `tree reset`, and a last
# `tree load` that creates every declared context again, asserting each step's summary counts,
# then reads the tree back through Mikoshi's contexts API and asserts each declared context exists
# at its path with its declared kind and filter. It prints each step's output and exits non-zero at
# the first mismatch. The reset deletes the definition's top-level contexts with their subtrees and
# leaves every other context in Mikoshi as it is.
# Run it through `mise run dataset:live`; `mise run check` never runs it.
#
# Prerequisites, none of which it starts:
# - the root's compose stack, through `mise run stack:up`, for postgres-mikoshi on 127.0.0.1:5442;
# - Mikoshi running on the host against that server, its MIKOSHI_DATABASE_PORT set to 5442 and its
#   MIKOSHI_DATABASE_PASSWORD to the stack's development password, app;
# - MIKOSHI_URL naming that Mikoshi, http://localhost:8080 unless set;
# - curl and jq on PATH.
#
# usage: scripts/dataset-live.sh [definition], dataset/dataset.json unless given
set -euo pipefail

root=$(cd "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck source=lib/dataset.sh
source "$root/lib/dataset.sh"

definition=${1:-$root/dataset/dataset.json}
url=${MIKOSHI_URL:-http://localhost:8080}

fail() {
  echo "dataset-live: $1" >&2
  exit 1
}

step() {
  local want=$1 output status=0
  shift
  echo "== dataset $*"
  output=$("$root/bin/dataset" "$@" "$definition") || status=$?
  printf '%s\n' "$output"
  ((status == 0)) || fail "dataset $* exited $status"
  [[ ${output##*$'\n'} == "$definition: $want" ]] ||
    fail "dataset $* summary is [${output##*$'\n'}], want [$definition: $want]"
}

if ! reason=$(mikoshi_call GET "/api/contexts/$(mikoshi_root)"); then
  fail "Mikoshi does not answer at $url: $reason"
fi
"$root/bin/dataset" tree check "$definition" >/dev/null || fail "$definition is not valid"

total=$(dataset_tree_jq '[load_rows] | length' "$definition")
tops=$(dataset_tree_jq '.contexts | length' "$definition")

echo "== dataset tree load"
first=$("$root/bin/dataset" tree load "$definition") || fail "dataset tree load exited $?"
printf '%s\n' "$first"
summary=${first##*$'\n'}
[[ $summary =~ ^.*:\ ([0-9]+)\ created,\ ([0-9]+)\ exists,\ 0\ differ,\ 0\ skipped$ ]] &&
  ((BASH_REMATCH[1] + BASH_REMATCH[2] == total)) ||
  fail "dataset tree load summary is [$summary], want $total created or existing, none differing"

step "0 created, $total exists, 0 differ, 0 skipped" tree load
step "$tops deleted, 0 absent" tree reset
step "$total created, 0 exists, 0 differ, 0 skipped" tree load

echo "== the tree through the API"
declare -A ids=([/]=$(mikoshi_root)) children=()
rows=$(dataset_tree_jq load_rows "$definition")
while IFS=$'\x1f' read -r context parent cname kind filter <&3; do
  [[ -n $context ]] || continue
  parent_id=${ids[/$parent]}
  if [[ -z ${children[$parent_id]:-} ]]; then
    children[$parent_id]=$(mikoshi_children "$parent_id") ||
      fail "context $context: ${children[$parent_id]}"
  fi
  found=$(jq -c --arg name "$cname" 'first(.[] | select(.name == $name)) // empty' \
    <<<"${children[$parent_id]}")
  [[ -n $found ]] || fail "context $context: absent after the load"
  # shellcheck disable=SC2016 # The $ names are jq's variables, not the shell's.
  reason=$(dataset_tree_jq 'context_difference($kind; $filter)' --arg kind "$kind" \
    --argjson filter "$filter" <<<"$found")
  [[ -z $reason ]] || fail "context $context: $reason"
  ids[/$context]=$(jq -r .id <<<"$found")
  echo "context $context: $kind, as declared"
done 3<<<"$rows"

echo "dataset-live: passed, $total contexts against $url"
