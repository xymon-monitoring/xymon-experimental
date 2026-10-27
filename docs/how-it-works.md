# How xymon-experimental works

For whoever maintains this repository. What it is and how to try it are in the [README](../README.md).

## What goes in

Every pull request there that is open, not a draft, has a milestone, and is
based on `main` or on the branch of another such pull request. A draft or a
pull request without a milestone stays out until that changes.

## In what order

By milestone, then by number, each pull request after the ones it depends on.
Its dependencies are its `Depends-on: #N` lines and, when it is based on
another pull request's branch, that pull request. A dependency already merged
upstream is met: its changes are in `main`.

Each pull request is merged as it stands, unless its branch carries copies of
a dependency that has since changed: then only its own commits are
cherry-picked — those whose subject none of its dependencies' commits have.

A branch ends at each milestone: `experimental/4.3.31` holds the 4.3.31 pull
requests, `experimental/4.3.32` those and the 4.3.32 ones, and so on.

## Conflicts

A conflict resolved once is resolved again the same way: git's `rerere`
replays the resolutions kept on the `rerere-cache` branch. A file a pull request
deletes is deleted, even where an earlier pull request edited it: rerere does
not record that kind of conflict, and the deletion is the pull request's intent. A conflict it has
not seen leaves that pull request out of the build, with every pull request
that depends on it, and the report says which and why. The build goes on.

To add a resolution: run `scripts/select.sh` and `scripts/integrate.sh` in a
clone of xymon with the pull request heads fetched as `refs/pr/N` and
`rerere-cache`'s `rr-cache/` copied into `.git/rr-cache`; redo the merge that
conflicts with `-c rerere.enabled=true`, resolve it, commit it, and open a
pull request here adding the new `.git/rr-cache` entries to `rerere-cache`.

## Glue

Some changes are needed only when several pull requests meet — a test of one
that relies on a setting another adds, a count each one raises by one. They
are not conflicts git can see, so they live in `glue/` as patches whose first
line names the pull requests they join:

    Needs: #219 #406

A glue patch is applied at the end of the first milestone by which every pull
request it names is in the build or already merged upstream, so each milestone
branch carries the glue it needs. One is added or changed by a pull
request here.

## Making a preview

The `experimental preview` workflow, run by hand for a milestone, tags
`experimental/<milestone>` as `preview-<milestone>-<N>`, makes its two
tarballs as xymon's own releases are made, and drafts a pre-release that
lists each pull request and what changed since the preview before. It starts
the lanes on the same commit; publish the draft once they pass.

A pull request merged upstream as it was needs no new preview: the code is the
same, only reviewed now.

## Output

Each run of the `experimental build` workflow leaves, as an artifact, the
report (`EXPERIMENTAL.md`, also on the run's summary page), the plan, and a
git bundle of the milestones; and it pushes each milestone, with the CI of
`cmake/bootstrap` on top, to `candidate/<milestone>`, where the `build` and
`tests` workflows run.

`experimental promote` then moves `experimental/<milestone>` to a candidate
once both have passed. A candidate that fails moves nothing: the branch keeps
the last build that passed, and comparing it with `candidate/<milestone>`
shows whether it is behind. When the newest milestone moves, the lanes are
started on it.

Lanes still running on the newest milestone are cancelled as soon as a
candidate with different code is pushed: they test code about to be replaced,
and hold the runners the candidate's `build` and `tests` would queue for. The
lanes report skips that milestone until the candidate is promoted. If it fails,
the milestone has no lane results until a build passes. A rebuild of the same
code cancels nothing, and an older milestone's lanes (a preview's) are left
alone.

Pushing needs a deploy key with write access, kept as the secret
`EXPERIMENTAL_DEPLOY_KEY` of the `publish` environment, which only workflows
running from `main` can use. A workflow token cannot push commits that touch
`.github/workflows`, and every Xymon branch does.

## When something is left out

Each left-out pull request, and each glue patch that no longer applies, is a
warning on the run's page, and the run fails once the branches are published:
a red run in the list, and GitHub's failure email to whoever last edited the
schedule.

The issue "Experimental build: current state" is rewritten by every run with
the latest report, what is left out at the top and the "Lanes" block, written
by `experimental lanes`, carried over. The body is the current state; its
edit history keeps the earlier ones. A comment is written only for what
someone has to act on: when something is left out and that set changed, one
comment mentions the maintainer. Nothing being left out any more is said by
the body alone.

A glue patch whose change is already in main -- the pull requests it joins
have merged with it -- is reported as obsolete, a notice rather than a
failure: delete it from `glue/`.

## Lanes

Each time a lane run finishes, and once a day as a safety net, `experimental
lanes` looks at the lane runs on each `experimental/<milestone>` branch's
current commit. A lane run's completion cannot start it -- those runs are
started with the workflow token, and GitHub starts no workflow from events that
token causes -- so each lane run's last job dispatches it instead, which that
token may do. A lane GitHub cancelled because no runner
took it -- macOS arm64 runners are short -- is run again, once, when that is
the only kind of miss in its run; a lane that failed is not, since running it
until it passes would hide the intermittent problems the lanes exist to find.
A lane run has finished when each of its jobs has a result; the run's own
status is not waited for, since GitHub can leave it "in progress" long after
the last job ended. Once every lane run for the branch's current commit has
finished, the "Lanes" block of the status issue's body gets the milestone's
row: the commit, how many lanes passed, each lane that did not by name with
its result, how many passed only on a rerun, and when it was looked at, linked
to the runs. While a newer commit's lanes run, or a candidate replacing the
newest milestone is under test, the last finished result stays in the row.
A comment is written only when a commit's lanes finished with one not passed,
once per commit, and it mentions the maintainer; a commit whose lanes all
passed changes the body and nothing else. The workflow's `dry_run` input
prints the block and any comment on the run's summary instead of writing
them.

## When it runs

Every day at 00:17 UTC, and on demand. A scheduled run first hashes what the
build depends on -- the eligible pull requests (number, head, milestone,
base, `Depends-on:` lines), `main`, `rerere-cache` and this repository's
`glue/` and `scripts/` -- and stops within seconds when the hash matches the
last build that published. A change to the CI overlay (`cmake/bootstrap`) or to
this repository's workflows does not count: it changes how the lanes run, not
what they test, so it waits for the next build that has something new to test.
A manual run always builds, unless `if_changed` is set, and applies such a
change at once.

GitHub pauses a scheduled workflow after 60 days without a commit to the
repository, and this one only gets commits when its scripts or glue change.
Each run therefore calls GitHub's "enable workflow" for itself, which resets
that count, as keepalive actions do instead of committing. Should GitHub
still pause it, it says so by notification, and the workflow's page has a
button to enable it again.
