#!/usr/bin/env bash
# Tests for dataset source generate (lib/generate.py): a run writes the four files, each with the
# sha256 dataset/dataset.json pins for it. They run the real generator through uv with the caller's
# uv cache and Python installs; without uv, or when uv can't reach the network for a package its
# cache lacks, the test prints a SKIP line.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

files=(collection-plan.xlsx mission-analysis-brief.pptx opord-26-03-v1.docx opord-26-03-v2.docx)

if command -v uv >/dev/null; then
  UV_CACHE_DIR=$(uv cache dir) UV_PYTHON_INSTALL_DIR=$(uv python dir)
  export UV_CACHE_DIR UV_PYTHON_INSTALL_DIR
fi

generate() {
  if ! command -v uv >/dev/null; then
    skip "uv must be on PATH; run mise install"
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

test_the_four_files_match_their_pins_in_the_definition() {
  generate "$tmp/out" || return 0
  assert_equal "files" "$(ls "$tmp/out")" "$(printf '%s\n' "${files[@]}")"
  local file
  for file in "${files[@]}"; do
    assert_equal "$file sha256" "$(sha256sum "$tmp/out/$file" | cut -d' ' -f1)" \
      "$(jq -r --arg name "$file" '.files[] | select(.generated == $name) | .sha256' \
        "$repo/dataset/dataset.json")"
  done
}

test_no_output_directory_is_a_usage_error() {
  run_dataset source generate
  assert_equal status "$status" 2
  assert_equal stderr "$err" "dataset: source generate takes one output directory
usage: dataset source generate <outdir>"
}

run_tests
