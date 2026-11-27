#!/usr/bin/env bash
# Tests for dataset tree load (lib/tree.sh, lib/mikoshi.sh), against a fixture definition and the
# real dataset/dataset.json: a curl stub emulates Mikoshi's contexts API, its root, its children
# reads in pages of at most 100 by cursor, and its create, over a state file of contexts.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

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
  write_stub curl "$(cat <<'STUB'
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
    id=$(printf '00000000-0000-0000-0001-%012d' "$(jq '.contexts | length' "$MIKOSHI_STATE")")
    jq --arg id "$id" --argjson body "$data" '.contexts += [$body + {id: $id,
      created_at: "2026-01-02T00:00:00Z"}]' "$MIKOSHI_STATE" >"$MIKOSHI_STATE.new"
    mv "$MIKOSHI_STATE.new" "$MIKOSHI_STATE"
    reply 201 "$(jq -c --arg id "$id" 'first(.contexts[] | select(.id == $id))' "$MIKOSHI_STATE")"
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

# Prints the number of creates the stub received.
creates() {
  calls | grep -c -- '-X POST'
}

test_an_empty_store_gets_every_declared_context() {
  write_fixture
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_equal "out" "$out" "context tour: created
context tour/docs: created
context tour/scan: created
context share: created
context share/ops: created
context share/ops/harbor: created
context views: created
context views/audio: created
context views/long: created
$definition: 9 created, 0 exists, 0 differ, 0 skipped"
  assert_equal "creates" "$(creates)" 9
  assert_equal "tour" "$(context_at tour)" '{"parent":"root","kind":"explicit","filter":null}'
  assert_equal "harbor" "$(context_at share/ops/harbor)" \
    '{"parent":"ops","kind":"explicit","filter":null}'
  assert_equal "audio" "$(context_at views/audio)" \
    '{"parent":"views","kind":"query","filter":[{"field":"route","op":"eq","value":"audio"}]}'
  assert_equal "long" "$(context_at views/long | jq -c .filter)" \
    '[{"field":"route","op":"in","value":["audio","video"]},{"field":"duration","op":"gt","value":120}]'
  assert_equal "live-step context" "$(context_at share/drafts)" ""
}

test_a_second_load_creates_nothing() {
  write_fixture
  run_dataset tree load "$definition"
  : >"$tmp/calls"
  cp "$state" "$tmp/before.json"
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 0
  assert_equal "creates" "$(creates)" 0
  assert_equal "exists lines" "$(grep -c ': exists$' <<<"$out")" 9
  assert_equal "summary" "$(tail -n 1 <<<"$out")" \
    "$definition: 0 created, 9 exists, 0 differ, 0 skipped"
  assert_equal "state" "$(cat "$state")" "$(cat "$tmp/before.json")"
}

test_only_the_missing_contexts_are_created() {
  write_fixture
  seed a0000000-0000-0000-0000-000000000001 "$root" tour
  seed a0000000-0000-0000-0000-000000000002 a0000000-0000-0000-0000-000000000001 docs
  seed a0000000-0000-0000-0000-000000000003 "$root" views
  seed a0000000-0000-0000-0000-000000000004 a0000000-0000-0000-0000-000000000003 long \
    '[{"value":120.0,"op":"gt","field":"duration"},{"field":"route","op":"in","value":["video","audio"]}]'
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_equal "creates" "$(creates)" 5
  assert_contains "tour" "$out" "context tour: exists"
  assert_contains "docs" "$out" "context tour/docs: exists"
  assert_contains "scan" "$out" "context tour/scan: created"
  assert_contains "long, a filter of the same conditions" "$out" "context views/long: exists"
  assert_contains "audio" "$out" "context views/audio: created"
  assert_equal "summary" "$(tail -n 1 <<<"$out")" \
    "$definition: 5 created, 4 exists, 0 differ, 0 skipped"
  assert_equal "scan's parent" "$(context_at tour/scan | jq -r .parent)" tour
}

