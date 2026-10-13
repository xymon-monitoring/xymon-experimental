#!/usr/bin/env bash
# report.sh PLAN REPORT_TSV BASE OVERLAY -- the build's report, in Markdown.
set -euo pipefail
plan=$1 rep=$2 base=$3 overlay=$4

count() { awk -F'\t' -v k="$1" -v r="$2" '$1==k && $3==r' "$rep" | wc -l | tr -d ' '; }
echo "# Xymon experimental integration"
echo
echo "Never an approval: a pull request reaches Xymon only through its own review."
echo
echo "- Base: \`main\` at \`${base:0:9}\`"
echo "- Lane machinery: \`cmake/bootstrap\` at \`${overlay:0:9}\`"
echo "- Built: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo
echo "| result | count |"
echo "|---|---:|"
echo "| merged cleanly | $(count pr clean) |"
echo "| merged with a recorded resolution | $(count pr resolved) |"
echo "| left out: conflict nothing resolves | $(count pr conflict) |"
echo "| left out: a dependency is out | $(count pr skipped) |"
echo "| glue applied | $(count glue applied) |"
echo "| glue not needed (a PR it joins is out) | $(count glue skipped) |"
echo "| glue that no longer applies | $(count glue failed) |"
echo
echo "## Milestones"
echo
echo "| milestone | ends at |"
echo "|---|---|"
awk -F'\t' '$1=="milestone"{printf "| %s | `%s` |\n", $2, substr($3,1,9)}' "$rep"
echo
if [ "$(awk -F'\t' '($1=="pr" && ($3=="conflict"||$3=="skipped")) || ($1=="glue" && $3!="applied")' "$rep" | wc -l)" -gt 0 ]; then
	echo "## Left out, and why"
	echo
	echo "| item | result | detail |"
	echo "|---|---|---|"
	awk -F'\t' '($1=="pr" && ($3=="conflict"||$3=="skipped")){printf "| #%s | %s | %s |\n", $2, $3, $4}
		($1=="glue" && $3!="applied"){printf "| glue %s | %s | %s |\n", $2, $3, $4}' "$rep"
	echo
fi
echo "## Pull requests, in merge order"
echo
echo "| PR | milestone | head | how | result |"
echo "|---|---|---|---|---|"
awk -F'\t' 'NR==FNR{ms[$1]=$2; head[$1]=substr($4,1,9); mode[$1]=$3; next}
	$1=="pr"{printf "| #%s | %s | `%s` | %s | %s |\n", $2, ms[$2], head[$2], mode[$2], $3}' "$plan" "$rep"
