#!/usr/bin/env bash
# Run this repo's Apex tests, with coverage, in the default (or named) org.
# Usage: npm run org:test [-- <alias>]
#
# RunLocalTests isn't used: apex-core-lib has no namespace, so its packaged tests count as local
# and would run too, and some of them assert defaults that this repo's DI bindings override.
# This is the same scope CI uses: every <Name>Test class in the package directories.
set -euo pipefail

dirs=$(node -p 'require("./sfdx-project.json").packageDirectories.map((d) => d.path).join(" ")')
# shellcheck disable=SC2086 # word splitting over the directory list is intended
tests=$(find $dirs -name '*Test.cls' -exec grep -li '@istest' {} + | xargs -n1 basename | sed 's/\.cls$//' | sort | paste -sd, -)

target=()
if [ -n "${1:-}" ]; then
  target=(--target-org "$1")
fi

sf apex run test --class-names "$tests" --code-coverage --result-format human --wait 30 "${target[@]}"
