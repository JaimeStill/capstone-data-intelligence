#!/usr/bin/env bash
# The dataset definition's check and its load, sourced by lib/dataset.sh: lib/tree.jq validates the
# definition and documents its format, this library adds the record bodies beside it, which jq
# can't see, and builds the declared contexts in Mikoshi through lib/mikoshi.sh.

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

# Builds the context tree of the definition at the path given, named in its output as the second
# argument, or as the path when there is none, in Mikoshi, after validating it as
# dataset_tree_check does. Walks the declared contexts top-down, never a live step's, matching
# each by name among every child of its parent: creates a missing one, printing
# "context <path>: created", and leaves an existing one as it is, printing "context <path>: exists".
# An existing context whose kind or filter, compared as conditions, differs from its declaration
# is reported to stderr as "dataset: <name>: context <path>: <difference>", and the contexts under
# it are not loaded. Then prints "<name>: <n> created, <n> exists, <n> differ, <n> skipped", and
# fails when any differs. Never edits, renames, moves, or deletes a context; refuses when Mikoshi
# is unreachable, and stops at the first call Mikoshi refuses.
dataset_tree_load() {
  local path=$1 name=${2:-$1} rows root reason context parent cname kind filter parent_id found
  local created=0 exists=0 differ=0 skipped=0
  local -A ids=() children=() blocked=()
  dataset_tree_check "$path" "$name" >/dev/null || return
  rows=$(dataset_tree_jq load_rows "$path") || return
  root=$(mikoshi_root)
  if ! reason=$(mikoshi_call GET "/api/contexts/$root"); then
    echo "dataset: $name: $reason" >&2
    return 1
  fi
  ids[/]=$root

  while IFS=$'\x1f' read -r context parent cname kind filter <&3; do
    [[ -n $context ]] || continue
    if [[ -n ${blocked[/$parent]:-} ]]; then
      echo "dataset: $name: context $context: not loaded, since $parent differs" >&2
      blocked[/$context]=1
      skipped=$((skipped + 1))
      continue
    fi
    parent_id=${ids[/$parent]}
    if [[ -z ${children[$parent_id]:-} ]]; then
      if ! found=$(mikoshi_children "$parent_id"); then
        echo "dataset: $name: context $context: $found" >&2
        return 1
      fi
      children[$parent_id]=$found
    fi
    found=$(jq -c --arg name "$cname" 'first(.[] | select(.name == $name)) // empty' \
      <<<"${children[$parent_id]}") || return
    if [[ -z $found ]]; then
      if ! found=$(mikoshi_create "$parent_id" "$cname" "$kind" "$filter"); then
        echo "dataset: $name: context $context: $found" >&2
        return 1
      fi
      ids[/$context]=$(jq -r .id <<<"$found")
      children[${ids[/$context]}]='[]'
      echo "context $context: created"
      created=$((created + 1))
      continue
    fi
    # shellcheck disable=SC2016 # The $ names are jq's variables, not the shell's.
    reason=$(dataset_tree_jq 'context_difference($kind; $filter)' --arg kind "$kind" \
      --argjson filter "$filter" <<<"$found") || return
    if [[ -n $reason ]]; then
      echo "dataset: $name: context $context: $reason;" \
        "the load changes no context, so change it in Mikoshi or in the definition" >&2
      blocked[/$context]=1
      differ=$((differ + 1))
      continue
    fi
    ids[/$context]=$(jq -r .id <<<"$found")
    echo "context $context: exists"
    exists=$((exists + 1))
  done 3<<<"$rows"

  echo "$name: $created created, $exists exists, $differ differ, $skipped skipped"
  ((differ == 0))
}
