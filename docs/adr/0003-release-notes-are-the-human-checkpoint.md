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
