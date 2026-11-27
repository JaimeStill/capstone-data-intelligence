#!/usr/bin/env bash
# Tests for the dataset dispatcher: the listing, running a command from any directory and through
# mise, and the usage errors, on the clone's copy with fixture commands written by each test.
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

remove_the_suite_commands() {
  rm -f "$clone"/bin/dataset-*-*
}

test_no_arguments_lists_only_the_usage_with_no_commands() {
  remove_the_suite_commands
  run_dataset
  assert_equal status "$status" 0
  assert_equal stdout "$out" "usage: dataset <group> <verb> [args...]"
  assert_equal stderr "$err" ""
}

test_no_arguments_lists_each_command_with_its_summary() {
  remove_the_suite_commands
  write_command demo echo "Prints its arguments" ':'
  write_command tree check "Checks the tree" ':'
  run_dataset
  assert_equal status "$status" 0
  assert_equal stdout "$out" "usage: dataset <group> <verb> [args...]
  dataset demo echo              Prints its arguments
  dataset tree check             Checks the tree"
}

test_listing_skips_files_that_are_not_executable() {
  remove_the_suite_commands
  write_command demo echo "Prints its arguments" ':'
  chmod -x "$clone/bin/dataset-demo-echo"
  run_dataset
  assert_equal stdout "$out" "usage: dataset <group> <verb> [args...]"
}

test_a_command_runs_with_the_remaining_arguments() {
  write_command demo echo "Prints its arguments" 'printf "[%s]" "$@"; exit 3'
  run_dataset demo echo first "two words"
  assert_equal status "$status" 3
  assert_equal stdout "$out" "[first][two words]"
}

test_a_command_runs_from_any_working_directory() {
  write_command demo echo "Prints its arguments" 'echo echoed'
  mkdir "$tmp/elsewhere"
  run bash -c 'cd "$1" && ../clone/bin/dataset demo echo' bash "$tmp/elsewhere"
  assert_equal status "$status" 0
  assert_equal stdout "$out" echoed
}

test_a_link_to_the_dispatcher_runs_commands_from_the_clone() {
  write_command demo echo "Prints its arguments" 'echo echoed'
  ln -s "$clone/bin/dataset" "$tmp/dataset"
  run "$tmp/dataset" demo echo
  assert_equal status "$status" 0
  assert_equal stdout "$out" echoed
}

test_mise_runs_a_command_with_its_arguments() {
  write_command demo echo "Prints its arguments" 'printf "[%s]" "$@"'
  run bash -c 'cd "$1" && mise run --quiet dataset -- demo echo first "two words"' mise "$clone"
  assert_equal status "$status" 0
  assert_equal stdout "$out" "[first][two words]"
}

test_an_unknown_command_is_a_usage_error() {
  run_dataset tree frobnicate
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" \
    "dataset: no command 'tree frobnicate'; run dataset with no arguments to list the commands"
}

test_a_group_without_a_verb_is_a_usage_error() {
  run_dataset tree
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" \
    "dataset: 'tree' names no verb; run dataset with no arguments to list the commands
usage: dataset <group> <verb> [args...]"
}

test_a_name_reaching_outside_the_commands_is_unknown() {
  mkdir "$clone/bin/dataset-x"
  printf '#!/usr/bin/env bash\necho ran\n' >"$clone/bin/demo-echo"
  chmod +x "$clone/bin/demo-echo"
  run_dataset x/../demo echo
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
}

test_a_command_usage_error_prints_to_stderr_and_exits_2() {
  write_command demo echo "Prints its arguments" \
    'dataset_usage_error "demo echo needs a word" "demo echo <word>..."'
  run_dataset demo echo
  assert_equal status "$status" 2
  assert_equal stdout "$out" ""
  assert_equal stderr "$err" "dataset: demo echo needs a word
usage: dataset demo echo <word>..."
}

run_tests
