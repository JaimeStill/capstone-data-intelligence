#!/usr/bin/env bash
# Tests for dataset source generate (lib/generate.py): two runs write the same four files, byte for
# byte, and each is an OOXML package carrying the fixed core properties. They run the real
# generator through uv with the caller's uv cache and Python installs; without uv or unzip, or
# when uv can't reach the network for a package its cache lacks, each test prints a SKIP line.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

files=(collection-plan.xlsx mission-analysis-brief.pptx opord-26-03-v1.docx opord-26-03-v2.docx)

if command -v uv >/dev/null; then
  UV_CACHE_DIR=$(uv cache dir) UV_PYTHON_INSTALL_DIR=$(uv python dir)
  export UV_CACHE_DIR UV_PYTHON_INSTALL_DIR
fi

# Runs dataset source generate into the directory given and succeeds when it wrote the files;
# otherwise prints a SKIP line when uv or unzip is missing or uv couldn't reach the network, or
# fails the test, and returns 1 either way.
generate() {
  if ! command -v uv >/dev/null || ! command -v unzip >/dev/null; then
    skip "uv and unzip must be on PATH; run mise install"
    return 1
  fi
  run_dataset source generate "$1"
  if ((status != 0)); then
    if [[ $err =~ (Failed to fetch|Failed to download|error sending request|dns error) ]]; then
      skip "uv couldn't reach the network: $err"
    else
      fail "generate exited $status: $err"
    fi
    return 1
  fi
}

test_two_runs_write_the_same_four_files() {
  if ! generate "$tmp/first" || ! generate "$tmp/second"; then return 0; fi
  assert_equal "first run's files" "$(ls "$tmp/first")" "$(printf '%s\n' "${files[@]}")"
  assert_equal "second run's files" "$(ls "$tmp/second")" "$(printf '%s\n' "${files[@]}")"
  local file
  for file in "${files[@]}"; do
    cmp -s "$tmp/first/$file" "$tmp/second/$file" || fail "$file differs between the runs"
  done
}

test_each_file_is_a_package_with_the_fixed_core_properties() {
  generate "$tmp/out" || return 0
  local file core
  for file in "${files[@]}"; do
    assert_contains "$file entries" "$(unzip -l "$tmp/out/$file")" "[Content_Types].xml"
    core=$(unzip -p "$tmp/out/$file" docProps/core.xml)
    assert_contains "$file creator" "$core" "TF LANTERN S3 Plans</dc:creator>"
    assert_contains "$file last modified by" "$core" "<cp:lastModifiedBy>TF LANTERN S3 Plans</cp:lastModifiedBy>"
    assert_contains "$file created" "$core" 'xsi:type="dcterms:W3CDTF">2026-03-0'
    [[ $core =~ dcterms:modified[^\>]*\>2026-03-(0[5-9]|10)T ]] ||
      fail "$file modified: [$core] has no fixed March 2026 modified date"
  done
}

test_every_entry_has_the_fixed_timestamp() {
  generate "$tmp/out" || return 0
  local file dates
  for file in "${files[@]}"; do
    dates=$(unzip -Z -T "$tmp/out/$file" | awk '$1 ~ /^-/ { print $7 }' | sort -u)
    assert_equal "$file entry timestamps" "$dates" 20260302.080000
  done
}

test_no_output_directory_is_a_usage_error() {
  run_dataset source generate
  assert_equal status "$status" 2
  assert_equal stderr "$err" "dataset: source generate takes one output directory
usage: dataset source generate <outdir>"
}

run_tests
