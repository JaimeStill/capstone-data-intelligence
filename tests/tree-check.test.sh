#!/usr/bin/env bash
# Tests for dataset tree check (lib/tree.sh, lib/tree.jq). tests/tree/dataset.json, with its record
# body, is the valid definition; each refusal fixture is a copy of it with one edit, written by its
# test, whose refusals are exactly the lines the test names.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

valid=$repo/tests/tree

# Copies the valid definition and its records to the fixture directory, applying the jq edit
# given to the definition: write_fixture <jq program>.
write_fixture() {
  fixture=$tmp/fixture/dataset.json
  mkdir -p "$tmp/fixture"
  cp -R "$valid/records" "$tmp/fixture/"
  jq "$1" "$valid/dataset.json" >"$fixture"
}

# Runs dataset tree check on the fixture and asserts it refuses with exactly the refusals given,
# one an argument, each "<entry>: <message>": assert_refuses <refusal>...
assert_refuses() {
  local refusal expected=()
  run_dataset tree check "$fixture"
  for refusal in "$@"; do
    expected+=("dataset: $fixture: $refusal")
  done
  assert_equal status "$status" 1
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "$(printf '%s\n' "${expected[@]}")"
}

test_the_valid_definition_passes_with_a_summary() {
  run_dataset tree check "$valid/dataset.json"
  assert_equal status "$status" 0
  assert_equal stdout "$out" \
    "$valid/dataset.json: valid, 9 contexts, 5 files, 1 records, 4 live steps"
  assert_equal stderr "$err" ""
}

test_the_definition_defaults_to_the_clones_dataset_from_any_directory() {
  mkdir -p "$clone/dataset" "$tmp/elsewhere"
  cp -R "$valid/dataset.json" "$valid/records" "$clone/dataset/"
  run bash -c 'cd "$1" && ../clone/bin/dataset tree check' bash "$tmp/elsewhere"
  assert_equal status "$status" 0
  assert_equal stdout "$out" \
    "dataset/dataset.json: valid, 9 contexts, 5 files, 1 records, 4 live steps"
}

test_the_check_writes_nothing() {
  write_fixture '.files[0].contexts += ["nowhere"]'
  local before
  before=$(find "$tmp/fixture" "$clone" -printf '%p %s %T@\n' | sort)
  run bash -c 'cd "$1" && clone/bin/dataset tree check fixture/dataset.json' bash "$tmp"
  assert_equal status "$status" 1
  assert_equal written "$(find "$tmp/fixture" "$clone" -printf '%p %s %T@\n' | sort)" "$before"
}

test_a_missing_definition_is_refused() {
  fixture=$tmp/absent.json
  assert_refuses "no such file; give the path of a dataset definition"
}

test_a_definition_that_is_not_json_is_refused() {
  fixture=$tmp/broken.json
  echo '{"contexts": [' >"$fixture"
  run_dataset tree check "$fixture"
  assert_equal status "$status" 1
  assert_contains stderr "$err" "dataset: $fixture: not valid JSON; fix it"
}

test_more_than_one_definition_is_a_usage_error() {
  run_dataset tree check a.json b.json
  assert_equal status "$status" 2
  assert_equal stderr "$err" "dataset: tree check takes at most one definition
usage: dataset tree check [definition]"
}

test_a_context_path_that_resolves_to_no_context_is_refused() {
  write_fixture '.files[0].contexts += ["share/missing"] | .records[0].contexts = ["tour"]
    | .records[0].contexts += ["nowhere"]'
  assert_refuses \
    "file field-manual: share/missing is not a declared context; declare it or fix the path" \
    "record manual-summary: nowhere is not a declared context; declare it or fix the path"
}

test_a_file_in_a_query_context_is_refused() {
  write_fixture '.files[1].contexts = ["views/audio"]'
  assert_refuses "file harbor-photo: views/audio is a query context, which holds only what its\
 filter selects; place the entry in an explicit context"
}

test_a_record_under_a_query_context_is_refused() {
  write_fixture '.records[0].contexts = ["views/audio/clips"]'
  assert_refuses "record manual-summary: views/audio/clips sits under a query context, which is a\
 leaf; place the entry in an explicit context"
}

test_a_context_under_a_query_context_is_refused() {
  write_fixture '.contexts[2].contexts[0].contexts = [{"name": "clips"}]'
  assert_refuses \
    "context views/audio: a query context is a leaf; remove its contexts or its filter"
}

test_siblings_sharing_a_name_are_refused() {
  write_fixture '.contexts[1].contexts += [{"name": "psyops"}]'
  assert_refuses \
    "context share/psyops: 2 sibling contexts share the name psyops; rename all but one"
}

test_a_malformed_context_is_refused() {
  write_fixture '.contexts[0].contexts += [{"name": "a/b"}, {"title": "x"}]'
  assert_refuses \
    "context tour: contexts[2]: name must be a non-empty string without /" \
    "context tour: contexts[3]: title is not a key here; the keys are name, contexts, filter" \
    "context tour: contexts[3]: name must be a non-empty string without /"
}

