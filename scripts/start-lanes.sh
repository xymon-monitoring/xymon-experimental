#!/usr/bin/env bash
# start-lanes.sh REPO MILESTONE -- start the lanes on experimental/MILESTONE:
# one run per family, amd64 server lanes, and macOS on every architecture.
#
# The family list is also in experimental-promote.yml and
# experimental-preview.yml, which start the same lanes.
set -euo pipefail
repo=$1 ms=$2
for f in alpine archlinux centos7 debian amazonlinux freebsd netbsd openbsd opensuse rockylinux almalinux fedora oraclelinux ubuntu solaris; do
	gh workflow run pipeline-select-run-lanes.yml -R "$repo" --ref "experimental/$ms" \
		-f family="$f" -f arch=amd64 -f variant=server -f verify_depth=test
done
gh workflow run pipeline-select-run-lanes.yml -R "$repo" --ref "experimental/$ms" \
	-f family=macos -f arch=all -f variant=server -f verify_depth=test
