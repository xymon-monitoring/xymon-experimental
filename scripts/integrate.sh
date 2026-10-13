#!/usr/bin/env bash
# integrate.sh PLAN GLUE_DIR MERGED_PRS -- build the experimental tree on the
# current HEAD and write report.tsv beside PLAN.
#
# PLAN is select.sh's output. MERGED_PRS lists, one per line, the numbers of
# pull requests already merged upstream, which satisfy a glue patch's Needs.
#
# Each PR is merged, or its own commits cherry-picked, with rerere resolving
# the conflicts it has seen before. A conflict rerere does not know leaves
# the PR out, and with it every PR that depends on it; the build goes on.
#
# Glue patches come last: a change needed only when several PRs meet, applied
# when every PR on its "Needs:" line is in the build or already merged.
#
# report.tsv lines:  pr N result detail  |  glue NAME result detail  |
#                    milestone M commit
set -uo pipefail
plan=$1 glue=$2 merged=$3
report=$(dirname "$plan")/report.tsv
: > "$report"
RR="-c rerere.enabled=true -c rerere.autoupdate=true"
export GIT_EDITOR=true

declare -A in out
unresolved() { git diff --name-only --diff-filter=U | tr '\n' ' '; }

last_ms=""
while IFS=$'\t' read -r n m mode head deps commits; do
	if [ -n "$last_ms" ] && [ "$m" != "$last_ms" ]; then
		printf 'milestone\t%s\t%s\n' "$last_ms" "$(git rev-parse HEAD)" >> "$report"
	fi
	last_ms=$m
	if [ "$mode" = skip ]; then
		out[$n]=1; printf 'pr\t%s\tskipped\t%s\n' "$n" "$commits" >> "$report"; continue
	fi
	missing=""
	for d in ${deps//,/ }; do [ -n "${in[$d]:-}" ] || missing="$missing #$d"; done
	if [ -n "$missing" ]; then
		out[$n]=1; printf 'pr\t%s\tskipped\tneeds%s, left out of this build\n' "$n" "$missing" >> "$report"; continue
	fi
	start=$(git rev-parse HEAD) files="" resolved=""
	if [ "$mode" = merge ]; then
		if ! git $RR merge -q --no-ff -m "experimental: merge #$n" "$head" >/dev/null 2>&1; then
			files=$(unresolved)
			if [ -z "$files" ]; then
				resolved=1; git $RR commit -q --no-edit >/dev/null
			else
				git merge --abort
			fi
		fi
	else
		for c in $commits; do
			git $RR cherry-pick --allow-empty --keep-redundant-commits "$c" >/dev/null 2>&1 && continue
			files=$(unresolved)
			if [ -z "$files" ]; then
				resolved=1; git $RR cherry-pick --continue >/dev/null 2>&1 || git $RR commit -q --allow-empty --no-edit
			else
				git cherry-pick --abort; break
			fi
		done
		[ -n "$files" ] || git commit -q --allow-empty -m "experimental: merge #$n

Its own commits, cherry-picked: $(for c in $commits; do printf '%s ' "${c:0:9}"; done)
The rest of its branch copies pull requests it depends on."
	fi
	if [ -n "$files" ]; then
		git reset -q --hard "$start"
		out[$n]=1; printf 'pr\t%s\tconflict\t%s\n' "$n" "$files" >> "$report"
	else
		in[$n]=1; printf 'pr\t%s\t%s\t%s\n' "$n" "$([ -n "$resolved" ] && echo resolved || echo clean)" "$mode ${head:0:9}" >> "$report"
	fi
done < "$plan"
[ -n "$last_ms" ] && printf 'milestone\t%s\t%s\n' "$last_ms" "$(git rev-parse HEAD)" >> "$report"

for p in "$glue"/*.patch; do
	[ -e "$p" ] || continue
	name=$(basename "$p" .patch) missing=""
	for d in $(sed -n '1s/^Needs://p' "$p" | tr -d '#'); do
		[ -n "${in[$d]:-}" ] || grep -qx "$d" "$merged" || missing="$missing #$d"
	done
	if [ -n "$missing" ]; then
		printf 'glue\t%s\tskipped\tneeds%s\n' "$name" "$missing" >> "$report"; continue
	fi
	if git apply --3way --index "$p" >/dev/null 2>&1; then
		git commit -q -m "experimental glue: $name

$(sed -n '2,/^diff --git/p' "$p" | sed '$d')"
		printf 'glue\t%s\tapplied\t\n' "$name" >> "$report"
	else
		git reset -q --hard HEAD
		printf 'glue\t%s\tfailed\tdoes not apply; the PRs it joins have changed\n' "$name" >> "$report"
	fi
done
