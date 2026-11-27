#!/usr/bin/env bash
# The dataset definition's check, sourced by lib/dataset.sh: lib/tree.jq validates the definition
# and documents its format, and this library adds the record bodies beside it, which jq can't see.

# Runs jq with the program given, which may call lib/tree.jq's definitions, and the remaining
# arguments, printing raw strings.
dataset_tree_jq() {
  jq -r -L "$(dirname "${BASH_SOURCE[0]}")" "include \"tree\"; $1" "${@:2}"
}

# Validates the definition at the path given, named in its output as the second argument, or as
# the path when there is none: prints each refusal to stderr as
# "dataset: <name>: <entry>: <message>", every one at once, and fails if it has any; otherwise
# prints "<name>: valid, <counts>". Writes nothing.
dataset_tree_check() {
  local path=$1 name=${2:-$1} dir id body output
  local -a refusals=()
  if [[ ! -f $path ]]; then
    echo "dataset: $name: no such file; give the path of a dataset definition" >&2
    return 1
  fi
  if ! output=$(jq empty "$path" 2>&1); then
    echo "dataset: $name: not valid JSON; fix it: ${output#jq: error }" >&2
    return 1
  fi
  output=$(dataset_tree_jq 'tree_errors | "\(.entry): \(.message)"' "$path") || return
  [[ -n $output ]] && mapfile -t refusals <<<"$output"
  dir=$(dirname "$path")
  output=$(dataset_tree_jq 'record_ids[]' "$path") || return
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    body=records/$id.json
    if [[ ! -f $dir/$body ]]; then
      refusals+=("record $id: no body at $body beside the definition; write it")
    elif ! jq empty "$dir/$body" 2>/dev/null; then
      refusals+=("record $id: $body is not valid JSON; fix it")
    fi
  done <<<"$output"
  if ((${#refusals[@]})); then
    for output in "${refusals[@]}"; do
      echo "dataset: $name: $output" >&2
    done
    return 1
  fi
  echo "$name: valid, $(dataset_tree_jq tree_summary "$path")"
}
