#!/usr/bin/env bash
# Pulls the latest setup from GitHub (fast-forward only) and re-applies it.
# Usage: ./update.sh [--skip-plugins]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
if ! git pull --ff-only; then
  echo "git pull --ff-only failed. This machine has local commits or edits; run 'git status' to see them." >&2
  exit 1
fi
exec ./setup.sh "$@"
