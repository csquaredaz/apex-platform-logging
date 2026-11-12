#!/usr/bin/env bash
# Create a scratch org, install package dependencies, deploy this repo and assign permissions.
# Usage: npm run org:setup [-- <alias>]   (default alias: the repo name)
set -euo pipefail

alias_name="${1:-apex-platform-logging}"

sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias "$alias_name" \
  --set-default \
  --duration-days "${SF_SCRATCH_DURATION:-7}" \
  --wait 15

# Install package dependencies declared in sfdx-project.json (for example apex-core-lib), in order.
node -e '
  const p = require("./sfdx-project.json");
  const deps = (p.packageDirectories.find((d) => d.default) || {}).dependencies || [];
  for (const d of deps) console.log(p.packageAliases[d.package] || d.package);
' | while read -r version_id; do
  [ -n "$version_id" ] || continue
  sf package install --package "$version_id" --target-org "$alias_name" --wait 20 --no-prompt
done

sf project deploy start --target-org "$alias_name" --wait 20

# Assign every permission set this repo ships, so the default user can exercise the features.
# (find, not **, because macOS ships bash 3.2 without globstar.)
find force-app -name '*.permissionset-meta.xml' | while read -r ps; do
  sf org assign permset --name "$(basename "$ps" .permissionset-meta.xml)" --target-org "$alias_name"
done

echo "Scratch org '$alias_name' is ready. Run: npm run org:test"
