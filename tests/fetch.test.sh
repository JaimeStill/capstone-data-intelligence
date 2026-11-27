#!/usr/bin/env bash
# Tests for dataset source fetch (lib/source.sh), against a fixture definition with one url, one
# corpus, and one generated file, and a manual file a test adds: a curl stub serves the url file, a
# fake docs-corpus git repo, whose working-tree MANIFEST.json has moved past its v0.2.0 tag, holds
# the corpus file, and a generator stub writes the generated file. Nothing is downloaded.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

sha() {
  printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

write_fixture() {
  definition=$tmp/fixture/dataset.json
  cache=$tmp/cache
  mkdir -p "$tmp/fixture" "$tmp/web" "$tmp/corpus/guides"
  export DATASET_CACHE=$cache DOCS_CORPUS=$tmp/corpus

  printf alpha >"$tmp/web/a.pdf"
  write_stub curl "out=''; url=''
while ((\$#)); do
  case \$1 in
    -o) out=\$2; shift ;;
    -*) ;;
    *) url=\$1 ;;
  esac
  shift
done
cat \"$tmp/web/\${url##*/}\" >\"\$out\""

  printf beta >"$tmp/corpus/guides/guide.md"
  jq -n --arg sha "$(sha beta)" \
    '{version: 1, files: [{path: "guides/guide.md", sha256: $sha, bytes: 4}]}' \
    >"$tmp/corpus/MANIFEST.json"
  git -C "$tmp/corpus" init -q
  git -C "$tmp/corpus" add .
  git -C "$tmp/corpus" -c user.name=test -c user.email=test@example.org commit -qm corpus
  git -C "$tmp/corpus" tag v0.2.0
  echo '{"version": 1, "files": []}' >"$tmp/corpus/MANIFEST.json"

  write_command source generate "Generates" \
    "echo \"generate \$*\" >>\"$tmp/calls\"; mkdir -p \"\$1\"; printf gamma >\"\$1/budget.xlsx\""

  jq -n --arg a "$(sha alpha)" --arg c "$(sha gamma)" '{
    contexts: [{name: "tour"}],
    files: [
      {id: "url-a", name: "a.pdf", contexts: ["tour"], url: "https://example.org/a.pdf",
       sha256: $a, bytes: 5, credit: "Example Press"},
      {id: "corpus-b", name: "guide.md", contexts: ["tour"], corpus: "guides/guide.md"},
      {id: "gen-c", name: "budget.xlsx", contexts: ["tour"], generated: "budget.xlsx",
       sha256: $c}
    ],
    records: [],
    live_steps: []
  }' | jq "${1:-.}" >"$definition"
}

manual_entry='.files += [{id: "manual-d", name: "d.jpg", contexts: ["tour"],
  manual: ["Open the archive", "Download the full-size scan"],
  sha256: "'$(sha delta)'", bytes: 5, credit: "Harbor Archive"}]'

cache_entries() {
  find "$cache" -mindepth 1 -printf '%P\n' | sort
}

test_a_fresh_fetch_places_every_file_under_its_sha256() {
  write_fixture
  run_dataset source fetch "$definition"
  assert_equal status "$status" 0
  assert_equal stderr "$err" ""
  assert_equal stdout "$out" "file url-a: fetched
file corpus-b: fetched
file gen-c: fetched
$definition: 3 fetched, 0 cached, 0 refused, 0 manual-missing"
  assert_equal cache "$(cache_entries)" "$(printf '%s\n' "$(sha alpha)" "$(sha beta)" "$(sha gamma)" | sort)"
  assert_equal "url-a bytes" "$(cat "$cache/$(sha alpha)")" alpha
  assert_equal "corpus-b bytes" "$(cat "$cache/$(sha beta)")" beta
  assert_equal "gen-c bytes" "$(cat "$cache/$(sha gamma)")" gamma
}

test_a_second_fetch_reports_every_file_cached_and_calls_nothing() {
  write_fixture
  run_dataset source fetch "$definition"
  rm -f "$tmp/calls"
  run_dataset source fetch "$definition"
  assert_equal status "$status" 0
  assert_equal stdout "$out" "file url-a: cached
file corpus-b: cached
file gen-c: cached
$definition: 0 fetched, 3 cached, 0 refused, 0 manual-missing"
  assert_equal calls "$(calls)" ""
}

test_the_generator_runs_once_for_every_generated_file() {
  write_fixture '.files += [.files[2] | .id = "gen-c2"]'
  run_dataset source fetch "$definition"
  assert_equal status "$status" 0
  assert_equal "generator runs" "$(calls | grep -c '^generate ')" 1
}

