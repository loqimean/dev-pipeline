#!/usr/bin/env bash
# Writes one review package (commit list, stat, full diff with context) to a file,
# so the reviewer reads it in one call and the diff never enters the orchestrator's context.
# Usage: review-package.sh <base> <head> <out-file>
set -euo pipefail
base=${1:?base ref}
head=${2:?head ref}
out=${3:?output file}
mkdir -p "$(dirname "$out")"
{
  echo "# Review package: ${base}..${head}"
  echo
  echo "## Commits"
  git log --oneline "${base}..${head}"
  echo
  echo "## Stat"
  git diff --stat "${base}...${head}"
  echo
  echo "## Diff"
  echo '```diff'
  git diff -U10 "${base}...${head}"
  echo '```'
} > "$out"
echo "$out ($(wc -l < "$out" | tr -d ' ') lines)"
