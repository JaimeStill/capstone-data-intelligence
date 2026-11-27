#!/usr/bin/env bash
# Tests for scripts/dataset-live.sh, run against the fixture definition and the real
# dataset/dataset.json through tests/mikoshi.sh's curl stub of Mikoshi's contexts API in place of a
# running Mikoshi.
# shellcheck source=tests/mikoshi.sh
source "$(dirname "$0")/mikoshi.sh"

run_live() {
  run "$repo/scripts/dataset-live.sh" "$@"
}

test_a_cycle_on_an_empty_store_passes() {
  write_fixture
  run_live "$definition"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_equal "summaries" "$(grep -E '^(==|dataset-live|/)' <<<"$out")" "== dataset tree load
$definition: 9 created, 0 exists, 0 differ, 0 skipped
== dataset tree load
$definition: 0 created, 9 exists, 0 differ, 0 skipped
== dataset tree reset
$definition: 3 deleted, 0 absent
== dataset tree load
$definition: 9 created, 0 exists, 0 differ, 0 skipped
== the tree through the API
dataset-live: passed, 9 contexts against http://mikoshi.test:8080"
  assert_contains "a query context checked" "$out" "context views/long: query, as declared"
  assert_equal "long's filter" "$(context_at views/long | jq -c .filter)" \
    '[{"field":"route","op":"in","value":["audio","video"]},{"field":"duration","op":"gt","value":120}]'
}

test_a_cycle_over_a_loaded_tree_passes_and_keeps_other_contexts() {
  write_fixture
  seed a0000000-0000-0000-0000-000000000001 "$root" foreign
  run_dataset tree load "$definition"
  run_live "$definition"
  assert_equal "status" "$status" 0
  assert_contains "first load" "$out" "$definition: 0 created, 9 exists, 0 differ, 0 skipped"
  assert_equal "foreign" "$(context_at foreign)" '{"parent":"root","kind":"explicit","filter":null}'
}

test_the_real_dataset_passes_a_cycle() {
  write_fixture
  run_live "$repo/dataset/dataset.json"
  assert_equal "status" "$status" 0
  assert_contains "last load" "$out" \
    "$repo/dataset/dataset.json: 18 created, 0 exists, 0 differ, 0 skipped"
  assert_contains "passed" "$out" "dataset-live: passed, 18 contexts"
}

test_a_context_that_differs_fails_the_first_load() {
  write_fixture
  seed a0000000-0000-0000-0000-000000000001 "$root" views
  seed a0000000-0000-0000-0000-000000000002 a0000000-0000-0000-0000-000000000001 audio \
    '[{"field":"route","op":"eq","value":"video"}]'
  run_live "$definition"
  assert_equal "status" "$status" 1
  assert_contains "err" "$err" "dataset-live: dataset tree load exited 1"
  assert_equal "deletes" "$(calls | grep -c -- '-X DELETE' || true)" 0
}

test_mikoshi_not_answering_is_refused_naming_mikoshi_url() {
  write_fixture
  write_stub curl 'exit 7'
  run_live "$definition"
  assert_equal "status" "$status" 1
  assert_equal "out" "$out" ""
  assert_equal "err" "$err" "dataset-live: Mikoshi does not answer at http://mikoshi.test:8080: cannot reach Mikoshi at http://mikoshi.test:8080; start it, or set MIKOSHI_URL to its address"
}

run_tests
