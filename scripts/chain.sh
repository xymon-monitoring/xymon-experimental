#!/usr/bin/env bash
# chain.sh after MILESTONE NIGHT  -- the milestone whose lanes start now that
#                                    MILESTONE's have all finished, if any
# chain.sh kickoff BUSY           -- the milestone the night chain starts
#                                    with, if any; BUSY is 1 while any lane
#                                    run is queued or running
# chain.sh wait MILESTONE         -- why MILESTONE's head has no lanes yet
#
# Reads the open milestones on stdin, oldest first, one per line:
#   milestone <SPACE> 1 when lanes ran or run on its current head, else 0
#
# The chain starts one milestone's lanes at a time, never two: the macOS
# runners the organisation gets at once are few. (A promotion of the oldest
# milestone starts its lanes whatever runs, as before.) The oldest milestone's
# start each time its branch moves (experimental-promote.yml). By day the chain
# then goes on to the second milestone only; during the night chain, through to
# the newest, a milestone whose head already has lanes ending it. The night
# chain is started by experimental-lanes.yml's night run on the first milestone
# after the oldest whose head has none, unless lanes are running already: the
# chain goes on from those when they finish. NIGHT is 1 while the night chain
# runs and 0 otherwise; the workflow decides it from when its night run really
# started, not from the clock, since GitHub starts that schedule hours late.
#
# after and kickoff print a milestone or nothing; wait prints the reason for
# the status issue's row. Makes no call to GitHub: the workflow
# gathers what it reads and starts what it prints, which keeps this testable.
set -euo pipefail

read_milestones() {
	list=() tested=()
	while read -r m t; do
		[ -n "$m" ] || continue
		list+=("$m") tested+=("$t")
	done
}
read_milestones

index_of() {
	local i
	for i in "${!list[@]}"; do [ "${list[$i]}" = "$1" ] && { echo "$i"; return; }; done
	echo -1
}

case "${1:-}" in
after)
	i=$(index_of "$2") night=$3
	n=$((i + 1))
	[ "$i" -ge 0 ] && [ "$n" -lt "${#list[@]}" ] || exit 0
	[ "${tested[$n]}" = 0 ] || exit 0
	if [ "$n" -eq 1 ] || [ "$night" = 1 ]; then
		echo "${list[$n]}"
	fi
	;;
kickoff)
	[ "$2" = 0 ] || exit 0
	for i in "${!list[@]}"; do
		if [ "$i" -ge 1 ] && [ "${tested[$i]}" = 0 ]; then echo "${list[$i]}"; exit 0; fi
	done
	;;
wait)
	i=$(index_of "$2")
	if [ "$i" -le 0 ]; then echo "no lane runs yet"
	elif [ "$i" -eq 1 ]; then echo "waiting: starts when ${list[0]}'s lanes finish"
	else echo "waiting: the night run (scheduled 01:47 UTC; GitHub starts it late)"
	fi
	;;
*)
	echo "usage: chain.sh after MILESTONE NIGHT | kickoff BUSY | wait MILESTONE" >&2
	exit 2
	;;
esac
