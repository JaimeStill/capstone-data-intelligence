#!/usr/bin/env bash
# The dataset suite's shell library, sourced by the dataset dispatcher and every
# dataset-<group>-<verb> command, which stay thin consumers of it. It holds the usage error every
# command reports the same way, and sources each group's library, lib/tree.sh and lib/source.sh,
# and lib/mikoshi.sh, the Mikoshi API calls the tree's load and reset make.

# Prints the message given to stderr, then the usage given, when one is, and exits 2.
dataset_usage_error() {
  echo "dataset: $1" >&2
  if [[ -n ${2:-} ]]; then
    echo "usage: dataset $2" >&2
  fi
  exit 2
}

# shellcheck source=lib/tree.sh
source "$(dirname "${BASH_SOURCE[0]}")/tree.sh"

# shellcheck source=lib/source.sh
source "$(dirname "${BASH_SOURCE[0]}")/source.sh"

# shellcheck source=lib/mikoshi.sh
source "$(dirname "${BASH_SOURCE[0]}")/mikoshi.sh"
