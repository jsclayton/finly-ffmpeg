---
status: accepted
date: 2026-09-08
amends: ADR-0001
---

# Release notes are the human checkpoint; confirmation follows the release

ADR 0001 put engine **confirmation** before the **release** and made that step John's hands. Trying it on the first bump showed the cost: confirmation needs binaries that only a release or a hand-edited package override provides, so the "hands" step was really a sequencing problem, and it put John *in* the loop for a check a machine can run. We decided to move the human checkpoint to where the irreversible act is: John reads **release notes** assembled from what landed since the last tag, and says cut or not. The release is then confirmed *after* the fact by the consumer's own suite against the tag (an engine-repo ticket bumps the pin and runs it). A red confirmation burns one tag number and reopens the work here; the consumer never pins a red tag.

## Considered options

- **Confirm before release through a local override** (ADR 0001's rule). Rejected on experience: the override needs the binary targets rewritten to local paths, it is manual, and it makes John run a suite that an implementer in the engine repo can run as its gate.
- **Confirm nothing and release on the gate.** Rejected: the gate proves the build, not the behaviour, and an unconfirmed tag would sit as the newest release with nothing attesting to it.

## Consequences

- `needs-hands` no longer means "confirm this". It is reserved for what a machine cannot do, and every such issue names its reason: **feel** (judgement on a device), **device** (hardware or a display the Mac cannot drive), **credential** (an account or key only John holds), or **decision**. A check with an oracle (a test, a script, a validator, a comparison) is not needs-hands; the brief names the oracle instead.
- The conductor drafts release notes when John asks to release, or when landed tickets accumulate: every landed ticket since the last tag with its gate evidence and deviations, the consumer-facing changes (API majors, removed symbols, new options), the open needs-hands issues with their reasons, and what confirmation the release will trigger. John reads that, not each issue.
- Cutting the release stays John's act, whether by hand or by asking the conductor to run the release script while he watches, because the tag is immutable.
- The first instance is `v9.0.1-1`: notes drafted on the needs-hands issue the bump filed; confirmation is the engine repo's pin-bump ticket.

## Addendum 2026-09-08 — the notes open with the breaking changes

Versioning here is `v{ffmpeg}-{N}`, so `N` carries no signal a consumer can read: it cannot say "this one changes what you must do" the way a semver major can, and the pin is `.exact` besides, so nothing resolves a break for anyone. That makes these notes the only place a consumer learns the contract moved, which is too much to leave to prose — a ticket that changes the contract now carries the label `breaking` and a `## Consumer-facing change` section in its body, and the draft opens with those sections quoted verbatim, printing "None" when there are none so a reader can tell none from forgotten. The decision is unchanged; this only names the one part of the document that a consumer, rather than John, is the audience for.

## Addendum 2026-09-08 — the notes are short

The first draft the script produced quoted every ticket's gate evidence and deviations, listed every commit by hash, and carried a trailer. John's read: far too much. The notes now hold the breaking changes and the list of tickets landed since the last tag, and nothing else. The gate evidence, deviations and landing shas stay where they were written, on each ticket's Done and landing comments, one click from the notes; the commit log is `git log`. The checkpoint is the decision to cut, and a document sized for that decision is the one that gets read.
