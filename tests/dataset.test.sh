#!/usr/bin/env bash
# Tests for the demo dataset itself, dataset/dataset.json and its records: the definition passes
# dataset tree check and keeps its tour files, share files, records, and live files.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

definition=$repo/dataset/dataset.json

# Prints the number of the definition's entries the jq filter given selects: count <filter>.
count() {
  jq "[$1] | length" "$definition"
}

test_the_dataset_definition_passes_the_tree_check() {
  run_dataset tree check "$definition"
  assert_equal status "$status" 0
  assert_equal stdout "$out" \
    "$definition: valid, 18 contexts, 37 files, 8 records, 3 live steps"
  assert_equal stderr "$err" ""
}

test_the_dataset_keeps_its_tour_share_records_and_live_files() {
  assert_equal "tour files" "$(count '.files[] | select(any(.contexts[]; startswith("tour/")))')" 10
  assert_equal "share files" \
    "$(count '.files[] | select(any(.contexts[]; startswith("share/")))')" 27
  assert_equal records "$(count '.records[]')" 8
  assert_equal "live files" "$(count '.files[] | select(.live == true)')" 2
}

run_tests
