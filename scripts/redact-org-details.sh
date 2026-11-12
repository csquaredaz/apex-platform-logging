#!/usr/bin/env bash
# Masks org-identifying values in Salesforce CLI output before it reaches a public CI log:
# usernames (email-shaped, with an alphabetic TLD so npm `pkg@1.2.3` strings survive), org and
# user Ids, and Salesforce instance URLs. Reads stdin and writes stdout, so a step keeps its output
# for debugging without naming the org.
#   sf org login jwt ... 2>&1 | bash scripts/redact-org-details.sh
# Pair it with `set -o pipefail` so the CLI's exit code still fails the step.
set -euo pipefail
perl -pe '
  s/[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,}\b/<username>/g;
  s/\b00D[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?\b/<org-id>/g;
  s/\b005[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?\b/<user-id>/g;
  s{https?://[\w.-]+\.(?:salesforce|force|salesforce-setup|lightning\.force)\.com\S*}{<instance-url>}g;
'
