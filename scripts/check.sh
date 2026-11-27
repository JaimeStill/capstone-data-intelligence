#!/usr/bin/env bash
# Validates the compose stack when one exists, shellchecks every tracked file whose first line is a
# sh or bash shebang, runs lint-context and lint-references, and runs every tests/*.test.sh,
# exiting nonzero if any step fails. Writes nothing.
# Run it through `mise run check`.
set -uo pipefail
cd "$(dirname "$0")/.." || exit

fail=0

compose_config() {
  if [[ -f compose.yml ]]; then
    echo "check: compose"
    docker compose config -q || fail=1
  fi
}

shellcheck_scripts() {
  local file scripts=()
  while IFS= read -r -d '' file; do
    if head -n 1 "$file" | grep -Eq '^#!.*\b(ba)?sh\b'; then
      scripts+=("$file")
    fi
  done < <(git ls-files -z)
  if ((${#scripts[@]})); then
    echo "check: shellcheck"
    shellcheck "${scripts[@]}" || fail=1
  fi
}

run_lint() {
  echo "check: $1"
  if ! command -v "$1" >/dev/null; then
    echo "FAIL: $1 is not on PATH; run mise install" >&2
    fail=1
    return
  fi
  "$1" || fail=1
}

run_tests() {
  local test
  echo "check: tests"
  for test in tests/*.test.sh; do
    [[ -e $test ]] || continue
    bash "$test" || fail=1
  done
}

compose_config
shellcheck_scripts
run_lint lint-context
run_lint lint-references
run_tests
exit "$fail"
