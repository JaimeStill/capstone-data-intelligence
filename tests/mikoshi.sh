#!/usr/bin/env bash
# The harness the tree tests source in place of tests/lib.sh, which it sources: a curl stub that
# emulates Mikoshi's contexts API over a JSON state file of contexts, with its root, its children
# reads in pages of at most 100 by cursor, its create, and its delete confirmed by the descendant
# count, beside a fixture definition and helpers that seed and read the state.
# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

root=00000000-0000-0000-0000-000000000000

# Writes the fixture definition (definition), the stub's state (state) holding the root alone, and
# the curl stub, with MIKOSHI_URL naming the stub's address.
write_fixture() {
  definition=$tmp/fixture/dataset.json
  state=$tmp/mikoshi.json
  mkdir -p "$tmp/fixture"
  export MIKOSHI_URL=http://mikoshi.test:8080 MIKOSHI_STATE=$state
  jq -n --arg root "$root" '{contexts: [{id: $root, parent_id: null, name: "root",
    kind: "explicit", filter: null, created_at: "2026-01-01T00:00:00Z"}]}' >"$state"
  jq -n '{
    contexts: [
      {name: "tour", contexts: [{name: "docs"}, {name: "scan"}]},
      {name: "share", contexts: [{name: "ops", contexts: [{name: "harbor"}]}]},
      {name: "views", contexts: [
        {name: "audio", filter: [{field: "route", op: "eq", value: "audio"}]},
        {name: "long", filter: [
          {field: "route", op: "in", value: ["audio", "video"]},
          {field: "duration", op: "gt", value: 120}
        ]}
      ]}
    ],
    files: [],
    records: [],
    live_steps: [{op: "create", path: "share/drafts"}]
  }' >"$definition"
  write_stub curl "root=$root
$(cat <<'STUB'
method=GET data='' url=''
while (($#)); do
  case $1 in
    -X) method=$2; shift ;;
    --data-raw) data=$2; shift ;;
    -H | -w) shift ;;
    -*) ;;
    *) url=$1 ;;
  esac
  shift
done
route=${url#"$MIKOSHI_URL"}
path=${route%%\?*}
query=${route#"$path"}
query=${query#\?}
reply() {
  printf '%s\n%s' "$2" "$1"
  exit 0
}
problem() {
  reply "$1" "$(jq -nc --argjson status "$1" --arg detail "$2" '{status: $status, detail: $detail}')"
}
param() {
  tr '&' '\n' <<<"$query" | sed -n "s/^$1=//p"
}
known() {
  jq -e --arg id "$1" 'any(.contexts[]; .id == $id)' "$MIKOSHI_STATE" >/dev/null
}
case "$method $path" in
  "GET /api/contexts/"*/children)
    id=${path#/api/contexts/}
    id=${id%/children}
    known "$id" || problem 404 "no context"
    size=$(param size)
    size=${size:-20}
    ((size <= 100)) || problem 400 "size must be at most 100"
    offset=0
    cursor=$(param cursor)
    page=$(param page)
    if [[ -n $cursor ]]; then
      offset=${cursor#o}
    elif [[ -n $page ]]; then
      offset=$(((page - 1) * size))
    fi
    reply 200 "$(jq -c --arg id "$id" --argjson offset "$offset" --argjson size "$size" '
      [.contexts[] | select(.parent_id == $id)] | sort_by(.name) | ($offset + $size) as $end
      | {items: .[$offset:$end], size: $size, more: (length > $end)}
      + (if length > $end then {next: "o\($end)"} else {} end)' "$MIKOSHI_STATE")"
    ;;
  "GET /api/contexts/"*)
    id=${path#/api/contexts/}
    known "$id" || problem 404 "no context"
    reply 200 "$(jq -c --arg id "$id" 'first(.contexts[] | select(.id == $id))' "$MIKOSHI_STATE")"
    ;;
  "POST /api/contexts")
    parent=$(jq -r .parent_id <<<"$data")
    known "$parent" || problem 404 "parent not found"
    jq -e --arg id "$parent" 'any(.contexts[]; .id == $id and .kind == "query")' \
      "$MIKOSHI_STATE" >/dev/null && problem 409 "query parent"
    jq -e --arg id "$parent" --arg name "$(jq -r .name <<<"$data")" \
      'any(.contexts[]; .parent_id == $id and .name == $name)' "$MIKOSHI_STATE" >/dev/null &&
      problem 409 "name taken"
    jq -e '(.kind == "explicit" and .filter == null)
      or (.kind == "query" and (.filter | type) == "array" and length > 0)' <<<"$data" \
      >/dev/null || problem 400 "bad kind or filter"
    id=$(printf '00000000-0000-0000-0001-%012d' "$(jq '[.contexts[].id
      | select(startswith("00000000-0000-0000-0001-"))[24:] | tonumber] | max // 0 | . + 1' \
      "$MIKOSHI_STATE")")
    jq --arg id "$id" --argjson body "$data" '.contexts += [$body + {id: $id,
      created_at: "2026-01-02T00:00:00Z"}]' "$MIKOSHI_STATE" >"$MIKOSHI_STATE.new"
    mv "$MIKOSHI_STATE.new" "$MIKOSHI_STATE"
    reply 201 "$(jq -c --arg id "$id" 'first(.contexts[] | select(.id == $id))' "$MIKOSHI_STATE")"
    ;;
  "DELETE /api/contexts/"*)
    id=${path#/api/contexts/}
    [[ $id == "$root" ]] && problem 409 "the root context is fixed"
    known "$id" || problem 404 "no context"
    confirm=$(param confirm)
    [[ $query != *confirm=* || $confirm =~ ^[0-9]+$ ]] || problem 400 "bad confirm"
    subtree=$(jq -c --arg id "$id" '.contexts as $all
      | [$id | recurse(. as $p | $all[] | select(.parent_id == $p) | .id)]' "$MIKOSHI_STATE")
    count=$(($(jq length <<<"$subtree") - 1))
    if ((${confirm:-0} != count)); then
      reply 409 "$(jq -nc --argjson count "$count" '{status: 409,
        detail: "the delete is not confirmed", descendants: $count}')"
    fi
    jq --argjson subtree "$subtree" '.contexts |= map(select(.id | IN($subtree[]) | not))' \
      "$MIKOSHI_STATE" >"$MIKOSHI_STATE.new"
    mv "$MIKOSHI_STATE.new" "$MIKOSHI_STATE"
    reply 204 ""
    ;;
esac
problem 405 "the stub takes no $method $path"
STUB
)"
}

# Adds a context to the stub's state and prints its id: seed <id> <parent id> <name> [filter].
seed() {
  local kind=explicit filter=${4:-null}
  [[ $filter == null ]] || kind=query
  jq --arg id "$1" --arg parent "$2" --arg name "$3" --arg kind "$kind" --argjson filter "$filter" \
    '.contexts += [{id: $id, parent_id: $parent, name: $name, kind: $kind, filter: $filter,
    created_at: "2026-01-01T00:00:00Z"}]' "$state" >"$state.new"
  mv "$state.new" "$state"
}

# Prints the context at the path given in the stub's state, as {parent, kind, filter}, the parent
# as its name, or nothing when there is none.
context_at() {
  jq -c --arg path "$1" '.contexts as $all
    | def at($id; $names): if $names == [] then first($all[] | select(.id == $id))
        else first($all[] | select(.parent_id == $id and .name == $names[0])) as $c
        | at($c.id; $names[1:]) end;
    (at("'"$root"'"; $path | split("/")) // empty)
    | {parent: (.parent_id as $p | first($all[] | select(.id == $p)).name), kind, filter}' "$state"
}
