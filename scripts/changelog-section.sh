#!/usr/bin/env bash
# Prints the body of one version's section from CHANGELOG.md (the lines after "## X.Y.Z", up to
# the next "## " heading). release.yml adds it to the GitHub release notes, so upgrade
# instructions are reviewed in a PR rather than typed into the release by hand.
#   bash scripts/changelog-section.sh 1.1.0
# Exits 1 when the section is missing or empty.
set -euo pipefail
version="${1:?usage: changelog-section.sh X.Y.Z}"
section=$(awk -v heading="## ${version}" '
  $0 == heading { found = 1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md)
if [ -z "${section//[[:space:]]/}" ]; then
  echo "CHANGELOG.md has no section for ${version}." >&2
  exit 1
fi
printf '%s\n' "$section"
