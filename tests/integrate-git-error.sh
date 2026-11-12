#!/usr/bin/env bash
# tests/integrate-git-error.sh
#
# When git merge or git cherry-pick fails for a reason other than a conflict
# (here, a head or commit this clone does not have), no path is left
# unmerged, and integrate.sh took the empty list for "every conflict
# resolved": it reported the pull request "resolved" (pick mode even
# committed an empty merge) though none of its changes were in the tree.
# This plans one merge-mode and one pick-mode pull request on missing
# commits and asserts both are reported as errors and the tree is untouched,
# and that a conflict rerere does resolve is still reported "resolved".

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
integrate=$here/../scripts/integrate.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
       GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

repo=$work/repo
git init -q "$repo"
cd "$repo"
echo base > f; git add f; git commit -qm base
start=$(git rev-parse HEAD)

ghost=0123456789abcdef0123456789abcdef01234567
# A pick always has a dependency; #5 is merged upstream, so it is met.
printf '10\t4.3.32\tmerge\t%s\t\t\n20\t4.3.32\tpick\t%s\t5\t%s\n' "$ghost" "$ghost" "$ghost" > "$work/plan.tsv"
mkdir "$work/glue"; echo 5 > "$work/merged.txt"

bash "$integrate" "$work/plan.tsv" "$work/glue" "$work/merged.txt"
report=$work/report.tsv

for n in 10 20; do
	if ! grep -qE "^pr	$n	error	" "$report"; then
		echo "FAIL: #$n, whose git command failed, is not reported as an error" >&2
		cat "$report" >&2
		exit 1
	fi
done
if [ "$(git rev-parse HEAD)" != "$start" ]; then
	echo "FAIL: a failed pull request left commits in the tree" >&2
	git log --oneline "$start..HEAD" >&2
	exit 1
fi

# The real thing: #30 and #40 both change f; rerere has seen that conflict.
git checkout -q -b pr30 "$start"; echo p30 > f; git commit -qam pr30; h30=$(git rev-parse HEAD)
git checkout -q -b pr40 "$start"; echo p40 > f; git commit -qam pr40; h40=$(git rev-parse HEAD)
git checkout -q --detach "$start"
git -c rerere.enabled=true merge -q "$h30"
git -c rerere.enabled=true merge -q "$h40" >/dev/null 2>&1 || true
echo resolved > f; git add f; git -c rerere.enabled=true commit -q --no-edit >/dev/null 2>&1
git checkout -q --detach "$start"
printf '30\t4.3.33\tmerge\t%s\t\t\n40\t4.3.33\tmerge\t%s\t\t\n' "$h30" "$h40" > "$work/plan.tsv"
bash "$integrate" "$work/plan.tsv" "$work/glue" "$work/merged.txt"
if ! grep -qE "^pr	40	resolved	" "$report" || [ "$(cat f)" != resolved ]; then
	echo "FAIL: a conflict rerere resolves is not integrated as resolved" >&2
	cat "$report" >&2
	exit 1
fi
echo "PASS: a git failure is an error, not a resolved conflict"
