#!/usr/bin/env bash
# Mikoshi's contexts API as the dataset suite calls it, sourced by lib/dataset.sh: every call goes
# to the Mikoshi at MIKOSHI_URL, http://localhost:8080 unless set, through curl, with no
# credentials.

# Prints the id of the root of Mikoshi's context tree, under which the top-level contexts sit.
mikoshi_root() {
  echo 00000000-0000-0000-0000-000000000000
}

# Calls Mikoshi: mikoshi_call <method> <path> [JSON body], the path under MIKOSHI_URL. Prints the
# response body and succeeds on a 2xx status; otherwise prints the reason, the status with the
# problem's detail, or that Mikoshi is unreachable at MIKOSHI_URL, and fails.
mikoshi_call() {
  local method=$1 path=$2 url response code body detail
  local -a args=(-s -X "$method" -w '\n%{http_code}')
  url=${MIKOSHI_URL:-http://localhost:8080}
  if (($# > 2)); then
    args+=(-H 'Content-Type: application/json' --data-raw "$3")
  fi
  if ! response=$(curl "${args[@]}" "$url$path"); then
    echo "cannot reach Mikoshi at $url; start it, or set MIKOSHI_URL to its address"
    return 1
  fi
  code=${response##*$'\n'}
  body=${response%$'\n'*}
  if [[ $code == 2?? ]]; then
    printf '%s\n' "$body"
    return 0
  fi
  detail=$(jq -r '.detail // .title // empty' 2>/dev/null <<<"$body")
  echo "$method $path answered $code${detail:+: $detail}"
  return 1
}

# Prints every child of the context with the id given, as one JSON array, reading each page of
# 100 in turn by the cursor a page returns, or by page number when it returns none. Prints
# mikoshi_call's reason and fails when a read fails.
mikoshi_children() {
  local id=$1 query='size=100' number=1 page next items='[]'
  while :; do
    page=$(mikoshi_call GET "/api/contexts/$id/children?$query") || {
      echo "$page"
      return 1
    }
    items=$(jq -c --argjson items "$items" '$items + .items' <<<"$page") || return
    [[ $(jq -r '.more' <<<"$page") == true ]] || break
    next=$(jq -r '.next // empty | @uri' <<<"$page")
    number=$((number + 1))
    if [[ -n $next ]]; then
      query="size=100&cursor=$next"
    else
      query="size=100&page=$number"
    fi
  done
  printf '%s\n' "$items"
}

# Creates a context: mikoshi_create <parent id> <name> <kind> <filter as JSON, null for an
# explicit context>. Prints the context as created, or mikoshi_call's reason and fails.
mikoshi_create() {
  local body
  body=$(jq -nc --arg parent "$1" --arg name "$2" --arg kind "$3" --argjson filter "$4" \
    '{parent_id: $parent, name: $name, kind: $kind, filter: $filter}') || return
  mikoshi_call POST /api/contexts "$body"
}
