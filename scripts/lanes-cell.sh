#!/usr/bin/env bash
# scripts/lanes-cell.sh LANES.TSV -- the Lanes cell for one milestone's head,
# from experimental-lanes.yml's table of its lanes: name, conclusion, job id,
# "rerun" when it passed only on a rerun.
#
# Prints "all N passed", or "B of N did not pass: ..." naming each, and how
# many passed on a rerun. A table with no lane at all is no result: a lane run
# GitHub has just started lists only its build-matrix job, which the table
# leaves out, until the matrix has spawned the lanes. Reported, that read
# "all 0 passed" and chained the next milestone before these lanes had run;
# it exits 2 instead, and the caller reports the lanes as running.
set -euo pipefail
tsv=$1
total=$(wc -l < "$tsv" | tr -d ' ')
[ "$total" -gt 0 ] || exit 2
bad=$(awk -F'\t' '$2 != "success" && $2 != "skipped"' "$tsv" | wc -l | tr -d ' ')
reruns=$(awk -F'\t' '$2 == "success" && $4 == "rerun"' "$tsv" | wc -l | tr -d ' ')
if [ "$bad" -eq 0 ]; then
	cell="all $total passed"
else
	cell="$bad of $total did not pass: $(awk -F'\t' '$2 != "success" && $2 != "skipped" { printf "%s%s (%s)", (n++ ? ", " : ""), $1, $2 }' "$tsv")"
fi
[ "$reruns" -eq 0 ] || cell="$cell; $reruns passed on a rerun"
printf '%s\n' "$cell"
