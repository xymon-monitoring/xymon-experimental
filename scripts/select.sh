#!/usr/bin/env bash
# select.sh PRS_JSON BASE [MERGED] -- print the integration plan, one PR per line:
#   number <TAB> milestone <TAB> mode <TAB> head <TAB> deps <TAB> commits-or-reason
#
# Run inside a clone of xymon with each PR head fetched as refs/pr/N. MERGED
# lists, one number per line, pull requests already merged upstream.
#
# Selected: open, not draft, with a milestone, and based on main or on the
# branch of another selected PR (a stack). A PR's dependencies are its
# "Depends-on: #N" lines plus, for a stack, the PR its base branch belongs to.
# A dependency in MERGED is met: its changes are in BASE already.
#
# Order: by milestone, then number, each PR after its dependencies.
#
# Mode:
#   merge  -- every dependency's head is in this PR's history, so merging
#             the head brings only the PR's own commits;
#   pick   -- the branch carries copies of its dependencies (rebased or
#             since amended): its own commits are those whose subject no
#             dependency's commits have, and they are cherry-picked;
#   skip   -- a dependency is neither selected nor merged, or comes in a
#             later milestone.
set -euo pipefail
prs=$1 base=$2 merged=${3:-/dev/null}
sel=$(mktemp); trap 'rm -f "$sel"' EXIT

# number milestone base-branch head-branch head-sha deps(comma)
jq -r '
  [ .[] | select((.isDraft|not) and .milestone != null) ] as $c
  | ($c | map({(.headRefName): .number}) | add // {}) as $byhead
  | $c[]
  | select(.baseRefName == "main" or ($byhead[.baseRefName] != null))
  | [ .number, .milestone.title, .baseRefName, .headRefName, .headRefOid,
      ( [ (.body // "" | scan("(?m)^Depends-on: *#([0-9]+)") | .[0] | tonumber) ]
        + (if .baseRefName == "main" then [] else [ $byhead[.baseRefName] ] end)
        | unique | map(tostring) | join(",") ) ]
  | @tsv' "$prs" > "$sel"

declare -A ms head deps
while IFS=$'\t' read -r n m _b _h sha d; do
	ms[$n]=$m head[$n]=$sha deps[$n]=$d
done < "$sel"

# All dependencies, transitively.
closure() {
	local n=$1 d out=""
	for d in ${deps[$n]//,/ }; do
		out="$out $d"
		[ -n "${ms[$d]:-}" ] && out="$out $(closure "$d")"
	done
	printf '%s\n' $out | sort -un | tr '\n' ' '
}

# Why an open pull request is not selected, or that it is not open at all:
# closed without merging when MERGED was given, since it would list it.
unselected() {
	local gone="not open"
	[ "$merged" = /dev/null ] || gone="closed without merging"
	jq -r --argjson n "$1" --arg gone "$gone" '
	  [ .[] | select(.number == $n) ][0]
	  | if . == null then $gone
	    elif .isDraft then "a draft"
	    elif .milestone == null then "without a milestone"
	    else "based on \(.baseRefName), which no selected pull request owns" end' "$prs"
}

declare -A emitted
emit() {
	local n=$1 d reason="" mode commits=""
	[ -n "${emitted[$n]:-}" ] && return
	emitted[$n]=1
	for d in ${deps[$n]//,/ }; do
		if [ -z "${ms[$d]:-}" ]; then
			grep -qx "$d" "$merged" && continue
			reason="depends on #$d, which is $(unselected "$d")"
			break
		fi
		if [ "$(printf '%s\n%s\n' "${ms[$d]}" "${ms[$n]}" | sort -V | tail -1)" != "${ms[$n]}" ]; then
			reason="depends on #$d, in the later milestone ${ms[$d]}"
			break
		fi
		emit "$d"
	done
	if [ -n "$reason" ]; then
		printf '%s\t%s\tskip\t%s\t%s\t%s\n' "$n" "${ms[$n]}" "${head[$n]}" "${deps[$n]}" "$reason"
		return
	fi
	mode=merge
	for d in $(closure "$n"); do
		[ -n "${head[$d]:-}" ] || continue
		git merge-base --is-ancestor "${head[$d]}" "${head[$n]}" || mode=pick
	done
	if [ "$mode" = pick ]; then
		local subj=$(mktemp)
		for d in $(closure "$n"); do
			[ -n "${head[$d]:-}" ] && git log --no-merges --format=%s "$base..${head[$d]}"
		done | sort -u > "$subj"
		commits=$(git log --reverse --no-merges --format='%H %s' "$base..${head[$n]}" \
			| while read -r c s; do grep -qxF -- "$s" "$subj" || printf '%s ' "$c"; done)
		rm -f "$subj"
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "${ms[$n]}" "$mode" "${head[$n]}" "${deps[$n]}" "${commits% }"
}

for n in $(awk -F'\t' '{print $2 "\t" $1}' "$sel" | sort -t$'\t' -k1,1V -k2,2n | cut -f2); do
	emit "$n"
done
