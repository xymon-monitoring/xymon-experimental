#!/usr/bin/env bash
# lane-heads.sh REPO -- the open milestones, oldest first, one per line:
#   milestone <SPACE> 1 when lane runs exist on experimental/<milestone>'s
#   current commit, else 0
# The input scripts/chain.sh reads.
set -euo pipefail
repo=$1
gh api "repos/$repo/branches" --paginate -q '.[] | "\(.name) \(.commit.sha)"' \
	| sed -n 's|^experimental/||p' | sort -V \
	| while read -r ms sha; do
		n=$(gh run list -R "$repo" --workflow pipeline-select-run-lanes.yml --commit "$sha" -L 1 \
			--json databaseId -q 'length')
		echo "$ms $([ "$n" -gt 0 ] && echo 1 || echo 0)"
	done
