#!/usr/bin/env bash
# tests/integrate-releasenotes-union.sh
#
# RELEASENOTES collects one entry per pull request in a single "(not yet
# released)" section. Two pull requests that both add an entry there touch the
# same anchor, so the second to be integrated conflicts with the first on
# RELEASENOTES though neither entry is wrong -- and integrate.sh would leave
# that pull request (and any depending on it) out of the build. integrate.sh
# union-merges RELEASENOTES so both entries are kept. This builds exactly that
# shape -- two pull requests each adding a line under the same header -- and
# asserts both are integrated, with no RELEASENOTES conflict in the report.

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
printf 'Changes\n=======\n\n(not yet released)\n\n4.3.31\n' > RELEASENOTES
git add RELEASENOTES; git commit -qm base; git branch -q main

# #10 and #20: each adds its own entry on the line after "(not yet released)".
git checkout -q -b pr10 main
sed -i '4a - entry from #10' RELEASENOTES
git commit -qam "pr10: releasenote"; h10=$(git rev-parse HEAD)

git checkout -q -b pr20 main
sed -i '4a - entry from #20' RELEASENOTES
git commit -qam "pr20: releasenote"; h20=$(git rev-parse HEAD)

git checkout -q --detach main

# plan.tsv: number <TAB> milestone <TAB> mode <TAB> head <TAB> deps <TAB> commits
printf '10\t4.3.32\tmerge\t%s\t\t\n20\t4.3.32\tmerge\t%s\t\t\n' "$h10" "$h20" > "$work/plan.tsv"
mkdir "$work/glue"; : > "$work/merged.txt"

bash "$integrate" "$work/plan.tsv" "$work/glue" "$work/merged.txt"
report=$work/report.tsv

if grep -q $'\tconflict\tRELEASENOTES' "$report"; then
	echo "FAIL: a RELEASENOTES entry was left out as a conflict" >&2
	cat "$report" >&2
	exit 1
fi
for n in 10 20; do
	if ! grep -qE "^pr	$n	(clean|resolved)	" "$report"; then
		echo "FAIL: #$n was not integrated" >&2
		cat "$report" >&2
		exit 1
	fi
done
# Both entries must survive in the built tree.
if ! { grep -q 'entry from #10' RELEASENOTES && grep -q 'entry from #20' RELEASENOTES; }; then
	echo "FAIL: an entry was dropped from the merged RELEASENOTES" >&2
	cat RELEASENOTES >&2
	exit 1
fi
echo "PASS: both RELEASENOTES entries are integrated, neither left out"
