#!/usr/bin/env bash
# full-lane-runs.sh REPO SHA [not-passed] -- how many lane runs on SHA ran
# every release of their family; with not-passed, how many of those have not
# passed (failed, cancelled, or not finished).
#
# A preview is published on these only. The promotion and the chain start
# the lanes on the newest release of each family (scripts/start-lanes.sh),
# and such a run says so in its name, "... (newest)": a run's inputs are not
# in what GitHub lists. Sixteen of those passing say less than a preview
# claims, so they do not count here.
set -euo pipefail
repo=$1 sha=$2 what=${3:-}
filter='select(.displayTitle | endswith("(newest)") | not)'
[ "$what" != not-passed ] || filter="$filter | select(.conclusion != \"success\")"
gh run list -R "$repo" --workflow pipeline-select-run-lanes.yml --commit "$sha" -L 100 \
	--json displayTitle,conclusion -q "[.[] | $filter] | length"
