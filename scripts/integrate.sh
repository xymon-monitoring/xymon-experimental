#!/usr/bin/env bash
# integrate.sh PLAN GLUE_DIR MERGED_PRS -- build the experimental tree on the
# current HEAD and write report.tsv beside PLAN.
#
# PLAN is select.sh's output. MERGED_PRS lists, one per line, the numbers of
# pull requests already merged upstream, which satisfy a glue patch's Needs
# and a pull request's dependency alike.
#
# Each PR is merged, or its own commits cherry-picked, with rerere resolving
# the conflicts it has seen before, and a file the PR deletes deleted even
# where an earlier PR edited it. A conflict rerere does not know leaves
# the PR out, and with it every PR that depends on it; the build goes on.
#
# Glue patches: a change needed only when several PRs meet, applied at the end
# of the first milestone by which every PR on its "Needs:" line is in the build
# or already merged, so that each milestone branch carries the glue it needs.
#
# A glue patch whose change is already in the tree is reported obsolete, not
# applied: the pull requests it joins have merged with it.
#
# A git failure that is not a conflict (a missing commit, say) leaves the PR
# out as an error, never as resolved.
#
# report.tsv lines:  pr N result detail  |  glue NAME result detail  |
#                    milestone M commit
set -uo pipefail
plan=$1 glue=$2 merged=$3
report=$(dirname "$plan")/report.tsv
: > "$report"
RR="-c rerere.enabled=true -c rerere.autoupdate=true"
export GIT_EDITOR=true

# RELEASENOTES gathers one entry per pull request in a single section, so two
# that both add there conflict on the same anchor though neither entry is
# wrong. Union-merge it, the way a changelog is meant to merge: both sides'
# lines are kept, so the pull requests are integrated instead of left out. The
# attribute is local to the build clone; it changes no pull request and no
# tracked file.
gitdir=$(git rev-parse --git-common-dir)
mkdir -p "$gitdir/info"
printf 'RELEASENOTES merge=union\n' >> "$gitdir/info/attributes"

