#!/usr/bin/env bash
# The dataset's file cache, sourced by lib/dataset.sh: fetches each file a definition names into
# the cache, dataset/.cache/ unless DATASET_CACHE names another, as <cache>/<sha256>, placing a file
# only once it matches its pinned sha256 and size. lib/tree.jq documents the definition's format.

# Prints one line a file of the definition at the path given, its fields separated by the unit
# separator, \x1f: its id, name, provenance, the provenance's value (empty for a manual file),
# sha256, and bytes, the last two empty when the definition doesn't pin them.
dataset_source_rows() {
  # shellcheck disable=SC2016 # The $ names are jq's variables, not the shell's.
  dataset_tree_jq '.files[] | . as $f | first(provenances[] | select(. as $p | $f | has($p)))
    as $p | [.id, .name, $p, (if $p == "manual" then "" else .[$p] end), .sha256 // "",
    (.bytes // "" | tostring)] | join("\u001f")' "$1"
}

# Succeeds when the file at the path given has the sha256 given and, when one is given, the size
# in bytes; otherwise prints what it has instead, "has <bytes> bytes, sha256 <sha256>", and fails.
dataset_source_verify() {
  local path=$1 sha=$2 bytes=${3:-} actual_sha actual_bytes
  actual_sha=$(sha256sum "$path" | cut -d' ' -f1)
  actual_bytes=$(stat -c %s "$path")
  if [[ $actual_sha == "$sha" && (-z $bytes || $actual_bytes == "$bytes") ]]; then
    return 0
  fi
  echo "has $actual_bytes bytes, sha256 $actual_sha"
  return 1
}

# Fetches every file of the definition at the path given, named in its output as the second
# argument, or as the path when there is none, into the cache: a url file with curl, a corpus file
# from the docs-corpus checkout DOCS_CORPUS names (~/architecture/docs-corpus unless set), pinned
# by that checkout's MANIFEST.json at tag v0.2.0, and a generated file from one run of
# `dataset source generate`. A manual file is never fetched: when it's missing, prints its steps
# and the cache path to save it to. A file already in the cache that verifies is reported cached
# and not fetched again. Prints "file <id>: fetched" or "file <id>: cached" for each file placed,
# each refusal to stderr as "dataset: <name>: file <id>: <message>", every one at once, and then
# "<name>: <n> fetched, <n> cached, <n> refused, <n> manual-missing"; fails unless every file is in
# the cache and verified. Writes nothing outside the cache; its scratch files are removed on exit.
dataset_source_fetch() {
  local path=$1 name=${2:-$1} rows cache corpus generator gen_status='' manifest='' corpus_error=''
  local id fname prov source sha bytes target scratch reason step n
  local fetched=0 cached=0 refused=0 missing=0
  dataset_tree_check "$path" "$name" >/dev/null || return
  rows=$(dataset_source_rows "$path") || return
  generator=$(dirname "${BASH_SOURCE[0]}")/../bin/dataset-source-generate
  corpus=${DOCS_CORPUS:-$HOME/architecture/docs-corpus}
  cache=${DATASET_CACHE:-$(dirname "${BASH_SOURCE[0]}")/../dataset/.cache}
  mkdir -p "$cache"
  cache=$(cd "$cache" && pwd)
  dataset_source_scratch=$(mktemp -d -p "$cache" .fetch.XXXXXX)
  trap 'rm -rf -- "$dataset_source_scratch"' EXIT

  while IFS=$'\x1f' read -r id fname prov source sha bytes <&3; do
    [[ -n $id ]] || continue
    if [[ $prov == corpus ]]; then
      if [[ -z $manifest && -z $corpus_error ]]; then
        manifest=$dataset_source_scratch/MANIFEST.json
        if [[ ! -d $corpus ]]; then
          corpus_error="no docs-corpus checkout at $corpus; clone docs-corpus there, or set DOCS_CORPUS to its checkout"
        elif ! git -C "$corpus" show v0.2.0:MANIFEST.json >"$manifest" 2>/dev/null; then
          corpus_error="$corpus has no MANIFEST.json at tag v0.2.0; run \`git fetch --tags\` in docs-corpus, or set DOCS_CORPUS to its checkout"
        fi
      fi
      if [[ -n $corpus_error ]]; then
        echo "dataset: $name: file $id: $corpus_error" >&2
        refused=$((refused + 1))
        continue
      fi
      sha=$(jq -r --arg path "$source" \
        'first(.files[] | select(.path == $path)) | "\(.sha256) \(.bytes)"' "$manifest")
      bytes=${sha#* }
      sha=${sha%% *}
      if [[ -z $sha ]]; then
        echo "dataset: $name: file $id: $source is not in docs-corpus v0.2.0's MANIFEST.json; name a path it lists" >&2
        refused=$((refused + 1))
        continue
      fi
    fi

    target=$cache/$sha
    if [[ -f $target ]]; then
      if reason=$(dataset_source_verify "$target" "$sha" "$bytes"); then
        echo "file $id: cached"
        cached=$((cached + 1))
        continue
      fi
      rm -f -- "$target"
      echo "dataset: $name: file $id: the cached $target $reason; removed it" >&2
      if [[ $prov == manual ]]; then
        refused=$((refused + 1))
        continue
      fi
    fi

    scratch=$(mktemp -p "$dataset_source_scratch" "$id.XXXXXX")
    case $prov in
      url)
        if ! curl -fsSL -o "$scratch" "$source" </dev/null; then
          echo "dataset: $name: file $id: downloading $source failed; check the URL still resolves" >&2
          rm -f -- "$scratch"
          refused=$((refused + 1))
          continue
        fi
        ;;
      corpus)
        if [[ ! -f $corpus/$source ]]; then
          echo "dataset: $name: file $id: $corpus/$source is missing; run \`mise run fetch\` in docs-corpus" >&2
          rm -f -- "$scratch"
          refused=$((refused + 1))
          continue
        fi
        cp -- "$corpus/$source" "$scratch"
        ;;
      generated)
        if [[ -z $gen_status ]]; then
          gen_status=0
          "$generator" "$dataset_source_scratch/generated" </dev/null >&2 || gen_status=$?
        fi
        if ((gen_status != 0)); then
          echo "dataset: $name: file $id: dataset source generate exited $gen_status; fix the generator" >&2
        elif [[ ! -f $dataset_source_scratch/generated/$source ]]; then
          echo "dataset: $name: file $id: dataset source generate wrote no $source; name a file it writes" >&2
        fi
        if ((gen_status != 0)) || [[ ! -f $dataset_source_scratch/generated/$source ]]; then
          rm -f -- "$scratch"
          refused=$((refused + 1))
          continue
        fi
        cp -- "$dataset_source_scratch/generated/$source" "$scratch"
        ;;
      manual)
        rm -f -- "$scratch"
        {
          echo "dataset: $name: file $id: $fname is fetched by hand and is not in the cache:"
          n=0
          while IFS= read -r step; do
            n=$((n + 1))
            echo "  $n. $step"
          done < <(jq -r --arg id "$id" '.files[] | select(.id == $id) | .manual[]' "$path")
          echo "  then save it as $target"
        } >&2
        missing=$((missing + 1))
        continue
        ;;
    esac

    if ! reason=$(dataset_source_verify "$scratch" "$sha" "$bytes"); then
      echo "dataset: $name: file $id: $source $reason, but the definition pins ${bytes:+$bytes bytes, }sha256 $sha; nothing was kept" >&2
      rm -f -- "$scratch"
      refused=$((refused + 1))
      continue
    fi
    mv -f -- "$scratch" "$target"
    echo "file $id: fetched"
    fetched=$((fetched + 1))
  done 3<<<"$rows"

  echo "$name: $fetched fetched, $cached cached, $refused refused, $missing manual-missing"
  ((refused == 0 && missing == 0))
}
