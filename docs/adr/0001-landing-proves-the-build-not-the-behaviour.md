---
status: accepted, amended by ADR-0003
date: 2026-09-08
---

> Amended the same day by ADR 0003: the landing rule below stands, but confirmation now follows the release rather than gating it, and the human checkpoint is the release notes. "Confirm before landing" and "confirm before releasing" are both retired.

# Landing proves the build; confirmation gates the release

This repo has no test suite of its own: the only behavioural check on an FFmpeg bump or a patch change is the consuming engine's suite, which lives in another repository and cannot run here. We decided that a change **lands** on `main` when it passes the gate (full six-slice build, simulator probe, shim compile) and nothing more, and that engine **confirmation** gates the **release** instead: a bump files a `needs-hands` issue asking John to confirm through a local package override and then run `scripts/release.sh`.

## Considered options

- **Confirm before landing.** Block every bump on John running the engine suite against the branch. Rejected: it parks the implementation loop on a manual step for a change that is cheap and reversible on `main`, and it protects nothing, because a release is the only irreversible act and it is already John's alone.
- **Confirm after releasing.** Cut the tag first, confirm against it, burn `N` on failure. Rejected as the default: the release model tolerates a burned tag name, but every bad tag costs a permanent number and a CI reproducibility run; the override path exists precisely so the suite sees the local build first.

## Consequences

- `main` may carry a landed but unconfirmed bump. Consumers pin exact tags, so this is invisible to them.
- `needs-hands` in this repo means the release step, not a landing step; it never blocks the loop.
- The gate must therefore catch everything a build can catch: a patch that fails to apply is red at fetch time, and the simulator probe should assert the patched capabilities it can (see the loop file).
