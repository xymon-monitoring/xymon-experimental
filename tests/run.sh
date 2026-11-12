#!/usr/bin/env bash
# tests/run.sh -- run every test in tests/, report each, fail if any fails.
here=$(cd "$(dirname "$0")" && pwd)
fail=0
for t in "$here"/*.sh; do
	[ "$t" = "$here/run.sh" ] && continue
	if bash "$t"; then :; else echo "FAILED: $(basename "$t")"; fail=1; fi
done
exit $fail
