#!/usr/bin/env bash
# tests/start-lanes.sh
#
# Pins scripts/start-lanes.sh and scripts/full-lane-runs.sh against a gh that
# records what it is asked and answers from a table of runs:
#   - 16 runs are started, with the release policy asked for, newest by
#     default; a policy that is neither newest nor all starts nothing
#   - lane runs still going on another commit of the branch are cancelled,
#     and no other run is
#   - a lane workflow that refuses release_policy is started without it
#   - full-lane-runs.sh leaves out the runs named "... (newest)"

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0
check() { # DESCRIPTION WANTED GOT
	[ "$2" = "$3" ] || { echo "FAIL: $1: expected '$2', got '$3'"; fail=1; }
}

# The stub. "gh run list ... -q FILTER" answers $RUNS through jq; "gh api
# .../git/ref/..." gives the branch head; everything is logged.
mkdir "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
"api repos/"*) echo headsha ;;
"run list")
	while [ $# -gt 0 ]; do [ "$1" = -q ] && { q=$2; break; }; shift; done
	jq -r "$q" <<< "$RUNS" ;;
"run cancel") ;;
"workflow run")
	if [ -n "${OLD_WORKFLOW:-}" ] && [[ "$*" == *release_policy* ]]; then
		echo 'could not create workflow dispatch event: HTTP 422: Unexpected inputs provided: ["release_policy"]' >&2
		exit 1
	fi ;;
esac
STUB
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GH_LOG="$work/log"

export RUNS='[
 {"databaseId":1,"status":"in_progress","headSha":"oldsha","headBranch":"experimental/4.3.32"},
 {"databaseId":2,"status":"completed","headSha":"oldsha","headBranch":"experimental/4.3.32"},
 {"databaseId":3,"status":"in_progress","headSha":"headsha","headBranch":"experimental/4.3.32"},
 {"databaseId":4,"status":"queued","headSha":"othersha","headBranch":"experimental/4.3.33"}
]'

: > "$GH_LOG"
bash "$here/../scripts/start-lanes.sh" o/r 4.3.32
check "16 runs are started" 16 "$(grep -c '^workflow run' "$GH_LOG")"
check "newest is the default policy" 16 "$(grep -c 'release_policy=newest' "$GH_LOG")"
check "each on the milestone's branch" 16 "$(grep -c -- '--ref experimental/4.3.32' "$GH_LOG")"
check "macOS on every architecture" 1 "$(grep -c 'family=macos -f arch=all' "$GH_LOG")"
check "the others on amd64" 15 "$(grep -c 'arch=amd64' "$GH_LOG")"
check "only the run going on another commit of this branch is cancelled" "run cancel 1 -R o/r" "$(grep '^run cancel' "$GH_LOG")"

: > "$GH_LOG"
bash "$here/../scripts/start-lanes.sh" o/r 4.3.32 all
check "all is passed on when asked for" 16 "$(grep -c 'release_policy=all' "$GH_LOG")"

: > "$GH_LOG"
rc=0; bash "$here/../scripts/start-lanes.sh" o/r 4.3.32 latest 2>/dev/null || rc=$?
check "an unknown policy is refused" 2 "$rc"
check "... before anything is started or cancelled" 0 "$(grep -c . "$GH_LOG" || true)"

: > "$GH_LOG"
OLD_WORKFLOW=1 bash "$here/../scripts/start-lanes.sh" o/r 4.3.32 2>"$work/err"
check "a workflow without release_policy is started without it" 16 "$(grep '^workflow run' "$GH_LOG" | grep -vc release_policy)"
check "... and that is said" 16 "$(grep -c 'has no release_policy' "$work/err")"

export RUNS='[
 {"displayTitle":"Pipeline - Select and Run Lanes","conclusion":"success"},
 {"displayTitle":"Pipeline - Select and Run Lanes","conclusion":"failure"},
 {"displayTitle":"Pipeline - Select and Run Lanes","conclusion":null},
 {"displayTitle":"Pipeline - Select and Run Lanes (newest)","conclusion":"success"},
 {"displayTitle":"Pipeline - Select and Run Lanes (newest)","conclusion":"failure"}
]'
check "runs on the newest releases are not counted" 3 "$(bash "$here/../scripts/full-lane-runs.sh" o/r sha)"
check "nor among those that did not pass" 2 "$(bash "$here/../scripts/full-lane-runs.sh" o/r sha not-passed)"

[ "$fail" = 0 ] && echo "PASS: start-lanes.sh starts 16 runs on the policy asked for and cancels the superseded ones; full-lane-runs.sh counts the runs on every release"
exit "$fail"
