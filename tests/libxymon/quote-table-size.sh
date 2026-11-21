#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tests/libxymon/quote-table-size.sh
#
# The escapers in lib/strfunc.c (htmlquoted() and the others) share quote(),
# which copies its table's characters into a 16-byte set for strcspn(). A
# table of 15 entries escapes every one of them. A larger table must stop
# the program with a message: before, its characters were copied past the
# set; stopping short instead would leave the last ones unescaped.
#
# The harness includes strfunc.c to reach the static quote(), and is built
# with AddressSanitizer where the compiler has it.

set -euo pipefail
. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/build-harness.sh"

ROOT=$(find_root)
here=$(dirname "$0")

require_c_buildenv "$ROOT"
lib=libxymon.a
[ -f "$(xymon_lib "$ROOT" "$lib")" ] || lib=libxymonclient.a
[ -f "$(xymon_lib "$ROOT" "$lib")" ] \
	|| skip "tree not built (run make first; the post-build CI suite covers this)"

work=$(mktempdir)
build_xymon_libs "$ROOT" "$work/libbuild.log" "$lib"
san=""
if asan_usable; then san="-fsanitize=address -fno-omit-frame-pointer"; fi
HARNESS_CFLAGS="-iquote $ROOT/include -iquote $ROOT/lib $san" \
	build_harness "$work" "$work/harness" "$here/quote-table-size-harness.c" "$lib"

out=$(ASAN_OPTIONS=detect_leaks=0 "$work/harness" 15 2>"$work/err") \
	|| fail "a table of 15 entries stopped quote(): $(head -3 "$work/err")"
assert_equal "<a><b><c><d><e><f><g><h><i><j><k><l><m><n><o>pqrstuvwxyz" "$out" \
	"a table of 15 entries does not escape each of its characters"

rc=0
out=$(ASAN_OPTIONS=detect_leaks=0 "$work/harness" 16 2>"$work/err") || rc=$?
[ "$rc" -ne 0 ] || fail "a table of 16 entries did not stop quote(): it printed '$out'"
assert_contains "quote: a substitution table has more than 15 entries" "$(cat "$work/err")" \
	"a table of 16 entries stopped quote() without saying why"

claim="quote() escapes a table of 15 entries, and stops with a message on a larger one"
[ -n "$san" ] || pass_partial "$claim" "no AddressSanitizer here: a copy past the set would go unreported"
pass "$claim"
