#!/usr/bin/env bash
# night.sh REPO [HOURS] -- print 1 while the night chain runs, 0 otherwise,
# with the reason on stderr.
#
# The night chain runs for HOURS (6 by default) after experimental-lanes.yml's
# night run really started. That run is the scheduled one whose step "Start
# the night's lane chain" ran; the daily look's run skips that step. It is
# found by when it ran, not by the clock: GitHub starts this repository's
# schedules hours late (the 01:47 UTC one around 08:00 in November 2026), so
# a window of fixed hours would never see the chain.
set -euo pipefail
repo=$1 hours=${2:-6}
step="Start the night's lane chain"

now=$(date -u +%s)
for run in $(gh run list -R "$repo" --workflow experimental-lanes.yml --event schedule -L 10 \
		--json databaseId -q '.[].databaseId'); do
	started=$(gh api "repos/$repo/actions/runs/$run/jobs" \
		-q ".jobs[].steps[] | select(.name == \"$step\" and .conclusion == \"success\") | .started_at" | head -1)
	[ -n "$started" ] || continue
	age=$(( (now - $(date -u -d "$started" +%s)) / 60 ))
	if [ "$age" -lt $((hours * 60)) ]; then
		echo "night chain: the night run $run started $started, $age minutes ago" >&2
		echo 1
	else
		echo "no night chain: the last night run, $run, started $started, $age minutes ago" >&2
		echo 0
	fi
	exit 0
done
echo "no night chain: no night run among the last ten scheduled runs" >&2
echo 0
