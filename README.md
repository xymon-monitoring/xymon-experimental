# xymon-experimental

Builds the open pull requests of
[xymon-monitoring/xymon](https://github.com/xymon-monitoring/xymon) together,
by milestone, so their combination is built and tested before any of them
merges.

**This is never an approval.** A change reaches Xymon only through its own
pull request, review and merge there. Nothing here writes to that repository.

## What goes in

Every pull request there that is open, not a draft, and has a milestone. Each
milestone's branch also holds the earlier milestones: `experimental/4.3.32`
has the 4.3.31 and 4.3.32 pull requests.

## Trying it

Take `experimental/<milestone>`: the last build of that milestone that passed
its tests. `candidate/<milestone>` is newer, and may not have passed. The issue
"Experimental build: current state" lists what each milestone contains and
what was left out.

Download it as a source archive, for example
<https://github.com/xymon-monitoring/xymon-experimental/archive/refs/heads/experimental/4.3.33.tar.gz>,
and build it as any Xymon source (`./configure --server`, `make`). It is `main`
plus pull requests nobody has reviewed yet: for testing, not production. The
`ci/` and `.github/` directories are CI added on top; a build does not use
them.

## Previews

A preview is a milestone frozen for testers, published under
[Releases](https://github.com/xymon-monitoring/xymon-experimental/releases).
Each has two source tarballs:

- `xymon-<milestone>-preview<N>.tar.gz`: the milestone, without the CI;
  `xymon --version` says `<milestone>-preview<N>`.
- `xymon-<milestone>-preview<N>-base.tar.gz`: the same `main` without the pull
  requests. Run it beside the first to see what they change.

The release page lists each pull request in it, reviewed or not. A preview
never changes; a new one is made when its pull requests have changed enough to
be worth testing again. It is not a release candidate: those are made in xymon
itself, once the pull requests are reviewed and merged.

**Found a problem, or that it works?** Say so on the pull request it is about,
naming the preview. That is what its review is waiting for.

## How it works

Order, conflicts, glue patches, the lanes and the schedule:
[docs/how-it-works.md](docs/how-it-works.md).
