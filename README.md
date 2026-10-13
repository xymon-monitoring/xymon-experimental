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

A glue patch is applied after the merges, when every pull request it names is
in the build or already merged upstream. One is added or changed by a pull
request here.

## Output

Each run of the `experimental build` workflow leaves, as an artifact, the
report (`EXPERIMENTAL.md`, also on the run's summary page), the plan, and a
git bundle holding the milestone branches.

Not done yet: publishing those branches here and running the lanes on them,
which needs a token allowed to push workflow files; and a daily schedule.
