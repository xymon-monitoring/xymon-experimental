#!/usr/bin/env bash
# preview.sh MILESTONE N BRANCH_HEAD MAIN OUTDIR [PREVIOUS_PRS] -- make preview N
# of a milestone, in a xymon clone that has BRANCH_HEAD and MAIN fetched.
#
# BRANCH_HEAD is experimental/MILESTONE: the milestone with the CI overlay as
# its last commit. The preview is the tree under that commit, so it carries
# none of the CI, with include/version.h saying MILESTONE-previewN: a bug
# report then says which build it came from. MAIN is xymon's main, to find
# where the milestone starts.
#
# Writes to OUTDIR:
#   xymon-VERSION.tar.gz (+ .sha256)  made as the release workflow makes one
#   xymon-VERSION-base.tar.gz (+ .sha256)  the same main without the pull
#                                     requests: the "before" to compare with
#   prs.tsv                           "N<TAB>head" of each pull request in it
#   notes.md                          the release notes
#   commit                            the stamped commit, to tag
#
# PREVIOUS_PRS is the prs.tsv of the preview before, for "since previewN-1".
# Uses gh for each pull request's title and state.
set -euo pipefail

m=$1 n=$2 head=$3 main=$4 out=$5 prev=${6:-}
version="$m-preview$n"
repo=xymon-monitoring/xymon
mkdir -p "$out"

case "$(git log -1 --format=%s "$head")" in
	"CI only:"*) src=$(git rev-parse "$head^") ;;
	*) echo "${head:0:9} does not end with the CI overlay commit; is it experimental/$m?" >&2; exit 1 ;;
esac
base=$(git merge-base "$src" "$main")

# Stamp a tree with a version, as build/dorelease.sh does, and pack it as
# workflow-release.yaml does. The commit is dated as the tree under it, so the
# same tree always gives the same commit and the same tarball bytes.
export GIT_AUTHOR_NAME=xymon-experimental GIT_AUTHOR_EMAIL=xymon-experimental@users.noreply.github.com
export GIT_COMMITTER_NAME=xymon-experimental GIT_COMMITTER_EMAIL=xymon-experimental@users.noreply.github.com
stamp_and_pack() {	# TREE VERSION WHAT -- prints the stamped commit
	local tree=$1 v=$2 what=$3 tarball="xymon-$2.tar.gz"
	git checkout -q --detach "$tree"
	sed -e "s/^#define VERSION \".*\"\$/#define VERSION \"$v\"/" include/version.h > include/version.h.new
	mv include/version.h.new include/version.h
	grep -qxF "#define VERSION \"$v\"" include/version.h || {
		echo "no '#define VERSION' line to stamp in include/version.h" >&2; exit 1; }
	GIT_AUTHOR_DATE=$(git log -1 --format=%cI "$tree") GIT_COMMITTER_DATE=$(git log -1 --format=%cI "$tree") \
		git commit -q -m "preview: Xymon $v" -m "$what" include/version.h
	git -c tar.umask=0022 archive --format=tar --prefix="xymon-$v/" HEAD | gzip -n -9 > "$out/$tarball"
	(cd "$out" && { sha256sum "$tarball" 2>/dev/null || shasum -a 256 "$tarball"; } > "$tarball.sha256")
	git rev-parse HEAD
}

stamped=$(stamp_and_pack "$src" "$version" "Built from experimental/$m at ${head:0:9}, without its CI overlay.")
echo "$stamped" > "$out/commit"
# The "before": main where the milestone starts, without any of its pull
# requests, so a tester can run the two side by side and see what they change.
stamp_and_pack "$base" "$version-base" "xymon main at ${base:0:9}: preview$n without its pull requests." > /dev/null

# What is in it: one "experimental: merge #N" commit per pull request, its head
# the merge's second parent or, when its own commits were cherry-picked, the
# last of them.
: > "$out/prs.tsv"
git log --reverse --format='%H%x09%P%x09%s' "$base..$src" | while IFS=$'\t' read -r c parents subj; do
	case "$subj" in
		"experimental: merge #"*)
			pr=${subj#experimental: merge #}
			set -- $parents
			if [ $# -ge 2 ]; then h=$2
			else h=$(git log -1 --format=%b "$c" | sed -n 's/^Its own commits, cherry-picked: //p' | awk '{print $NF}')
			fi
			printf '%s\t%s\n' "$pr" "$h" >> "$out/prs.tsv" ;;
	esac
done
glue=$(git log --reverse --format=%s "$base..$src" | sed -n 's/^experimental glue: //p')

{
	echo "**Not a release.** Xymon $m as it would be if the pull requests below merged as they stand today. Most of them are not reviewed yet: this is for testing, not for production."
	echo
	echo "Built from xymon \`main\` at [\`${base:0:9}\`](https://github.com/$repo/commit/$base). \`xymon --version\` says \`$version\`."
	echo
	echo "To see what the pull requests change, run it beside \`xymon-$version-base.tar.gz\`: that same \`main\` without them, \`$version-base\`."
	echo
	echo "| PR | | State |"
	echo "|---|---|---|"
	while IFS=$'\t' read -r pr h; do
		read -r state title < <(gh pr view "$pr" -R "$repo" --json state,title -q '"\(.state) \(.title)"')
		case "$state" in MERGED) s="merged" ;; OPEN) s="**not reviewed**" ;; *) s=$(echo "$state" | tr A-Z a-z) ;; esac
		echo "| #$pr | $title | $s |"
	done < "$out/prs.tsv"
	if [ -n "$glue" ]; then
		echo
		echo "Glue between them: $(echo "$glue" | sed 's/^/`/; s/$/`/' | paste -sd, - | sed 's/,/, /g')."
	fi
	if [ -n "$prev" ] && [ -s "$prev" ]; then
		echo
		echo "### Since preview$((n - 1))"
		echo
		changes=$(awk -F'\t' 'NR == FNR { old[$1] = $2; next }
			!($1 in old) { print "- #" $1 " added" ; next }
			old[$1] != $2 { print "- #" $1 " updated" }
			{ delete old[$1] }
			END { for (p in old) print "- #" p " no longer in it" }' "$prev" "$out/prs.tsv" | sort -t'#' -k2 -n)
		echo "${changes:-Nothing changed in the pull requests; main moved on.}"
	fi
	echo
	echo "### Reporting"
	echo
	echo "On the pull request the problem is about, naming \`$version\` and your system. \"Works on ...\" is worth saying there too: it is what a reviewer is waiting for."
} > "$out/notes.md"

echo "$version: $(wc -l < "$out/prs.tsv" | tr -d ' ') pull requests, ${stamped:0:9}"
