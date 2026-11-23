#!/usr/bin/env bash
# start-lanes.sh REPO MILESTONE [POLICY] -- start the lanes on
# experimental/MILESTONE: one run per family, amd64 server lanes, and macOS on
# every architecture.
#
# POLICY is which releases of each family run:
#   newest  one lane per family, its newest release: 16 lanes. The default,
#           and what the promotion and the chain start.
#   all     every release: 47 lanes. What a preview starts.
# A family's lanes differ by release (FreeBSD 14.3 to 15.1, five of them); a
# change is usually checked well enough on one, and a preview, which is what
# gets published, is checked on all.
#
# Lane runs still going on an earlier commit of the branch are cancelled
# first: they test code that is gone, and hold runners these need.
#
# The only place the family list is written: experimental-promote.yml,
# experimental-lanes.yml and experimental-preview.yml all start lanes with
# this script.
set -euo pipefail
repo=$1 ms=$2 policy=${3:-newest}
case "$policy" in
newest|all) ;;
*) echo "usage: start-lanes.sh REPO MILESTONE [newest|all]" >&2; exit 2 ;;
esac
workflow=pipeline-select-run-lanes.yml

head=$(gh api "repos/$repo/git/ref/heads/experimental/$ms" -q .object.sha)
gh run list -R "$repo" --workflow "$workflow" -L 100 --json databaseId,status,headSha,headBranch \
	-q ".[] | select(.status != \"completed\" and .headSha != \"$head\" and .headBranch == \"experimental/$ms\") | .databaseId" \
	| while read -r old; do gh run cancel "$old" -R "$repo" || true; done

# start FAMILY ARCH. The workflow is the one on the branch, from
# cmake/bootstrap as it was when the branch was built: one older than
# release_policy refuses the input, and is then started without it, which
# runs every release as before.
start() {
	local err
	if err=$(gh workflow run "$workflow" -R "$repo" --ref "experimental/$ms" \
			-f family="$1" -f arch="$2" -f variant=server -f verify_depth=test \
			-f release_policy="$policy" 2>&1); then
		return 0
	fi
	case "$err" in
	*"Unexpected inputs"*)
		echo "experimental/$ms: its lane workflow has no release_policy; $1 runs every release" >&2
		gh workflow run "$workflow" -R "$repo" --ref "experimental/$ms" \
			-f family="$1" -f arch="$2" -f variant=server -f verify_depth=test
		;;
	*) printf '%s\n' "$err" >&2; return 1 ;;
	esac
}

for f in alpine archlinux centos7 debian amazonlinux freebsd netbsd openbsd opensuse rockylinux almalinux fedora oraclelinux ubuntu solaris; do
	start "$f" amd64
done
start macos all
