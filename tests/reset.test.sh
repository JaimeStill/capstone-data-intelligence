#!/usr/bin/env bash
# Tests for dataset tree reset (lib/tree.sh, lib/mikoshi.sh), against a fixture definition and the
# real dataset/dataset.json, through tests/mikoshi.sh's curl stub of Mikoshi's contexts API.
# shellcheck source=tests/mikoshi.sh
source "$(dirname "$0")/mikoshi.sh"

top_id() {
  jq -r --arg root "$root" --arg name "$1" \
    'first(.contexts[] | select(.parent_id == $root and .name == $name)) | .id' "$state"
}

tree_shape() {
  jq -c '.contexts as $all | [.contexts[] | {parent: (.parent_id as $p
    | first($all[] | select(.id == $p)).name), name, kind, filter}] | sort_by(.parent, .name)[]' \
    "$state"
}

test_reset_after_a_load_deletes_the_three_subtrees() {
  write_fixture
  seed a0000000-0000-0000-0000-000000000001 "$root" foreign
  seed a0000000-0000-0000-0000-000000000002 a0000000-0000-0000-0000-000000000001 inner
  run_dataset tree load "$definition"
  : >"$tmp/calls"
  run_dataset tree reset "$definition"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_equal "out" "$out" "context tour: deleted (2 descendants)
context share: deleted (2 descendants)
context views: deleted (2 descendants)
$definition: 3 deleted, 0 absent"
  assert_equal "contexts left" "$(jq -c '[.contexts[].name] | sort' "$state")" \
    '["foreign","inner","root"]'
  assert_equal "unconfirmed deletes" "$(calls | grep -c -- '-X DELETE .*/api/contexts/[^?]*$')" 3
  assert_equal "confirmed deletes" "$(calls | grep -c -- '-X DELETE .*?confirm=2$')" 3
}

test_reset_on_an_empty_store_reports_every_context_absent() {
  write_fixture
  run_dataset tree reset "$definition"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_equal "out" "$out" "context tour: absent
context share: absent
context views: absent
$definition: 0 deleted, 3 absent"
  assert_equal "deletes" "$(calls | grep -c -- '-X DELETE' || true)" 0
}

test_a_leaf_top_level_context_is_deleted_on_the_first_request() {
  write_fixture
  seed a0000000-0000-0000-0000-000000000001 "$root" tour
  run_dataset tree reset "$definition"
  assert_equal "status" "$status" 0
  assert_contains "tour" "$out" "context tour: deleted (0 descendants)"
  assert_equal "deletes" "$(calls | grep -c -- '-X DELETE')" 1
}

test_load_reset_load_ends_with_the_tree_of_one_load() {
  write_fixture
  run_dataset tree load "$definition"
  tree_shape >"$tmp/once"
  run_dataset tree reset "$definition"
  run_dataset tree load "$definition"
  assert_equal "status" "$status" 0
  assert_equal "summary" "$(tail -n 1 <<<"$out")" \
    "$definition: 9 created, 0 exists, 0 differ, 0 skipped"
  assert_equal "tree" "$(tree_shape)" "$(cat "$tmp/once")"
}

test_a_live_step_context_goes_with_its_subtree_and_one_outside_stays() {
  write_fixture
  run_dataset tree load "$definition"
  seed a0000000-0000-0000-0000-000000000001 "$(top_id share)" drafts
  seed a0000000-0000-0000-0000-000000000002 "$root" inbox
  run_dataset tree reset "$definition"
  assert_equal "status" "$status" 0
  assert_contains "share" "$out" "context share: deleted (3 descendants)"
  assert_equal "drafts" "$(jq '[.contexts[] | select(.name == "drafts")] | length' "$state")" 0
  assert_equal "contexts left" "$(jq -c '[.contexts[].name] | sort' "$state")" \
    '["inbox","root"]'
}

test_an_unreachable_api_is_refused_naming_mikoshi_url() {
  write_fixture
  write_stub curl 'exit 7'
  run_dataset tree reset "$definition"
  assert_equal "status" "$status" 1
  assert_equal "out" "$out" ""
  assert_equal "err" "$err" "dataset: $definition: cannot reach Mikoshi at http://mikoshi.test:8080; start it, or set MIKOSHI_URL to its address"
}

test_an_invalid_definition_is_refused_before_any_call() {
  write_fixture
  jq '.contexts[0].name = "a/b"' "$definition" >"$definition.new"
  mv "$definition.new" "$definition"
  run_dataset tree reset "$definition"
  assert_equal "status" "$status" 1
  assert_contains "err" "$err" "name must be a non-empty string without /"
  assert_equal "calls" "$(calls)" ""
}

test_the_root_is_never_targeted() {
  write_fixture
  run_dataset tree load "$definition"
  run_dataset tree reset "$definition"
  assert_equal "deletes of the root" "$(calls | grep -c -- "-X DELETE .*/$root" || true)" 0
  assert_equal "root" "$(jq -r --arg root "$root" '.contexts[] | select(.id == $root) | .name' \
    "$state")" root
  : >"$tmp/calls"
  write_command probe delete 'Deletes the root' "mikoshi_delete $root"
  run "$clone/bin/dataset-probe-delete"
  assert_equal "status" "$status" 1
  assert_equal "out" "$out" "the root context is never deleted"
  assert_equal "calls" "$(calls)" ""
}

test_the_real_dataset_resets_after_its_load() {
  write_fixture
  run_dataset tree load "$repo/dataset/dataset.json"
  run_dataset tree reset "$repo/dataset/dataset.json"
  assert_equal "status" "$status" 0
  assert_equal "err" "$err" ""
  assert_equal "summary" "$(tail -n 1 <<<"$out")" "$repo/dataset/dataset.json: 3 deleted, 0 absent"
  assert_equal "contexts left" "$(jq -c '[.contexts[].name]' "$state")" '["root"]'
}

run_tests
