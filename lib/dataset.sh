#!/usr/bin/env bash
# The dataset suite's shell library, sourced by the dataset dispatcher and every
# dataset-<group>-<verb> command, which stay thin consumers of it. It holds the usage error every
# command reports the same way.

# Prints the message given to stderr, then the usage given, when one is, and exits 2.
dataset_usage_error() {
  echo "dataset: $1" >&2
  if [[ -n ${2:-} ]]; then
    echo "usage: dataset $2" >&2
  fi
  exit 2
}
