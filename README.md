# xymon-experimental

Builds the open pull requests of
[xymon-monitoring/xymon](https://github.com/xymon-monitoring/xymon) together,
by milestone, so that their combination is built and tested before any of
them merges.

**This is never an approval.** A change reaches Xymon only through its own
pull request, review and merge there. Nothing here writes to that repository.

## What goes in

Every pull request there that is open, not a draft, has a milestone, and is
based on `main` or on the branch of another such pull request. A draft or a
pull request without a milestone stays out until that changes.

## In what order

By milestone, then by number, each pull request after the ones it depends on.
Its dependencies are its `Depends-on: #N` lines and, when it is based on
another pull request's branch, that pull request.

Each pull request is merged as it stands, unless its branch carries copies of
a dependency that has since changed: then only its own commits are
cherry-picked — those whose subject none of its dependencies' commits have.

A branch ends at each milestone: `experimental/4.3.31` holds the 4.3.31 pull
requests, `experimental/4.3.32` those and the 4.3.32 ones, and so on.

## Conflicts

A conflict resolved once is resolved again the same way: git's `rerere`
replays the resolutions kept on the `rerere-cache` branch. A conflict it has
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
the latest report, what is left out at the top. When what is left out
changes, a comment there mentions the maintainer.

Not done yet: a daily schedule.