test_an_empty_filter_is_refused() {
  write_fixture '.contexts[2].contexts[0].filter = []'
  assert_refuses \
    "context views/audio: filter must be a non-empty list of {field, op, value} conditions"
}

test_a_filter_on_a_field_outside_route_kind_and_duration_is_refused() {
  write_fixture '.contexts[2].contexts[0].filter[0].field = "content_type"'
  assert_refuses \
    "context views/audio: filter[0].field must be one of route, kind, duration"
}

test_a_filter_with_an_unknown_operator_is_refused() {
  write_fixture '.contexts[2].contexts[0].filter[0].op = "contains"'
  assert_refuses "context views/audio: filter[0].op must be one of eq, ne, gt, ge, lt, le, like,\
 in, null, notnull"
}

test_a_filter_value_the_operator_does_not_take_is_refused() {
  write_fixture '.contexts[2].contexts[1].filter = [
      {"field": "kind", "op": "eq", "value": ["audio"]},
      {"field": "kind", "op": "like"},
      {"field": "kind", "op": "eq", "value": null},
      {"field": "route", "op": "in", "value": []},
      {"field": "route", "op": "in", "value": ["a", {"b": 1}]},
      {"field": "route", "op": "null", "value": "x"},
      {"field": "route", "op": "eq", "value": "x", "negate": true}]'
  assert_refuses \
    "context views/long: filter[0]: op eq takes one value, a string, number, or boolean" \
    "context views/long: filter[1]: op like takes one value, a string, number, or boolean" \
    "context views/long: filter[2]: op eq takes one value, a string, number, or boolean" \
    "context views/long: filter[3]: op in takes a non-empty list of strings, numbers, or booleans" \
    "context views/long: filter[4]: op in takes a non-empty list of strings, numbers, or booleans" \
    "context views/long: filter[5]: op null takes no value; remove it" \
    "context views/long: filter[6]: negate is not a key here; the keys are field, op, value"
}

test_a_file_without_a_provenance_is_refused() {
  write_fixture '.files[0] |= del(.url)'
  assert_refuses "file field-manual: needs exactly one provenance, url, manual, corpus, or\
 generated; it has none"
}

test_a_file_with_two_provenances_is_refused() {
  write_fixture '.files[0].corpus = "guides/manual.pdf"'
  assert_refuses "file field-manual: needs exactly one provenance, url, manual, corpus, or\
 generated; it has url, corpus"
}

test_a_provenance_missing_its_keys_is_refused() {
  write_fixture '.files[0] |= del(.bytes, .credit) | .files[3] |= del(.sha256)'
  assert_refuses \
    "file field-manual: a url file needs bytes; add it" \
    "file field-manual: a url file needs credit; add it" \
    "file budget-v1: a generated file needs sha256; add it"
}

test_a_provenance_carrying_keys_it_does_not_take_is_refused() {
  write_fixture '.files[2] += {"sha256": "'"$(printf 'b%.0s' {1..64})"'"}
    | .files[3].credit = "us"'
  assert_refuses \
    "file corpus-guide: a corpus file carries no sha256, fetch reads it from docs-corpus's\
 MANIFEST.json; remove it" \
    "file budget-v1: a generated file carries no credit; remove it"
}

test_malformed_provenance_values_are_refused() {
  write_fixture '.files[0].url = "ftp://example.org/x" | .files[0].bytes = 0
    | .files[1].manual = [] | .files[2].corpus = "../outside.md"
    | .files[3].generated = "out/budget.xlsx"'
  assert_refuses \
    "file field-manual: url must be an http or https URL" \
    "file field-manual: bytes must be the file's size, a whole number over 0" \
    "file harbor-photo: manual must be a non-empty list of the steps to fetch the file" \
    "file corpus-guide: corpus must be a relative path inside docs-corpus" \
    "file budget-v1: generated must be the generator's output file name"
}

test_a_sha256_that_is_not_64_lowercase_hex_characters_is_refused() {
  write_fixture '.files[0].sha256 |= ascii_upcase | .files[1].sha256 |= .[1:]'
  assert_refuses \
    "file field-manual: sha256 must be 64 lowercase hex characters" \
    "file harbor-photo: sha256 must be 64 lowercase hex characters"
}

test_a_malformed_file_entry_is_refused() {
  write_fixture '.files[0].name = "" | .files[0].live = "yes" | .files[0].contexts = []
    | .files[2].id = "Corpus Guide" | .files += ["loose"]'
  assert_refuses \
    "file field-manual: name must be the file's name, a non-empty string without /" \
    "file field-manual: contexts must be a non-empty list of context paths, such as share/psyops" \
    "file field-manual: live must be true or false" \
    "file Corpus Guide: id must be lowercase letters, digits, dots, hyphens, and underscores, from\
 a letter or digit" \
    "files[5]: must be an object"
}

test_duplicated_ids_are_refused() {
  write_fixture '.files[2].id = "field-manual" | .records[0].id = "budget-v1"'
  assert_refuses \
    "id budget-v1: 2 entries share the id budget-v1; give each its own" \
    "id field-manual: 2 entries share the id field-manual; give each its own" \
    "record budget-v1: no body at records/budget-v1.json beside the definition; write it"
}

