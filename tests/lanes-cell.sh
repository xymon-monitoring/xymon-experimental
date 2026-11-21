#!/usr/bin/env bash
# tests/lanes-cell.sh
#
# Pins scripts/lanes-cell.sh, the Lanes cell experimental-lanes.yml writes: a
# table with no lane is no result (exit 2, nothing printed), where it once read
# "all 0 passed" and chained the next milestone; otherwise every lane that
# neither passed nor was skipped is named, and reruns are counted.

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cell=$here/../scripts/lanes-cell.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

# expect DESCRIPTION WANTED_RC WANTED_OUT TABLE
expect() {
	local what=$1 wrc=$2 want=$3 got rc=0
	printf '%s' "$4" > "$work/lanes.tsv"
	got=$(bash "$cell" "$work/lanes.tsv") || rc=$?
	if [ "$rc" != "$wrc" ] || [ "$got" != "$want" ]; then
		echo "FAIL: $what: expected rc $wrc '$want', got rc $rc '$got'"
		fail=1
	fi
}

T=$'\t'
expect "no lane listed yet is no result, not all 0 passed" 2 "" ""
expect "every lane passed or skipped" 0 "all 3 passed" \
	"a${T}success${T}1${T}"$'\n'"b${T}skipped${T}2${T}"$'\n'"c${T}success${T}3${T}"$'\n'
expect "a lane that did not pass is named with its conclusion" 0 "1 of 2 did not pass: b (failure)" \
	"a${T}success${T}1${T}"$'\n'"b${T}failure${T}2${T}"$'\n'
expect "a pass on a rerun is counted" 0 "all 2 passed; 1 passed on a rerun" \
	"a${T}success${T}1${T}rerun"$'\n'"b${T}success${T}2${T}"$'\n'

[ "$fail" -eq 0 ] && echo "PASS: lanes-cell"
exit "$fail"