declare -A in out
declare -A glued
apply_glue() {
	local p name missing d
	for p in "$glue"/*.patch; do
		[ -e "$p" ] || continue
		name=$(basename "$p" .patch) missing=""
		[ -n "${glued[$name]:-}" ] && continue
		for d in $(sed -n '1s/^Needs://p' "$p" | tr -d '#'); do
			[ -n "${in[$d]:-}" ] || grep -qx "$d" "$merged" || missing="$missing #$d"
		done
		[ -n "$missing" ] && { pending[$name]="needs$missing"; continue; }
		glued[$name]=1; unset "pending[$name]"
		if git apply --reverse --check "$p" >/dev/null 2>&1; then
			# Its change is already there: the pull requests it joins have
			# merged, and one of them carried it. Nothing is wrong; it is done.
			printf 'glue\t%s\tobsolete\talready in the tree; delete it\n' "$name" >> "$report"
		elif git apply --3way --index "$p" >/dev/null 2>&1; then
			git commit -q -m "experimental glue: $name

$(sed -n '2,/^diff --git/p' "$p" | sed '$d')"
			printf 'glue\t%s\tapplied\t\n' "$name" >> "$report"
		else
			git reset -q --hard HEAD
			printf 'glue\t%s\tfailed\tdoes not apply; the PRs it joins have changed\n' "$name" >> "$report"
		fi
	done
}
declare -A pending
end_milestone() {
	apply_glue
	printf 'milestone\t%s\t%s\n' "$1" "$(git rev-parse HEAD)" >> "$report"
}

unresolved() { git diff --name-only --diff-filter=U | tr '\n' ' '; }

# A merge or cherry-pick that stops with no unmerged path either had every
# conflict resolved by rerere -- the operation is still in progress, waiting
# for its commit -- or never started: a missing commit, a dirty tree, any git
# error. Only the first is "resolved"; the second is an error, and its first
# line of output says why.
in_progress() { git rev-parse -q --verify "$1" >/dev/null; }
first_line() { printf '%s\n' "$1" | grep -m1 . | tr '\t' ' ' || echo "git failed"; }

# A file the incoming pull request deletes, where an earlier one edited it,
# is a modify/delete conflict, which rerere does not record. The deletion is
# the incoming pull request's stated intent, and edits to a file it removes are
# moot, so it is taken. Only when every unresolved path is of that kind.
take_deletions() {
	local st
	st=$(git status --porcelain | grep -E '^(DD|AU|UD|UA|DU|AA|UU) ')
	[ -n "$st" ] || return 1
	echo "$st" | grep -qvE '^UD ' && return 1
	echo "$st" | cut -c4- | xargs git rm -q --
}

last_ms=""
while IFS=$'\t' read -r n m mode head deps commits; do
	[ -n "$last_ms" ] && [ "$m" != "$last_ms" ] && end_milestone "$last_ms"
	last_ms=$m
	if [ "$mode" = skip ]; then
		out[$n]=1; printf 'pr\t%s\tskipped\t%s\n' "$n" "$commits" >> "$report"; continue
	fi
	missing=""
	for d in ${deps//,/ }; do [ -n "${in[$d]:-}" ] || grep -qx "$d" "$merged" || missing="$missing #$d"; done
	if [ -n "$missing" ]; then
		out[$n]=1; printf 'pr\t%s\tskipped\tneeds%s, left out of this build\n' "$n" "$missing" >> "$report"; continue
	fi
	start=$(git rev-parse HEAD) files="" resolved="" error=""
	if [ "$mode" = merge ]; then
		if ! err=$(git $RR merge -q --no-ff -m "experimental: merge #$n" "$head" 2>&1); then
			take_deletions || true
			files=$(unresolved)
			if [ -n "$files" ]; then
				git merge --abort
			elif in_progress MERGE_HEAD && err=$(git $RR commit -q --no-edit 2>&1); then
				resolved=1
			else
				error=$(first_line "$err")
			fi
		fi
	else
		for c in $commits; do
			err=$(git $RR cherry-pick --allow-empty --keep-redundant-commits "$c" 2>&1) && continue
			take_deletions || true
			files=$(unresolved)
			if [ -n "$files" ]; then
				git cherry-pick --abort; break
			elif in_progress CHERRY_PICK_HEAD \
				&& { git $RR cherry-pick --continue >/dev/null 2>&1 || err=$(git $RR commit -q --allow-empty --no-edit 2>&1); }; then
				resolved=1
			else
				error=$(first_line "$err"); break
			fi
		done
		[ -n "$files$error" ] || git commit -q --allow-empty -m "experimental: merge #$n

Its own commits, cherry-picked: $(for c in $commits; do printf '%s ' "${c:0:9}"; done)
The rest of its branch copies pull requests it depends on."
	fi
	if [ -n "$files" ]; then
		git reset -q --hard "$start"
		out[$n]=1; printf 'pr\t%s\tconflict\t%s\n' "$n" "$files" >> "$report"
	elif [ -n "$error" ]; then
		# reset --hard also drops a merge or cherry-pick left half-done.
		git cherry-pick --abort >/dev/null 2>&1; git merge --abort >/dev/null 2>&1
		git reset -q --hard "$start"
		out[$n]=1; printf 'pr\t%s\terror\t%s\n' "$n" "$error" >> "$report"
	else
		in[$n]=1; printf 'pr\t%s\t%s\t%s\n' "$n" "$([ -n "$resolved" ] && echo resolved || echo clean)" "$mode ${head:0:9}" >> "$report"
	fi
done < "$plan"
[ -n "$last_ms" ] && end_milestone "$last_ms"
for name in "${!pending[@]}"; do
	printf 'glue\t%s\tskipped\t%s\n' "$name" "${pending[$name]}" >> "$report"
done

