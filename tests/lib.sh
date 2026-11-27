#!/usr/bin/env bash
# The test harness every tests/*.test.sh sources: each test_ function runs in a fresh copy of the
# clone's bin/, lib/, and mise.toml, under a temporary HOME, with a stub directory first on PATH,
# so no test touches the real stack. A test script ends with run_tests, which prints a FAIL line
# per failed assertion and exits 1 if any fails.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

# Prints a FAIL line naming the calling test and the message given, and marks the run failed.
fail() {
  local test
  for test in "${FUNCNAME[@]}"; do
    [[ $test == test_* ]] && break
  done
  echo "FAIL: ${BASH_SOURCE[-1]##*/}: $test: $*" >&2
  failures=1
}

# Fails unless the actual value equals the expected one: assert_equal <what> <actual> <expected>.
assert_equal() {
  [[ $2 == "$3" ]] || fail "$1: got [$2], want [$3]"
}

# Fails unless the text given contains the fragment: assert_contains <what> <text> <fragment>.
assert_contains() {
  [[ $2 == *"$3"* ]] || fail "$1: [$2] does not contain [$3]"
}

# Starts a test: a fresh temporary directory holding the clone's copy (clone), the HOME, the stub
# directory first on PATH (stubs), and the stub call log.
set_up() {
  tmp=$(mktemp -d)
  clone=$tmp/clone
  stubs=$tmp/stubs
  mkdir -p "$clone" "$tmp/home" "$stubs"
  cp -R "$repo/bin" "$repo/lib" "$repo/mise.toml" "$clone/"
  export HOME=$tmp/home MISE_TRUSTED_CONFIG_PATHS=$clone
  PATH=$stubs:$base_path
}

# Writes a stub command first on PATH that logs its name and arguments to the call log (calls),
# then runs the body given, if any: write_stub <name> [body].
write_stub() {
  printf '#!/usr/bin/env bash\necho "%s $*" >>%q\n%s\n' "$1" "$tmp/calls" "${2:-}" >"$stubs/$1"
  chmod +x "$stubs/$1"
}

# Prints the stub call log, one call a line.
calls() {
  cat "$tmp/calls" 2>/dev/null
}

# Writes a command into the clone's bin/ as dataset-<group>-<verb>, sourcing the suite's library,
# with the summary and the body given: write_command <group> <verb> <summary> <body>.
write_command() {
  local path=$clone/bin/dataset-$1-$2
  printf '#!/usr/bin/env bash\n# dataset:summary=%s\nset -euo pipefail\nsource "%s"\n%s\n' \
    "$3" "$clone/lib/dataset.sh" "$4" >"$path"
  chmod +x "$path"
}

# Runs the command given, holding its stdout in out, its stderr in err, and its status in status.
# shellcheck disable=SC2034 # The test scripts that source this file read out, err, and status.
run() {
  out=$("$@" 2>"$tmp/stderr")
  status=$?
  err=$(<"$tmp/stderr")
}

# Runs the clone's dataset with the arguments given, as run does.
run_dataset() {
  run "$clone/bin/dataset" "$@"
}

# Runs every test_ function of the calling script, each after set_up and in its own temporary
# directory, removed after it, then exits 1 if any assertion failed.
run_tests() {
  local test
  for test in $(declare -F | awk '$3 ~ /^test_/ { print $3 }'); do
    set_up
    "$test"
    rm -rf "$tmp"
  done
  exit "$failures"
}

base_path=$PATH
