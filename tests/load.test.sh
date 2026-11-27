#!/usr/bin/env bash
# Tests for dataset tree load (lib/tree.sh, lib/mikoshi.sh), against a fixture definition and the
# real dataset/dataset.json, through tests/mikoshi.sh's curl stub of Mikoshi's contexts API.
# shellcheck source=tests/mikoshi.sh
source "$(dirname "$0")/mikoshi.sh"

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
