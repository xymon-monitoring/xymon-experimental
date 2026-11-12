#!/usr/bin/env bash
# tests/select-dep-cycle.sh
#
# Two pull requests that depend on each other ("Depends-on: #20" in #10 and
# "Depends-on: #10" in #20) form a cycle. closure() followed it without end,
# so select.sh recursed until bash ran out of stack, and the cycle was not
# reported. This builds that cycle beside an independent #30 and asserts
# select.sh finishes, skips the cycle with a reason naming it, and still plans
# #30.

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
for n in 10 20 30; do
	git checkout -q -b "pr$n" main; echo "$n" > "f$n"; git add "f$n"; git commit -qm "pr$n"
	eval "h$n=\$(git rev-parse HEAD)"
done
git checkout -q main

cat > "$work/prs.json" <<JSON
[
 {"number":10,"isDraft":false,"baseRefName":"main","headRefName":"pr10","headRefOid":"$h10","milestone":{"title":"4.3.32"},"body":"Depends-on: #20"},
 {"number":20,"isDraft":false,"baseRefName":"main","headRefName":"pr20","headRefOid":"$h20","milestone":{"title":"4.3.32"},"body":"Depends-on: #10"},
 {"number":30,"isDraft":false,"baseRefName":"main","headRefName":"pr30","headRefOid":"$h30","milestone":{"title":"4.3.32"},"body":""}
]
JSON

rc=0
timeout 60 bash "$select" "$work/prs.json" main > "$work/plan.tsv" 2> "$work/err" || rc=$?
if [ "$rc" != 0 ]; then
	echo "FAIL: select.sh exited $rc on a dependency cycle" >&2
	tail -5 "$work/err" >&2
	exit 1
fi
for n in 10 20; do
	if ! awk -F'\t' -v n="$n" '$1==n && $3=="skip" && $6 ~ /cycle/{f=1} END{exit !f}' "$work/plan.tsv"; then
		echo "FAIL: #$n, in a cycle, is not skipped as such" >&2
		cat "$work/plan.tsv" >&2
		exit 1
	fi
done
if ! awk -F'\t' '$1==30 && $3=="merge"{f=1} END{exit !f}' "$work/plan.tsv"; then
	echo "FAIL: #30, outside the cycle, is not planned" >&2
	cat "$work/plan.tsv" >&2
	exit 1
fi
echo "PASS: a dependency cycle is skipped and named, the rest is planned"
