#!/usr/bin/env bash
# Enable the repo's secret-guard pre-commit hook. Run once per clone.
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "✓ pre-commit secret guard enabled (.githooks)"