test_a_url_with_the_wrong_sha256_is_refused_and_leaves_nothing() {
  write_fixture ".files[0].sha256 = \"$(sha other)\""
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "dataset: $definition: file url-a: https://example.org/a.pdf has 5 bytes, sha256 $(sha alpha), but the definition pins 5 bytes, sha256 $(sha other); nothing was kept"
  assert_contains stdout "$out" "2 fetched, 0 cached, 1 refused, 0 manual-missing"
  assert_equal cache "$(cache_entries)" "$(printf '%s\n' "$(sha beta)" "$(sha gamma)" | sort)"
}

test_a_wrong_byte_count_is_refused() {
  write_fixture '.files[0].bytes = 6'
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_contains stderr "$err" "file url-a: https://example.org/a.pdf has 5 bytes"
  assert_contains stderr "$err" "pins 6 bytes"
  [[ -e $cache/$(sha alpha) ]] && fail "the refused url-a is in the cache"
  assert_contains stdout "$out" "1 refused"
}

test_a_generated_file_with_the_wrong_sha256_is_refused() {
  write_fixture ".files[2].sha256 = \"$(sha other)\""
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_contains stderr "$err" "file gen-c: budget.xlsx has 5 bytes, sha256 $(sha gamma)"
  [[ -e $cache/$(sha gamma) ]] && fail "the refused gen-c is in the cache"
}

test_a_missing_manual_file_is_listed_with_its_cache_path() {
  write_fixture "$manual_entry"
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "dataset: $definition: file manual-d: d.jpg is fetched by hand and is not in the cache:
  1. Open the archive
  2. Download the full-size scan
  then save it as $cache/$(sha delta)"
  assert_contains stdout "$out" "3 fetched, 0 cached, 0 refused, 1 manual-missing"
}

test_a_manual_file_placed_by_hand_verifies() {
  write_fixture "$manual_entry"
  mkdir -p "$cache"
  printf delta >"$cache/$(sha delta)"
  run_dataset source fetch "$definition"
  assert_equal status "$status" 0
  assert_contains stdout "$out" "file manual-d: cached"
  assert_contains stdout "$out" "3 fetched, 1 cached, 0 refused, 0 manual-missing"
}

test_a_corrupt_cached_file_is_removed_and_fetched_again() {
  write_fixture
  mkdir -p "$cache"
  printf wrong >"$cache/$(sha alpha)"
  run_dataset source fetch "$definition"
  assert_equal status "$status" 0
  assert_contains stderr "$err" "file url-a: the cached $cache/$(sha alpha) has 5 bytes, sha256 $(sha wrong); removed it"
  assert_equal "url-a bytes" "$(cat "$cache/$(sha alpha)")" alpha
}

test_a_corpus_path_not_in_the_manifest_is_refused() {
  write_fixture '.files[1].corpus = "guides/absent.md"'
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "dataset: $definition: file corpus-b: guides/absent.md is not in docs-corpus v0.2.0's MANIFEST.json; name a path it lists"
}

test_a_corpus_file_missing_from_the_checkout_is_refused_with_its_fix() {
  write_fixture
  rm "$tmp/corpus/guides/guide.md"
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "dataset: $definition: file corpus-b: $tmp/corpus/guides/guide.md is missing; run \`mise run fetch\` in docs-corpus"
}

test_a_missing_docs_corpus_is_refused_with_its_fix() {
  write_fixture
  export DOCS_CORPUS=$tmp/nowhere
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_equal stderr "$err" "dataset: $definition: file corpus-b: no docs-corpus checkout at $tmp/nowhere; clone docs-corpus there, or set DOCS_CORPUS to its checkout"
  assert_contains stdout "$out" "2 fetched, 0 cached, 1 refused, 0 manual-missing"
}

test_curl_is_never_given_a_user_agent() {
  write_fixture
  run_dataset source fetch "$definition"
  assert_contains calls "$(calls)" "curl "
  if calls | grep -E '^curl .*(-A|--user-agent)( |=|$)'; then
    fail "curl was given a user agent"
  fi
}

test_the_cache_holds_no_scratch_after_a_refusal() {
  write_fixture ".files[0].sha256 = \"$(sha other)\" | .files[2].sha256 = \"$(sha other)\""
  run_dataset source fetch "$definition"
  assert_equal cache "$(cache_entries)" "$(sha beta)"
}

test_an_invalid_definition_is_refused_before_fetching() {
  write_fixture '.files[0].bytes = "five"'
  run_dataset source fetch "$definition"
  assert_equal status "$status" 1
  assert_contains stderr "$err" "file url-a: bytes must be the file's size"
  assert_equal calls "$(calls)" ""
}

test_more_than_one_definition_is_a_usage_error() {
  run_dataset source fetch a.json b.json
  assert_equal status "$status" 2
  assert_equal stderr "$err" "dataset: source fetch takes at most one definition
usage: dataset source fetch [definition]"
}

run_tests
