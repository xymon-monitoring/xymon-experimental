#!/usr/bin/env bash
# tests/select-headless-dep.sh
#
# A pick-mode pull request may depend on a pull request that is already merged
# upstream: the dependency is satisfied, but its head is not fetched, so
# select.sh holds no head for it. When such a headless dependency is the last
# in a pull request's closure, the per-dependency loop that feeds "git log |
# sort" ends on a false "[ -n "$head" ]" test -- exit 1 -- and, as the left
# side of a pipe under "set -euo pipefail", pipefail and set -e take that for a
# failure and abort the whole plan silently (exit 1, no message). This builds
# exactly that shape and asserts select.sh completes and plans the pull request.

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
select=$here/../scripts/select.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

repo=$work/repo
git init -q "$repo"
cd "$repo"
echo base > f; git add f; git commit -qm base; git branch -q main

# #5: its own commit off main -- a selected dependency with a head.
git checkout -q -b pr5 main; echo p5 > f5; git add f5; git commit -qm "pr5"
h5=$(git rev-parse HEAD)

# #20: its own commit off main, depending on #5 (selected) and #10 (merged).
# #5 is not an ancestor of #20, so #20 is pick mode; #10 is merged, so it is
# headless and -- sorting after #5 -- is the closure's last entry.
git checkout -q -b pr20 main; echo p20 > f20; git add f20; git commit -qm "pr20"
h20=$(git rev-parse HEAD)
git checkout -q main

cat > "$work/prs.json" <<JSON
[
 {"number":5,"isDraft":false,"baseRefName":"main","headRefName":"pr5","headRefOid":"$h5","milestone":{"title":"4.3.32"},"body":""},
 {"number":20,"isDraft":false,"baseRefName":"main","headRefName":"pr20","headRefOid":"$h20","milestone":{"title":"4.3.32"},"body":"Depends-on: #5\nDepends-on: #10"}
]
JSON
printf '10\n' > "$work/merged.txt"

rc=0
bash "$select" "$work/prs.json" main "$work/merged.txt" > "$work/plan.tsv" 2> "$work/err" || rc=$?
if [ "$rc" != 0 ]; then
	echo "FAIL: select.sh exited $rc on a pick PR with a headless last dependency" >&2
	cat "$work/err" >&2
	exit 1
fi
if ! awk -F'\t' '$1==20 && $3=="pick"{found=1} END{exit !found}' "$work/plan.tsv"; then
	echo "FAIL: #20 is not planned as a pick-mode pull request" >&2
	cat "$work/plan.tsv" >&2
	exit 1
fi
echo "PASS: a headless last dependency does not abort the plan"
