#!/usr/bin/env bash
# tests/chain-next.sh
#
# Pins scripts/chain.sh's decisions on which milestone's lanes start next:
# by day the chain stops after the second milestone, at night it goes on to
# the newest, a head that already has lanes ends it, and the night kickoff
# leaves the oldest to experimental-promote.yml and waits for lanes already
# running.

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
chain=$here/../scripts/chain.sh
fail=0

# expect DESCRIPTION WANTED TABLE ARGS... -- run chain.sh on TABLE with ARGS.
expect() {
	local what=$1 want=$2 table=$3 got
	shift 3
	got=$(printf '%s' "$table" | bash "$chain" "$@")
	if [ "$got" != "$want" ]; then
		echo "FAIL: $what: expected '$want', got '$got'"
		fail=1
	fi
}

none=$'4.3.32 1\n4.3.33 0\n4.3.34 0\n'
mid=$'4.3.32 1\n4.3.33 1\n4.3.34 0\n'
all=$'4.3.32 1\n4.3.33 1\n4.3.34 1\n'

expect "by day, the oldest's lanes chain to the second"      4.3.33 "$none" after 4.3.32 14
expect "by day, the second's lanes chain no further"         ""     "$mid"  after 4.3.33 14
expect "at night, the second's lanes chain to the third"     4.3.34 "$mid"  after 4.3.33 03
expect "01:00 UTC is night"                                  4.3.34 "$mid"  after 4.3.33 1
expect "07:00 UTC is day again"                              ""     "$mid"  after 4.3.33 7
expect "a head that already has lanes ends the chain"        ""     "$all"  after 4.3.32 03
expect "the newest has no next"                              ""     "$none" after 4.3.34 03
expect "a milestone that is not open chains to nothing"      ""     "$none" after 4.3.31 03
expect "one milestone open: nothing to chain to"             ""     $'4.3.32 1\n' after 4.3.32 03

expect "the kickoff starts the first untested after the oldest" 4.3.33 "$none" kickoff 0
expect "the kickoff skips a tested second"                   4.3.34 "$mid"  kickoff 0
expect "the kickoff leaves the oldest to the promotion"      ""     $'4.3.32 0\n4.3.33 1\n' kickoff 0
expect "the kickoff waits while lanes run"                   ""     "$none" kickoff 1
expect "the kickoff has nothing to do when all are tested"   ""     "$all"  kickoff 0

expect "the second waits for the oldest"   "waiting: starts when 4.3.32's lanes finish" "$none" wait 4.3.33
expect "the third waits for the night"     "waiting: tonight's chain, from 01:47 UTC"   "$none" wait 4.3.34
expect "the oldest waits for nothing"      "no lane runs yet"                           "$none" wait 4.3.32

[ "$fail" = 0 ] && echo "PASS: chain.sh starts one milestone's lanes at a time: the second by day, every one at night"
exit "$fail"