test_a_supersedes_that_names_no_file_is_refused() {
  write_fixture '.files[4].supersedes = "budget-v0" | .files[3].supersedes = "budget-v1"'
  assert_refuses \
    "file budget-v1: supersedes names the entry itself; give the older entry's id" \
    "file budget-v2: supersedes \"budget-v0\" names no file; give the older entry's id"
}

test_a_record_annotating_no_file_is_refused() {
  write_fixture '.records[0].annotates += ["manual-summary", "ghost"]
    | .records += [{"id": "bare", "annotates": [], "contexts": ["share"]}]'
  assert_refuses \
    "record manual-summary: annotates \"manual-summary\", which names no file; give a file's id" \
    "record manual-summary: annotates \"ghost\", which names no file; give a file's id" \
    "record bare: annotates must be a non-empty list of file ids" \
    "record bare: no body at records/bare.json beside the definition; write it"
}

test_a_record_whose_body_is_not_json_is_refused() {
  write_fixture .
  echo '{"summary":' >"$tmp/fixture/records/manual-summary.json"
  assert_refuses "record manual-summary: records/manual-summary.json is not valid JSON; fix it"
}

test_a_live_step_naming_a_context_that_does_not_exist_is_refused() {
  write_fixture '.live_steps += [
      {"op": "rename", "path": "share/drafts", "name": "x"},
      {"op": "create", "path": "nowhere/new"},
      {"op": "move", "path": "share/psyops", "parent": "archive"}]'
  assert_refuses \
    "live_steps[4] (rename share/drafts): share/drafts does not exist at this step" \
    "live_steps[5] (create nowhere/new): parent nowhere does not exist at this step" \
    "live_steps[6] (move share/psyops): parent \"archive\" does not exist at this step"
}

test_a_live_step_taking_a_name_in_use_is_refused() {
  write_fixture '.live_steps += [
      {"op": "create", "path": "tour/images"},
      {"op": "rename", "path": "share/psyops", "name": "briefings"},
      {"op": "move", "path": "share/psyops", "parent": "tour", "name": "plans"}]'
  assert_refuses \
    "live_steps[4] (create tour/images): tour/images already exists at this step; choose a free\
 name" \
    "live_steps[5] (rename share/psyops): briefings is taken among its siblings at this step;\
 choose a free name" \
    "live_steps[6] (move share/psyops): plans is taken under tour at this step; choose a free name"
}

test_a_live_step_under_a_query_context_is_refused() {
  write_fixture '.live_steps += [
      {"op": "create", "path": "views/audio/new"},
      {"op": "move", "path": "share/psyops", "parent": "tour/plans/recent"}]'
  assert_refuses \
    "live_steps[4] (create views/audio/new): parent views/audio is a query context; create under\
 an explicit one" \
    "live_steps[5] (move share/psyops): parent tour/plans/recent is a query context; move under an\
 explicit one"
}

test_live_steps_run_against_the_tree_as_the_steps_before_left_it() {
  write_fixture '.live_steps = [
      {"op": "create", "path": "share/drafts/q1"},
      {"op": "create", "path": "share/drafts"},
      {"op": "move", "path": "share", "parent": "share/drafts"},
      {"op": "rename", "path": "share/drafts", "name": "plans"},
      {"op": "create", "path": "share/drafts/q2"}]'
  assert_refuses \
    "live_steps[0] (create share/drafts/q1): parent share/drafts does not exist at this step" \
    "live_steps[2] (move share): parent share/drafts is inside share; move it elsewhere" \
    "live_steps[4] (create share/drafts/q2): parent share/drafts does not exist at this step"
}

test_a_context_a_live_step_creates_is_not_declared_for_the_load() {
  write_fixture '.files[0].contexts = ["share/drafts"]'
  assert_refuses \
    "file field-manual: share/drafts is not a declared context; declare it or fix the path"
}

test_a_malformed_live_step_is_refused() {
  write_fixture '.live_steps += [
      {"op": "delete", "path": "share"},
      {"op": "create", "path": "top"},
      {"op": "rename", "path": "share", "name": ""},
      {"op": "create", "path": "share/q", "filter": []},
      {"op": "create", "path": "share/r", "parent": "tour"},
      "loose"]'
  assert_refuses \
    "live_steps[4] (delete share): op must be create, rename, or move" \
    "live_steps[5] (create top): path must name the new context under a context" \
    "live_steps[6] (rename share): name must be a non-empty string without /" \
    "live_steps[7] (create share/q): filter must be a non-empty list of {field, op, value}\
 conditions" \
    "live_steps[8] (create share/r): parent is not a key here; the keys are op, path, filter" \
    "live_steps[9]: must be an object"
}

test_a_malformed_definition_is_refused() {
  write_fixture '{contexts: [], files: {}, extra: 1}'
  assert_refuses \
    "definition: extra is not a key here; the keys are contexts, files, records, live_steps" \
    "definition: contexts must be a non-empty list of the top-level contexts" \
    "definition: files must be a list"
}

run_tests