test_a_context_that_differs_is_reported_and_left_alone() {
  write_fixture
  seed a0000000-0000-0000-0000-000000000001 "$root" share \
    '[{"field":"route","op":"eq","value":"text"}]'
  seed a0000000-0000-0000-0000-000000000003 "$root" views
  seed a0000000-0000-0000-0000-000000000004 a0000000-0000-0000-0000-000000000003 audio \
    '[{"field":"route","op":"eq","value":"video"}]'
  seed a0000000-0000-0000-0000-000000000005 a0000000-0000-0000-0000-000000000003 long
  cp "$state" "$tmp/before.json"
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 1
  assert_contains "share" "$err" \
    "dataset: $definition: context share: exists with kind query, the definition declares kind explicit"
  assert_contains "audio" "$err" \
    "dataset: $definition: context views/audio: exists with filter [{\"field\":\"route\",\"op\":\"eq\",\"value\":\"video\"}]"
  assert_contains "long" "$err" "dataset: $definition: context views/long: exists with kind explicit"
  assert_contains "under share" "$err" \
    "dataset: $definition: context share/ops: not loaded, since share differs"
  assert_contains "under share/ops" "$err" \
    "dataset: $definition: context share/ops/harbor: not loaded, since share/ops differs"
  assert_equal "summary" "$(tail -n 1 <<<"$out")" \
    "$definition: 3 created, 1 exists, 3 differ, 2 skipped"
  assert_equal "seeded contexts" \
    "$(jq -c '.contexts[] | select(.id | startswith("a"))' "$state")" \
    "$(jq -c '.contexts[] | select(.id | startswith("a"))' "$tmp/before.json")"
  assert_equal "calls beyond read and create" \
    "$(calls | grep -Ev -- '-X (GET|POST) ' || true)" ""
}

test_a_parent_with_more_than_one_page_of_children_matches_by_name() {
  write_fixture
  jq --arg root "$root" '.contexts += [range(150) as $i | {
    id: ("b0000000-0000-0000-0000-\($i | tostring | ("000000000000" + .)[-12:])"),
    parent_id: $root, name: "aaa-\($i | tostring | ("000" + .)[-3:])", kind: "explicit",
    filter: null, created_at: "2026-01-01T00:00:00Z"}]' "$state" >"$state.new"
  mv "$state.new" "$state"
  seed a0000000-0000-0000-0000-000000000001 "$root" views
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_contains "views, on the second page" "$out" "context views: exists"
  assert_contains "second page read" "$(calls)" "/children?size=100&cursor=o100"
  assert_equal "top-level views" \
    "$(jq '[.contexts[] | select(.parent_id == "'"$root"'" and .name == "views")] | length' "$state")" 1
}

test_contexts_outside_the_definition_are_untouched() {
  write_fixture
  seed a0000000-0000-0000-0000-000000000001 "$root" foreign
  seed a0000000-0000-0000-0000-000000000002 a0000000-0000-0000-0000-000000000001 inner
  seed a0000000-0000-0000-0000-000000000003 "$root" tour
  seed a0000000-0000-0000-0000-000000000004 a0000000-0000-0000-0000-000000000003 extra
  cp "$state" "$tmp/before.json"
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 0
  assert_equal "seeded contexts" \
    "$(jq -c '.contexts[] | select(.id | startswith("a"))' "$state")" \
    "$(jq -c '.contexts[] | select(.id | startswith("a"))' "$tmp/before.json")"
  assert_equal "foreign in output" "$(grep -c 'foreign\|extra' <<<"$out")" 0
}

test_an_unreachable_api_is_refused_naming_mikoshi_url() {
  write_fixture
  write_stub curl 'exit 7'
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 1
  assert_equal "out" "$out" ""
  assert_equal "err" "$err" "dataset: $definition: cannot reach Mikoshi at http://mikoshi.test:8080; start it, or set MIKOSHI_URL to its address"
}

test_an_invalid_definition_is_refused_before_any_call() {
  write_fixture
  jq '.contexts[0].name = "a/b"' "$definition" >"$definition.new"
  mv "$definition.new" "$definition"
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 1
  assert_contains "err" "$err" "name must be a non-empty string without /"
  assert_equal "calls" "$(calls)" ""
}

test_the_real_dataset_creates_eighteen_contexts() {
  write_fixture
  run_dataset tree load "$repo/dataset/dataset.json"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_equal "summary" "$(tail -n 1 <<<"$out")" \
    "$repo/dataset/dataset.json: 18 created, 0 exists, 0 differ, 0 skipped"
  assert_equal "live-step context" "$(context_at share/intelligence/vlf-channel-shift)" ""
  assert_equal "information-operations" \
    "$(context_at share/information-operations | jq -r .parent)" share
}

run_tests
