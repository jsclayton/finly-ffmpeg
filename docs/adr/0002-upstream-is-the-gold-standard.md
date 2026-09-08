---
status: accepted
date: 2026-09-08
---

# Upstream is the gold standard; every patch is debt

The five vendored patches exist because this decoder-less build cannot recover colour, HDR metadata or a single-layer Dolby Vision stream the way a full FFmpeg does. We decided that each patch is a **temporary deviation to be retired**, not a permanent feature: whenever upstream FFmpeg grows a mechanism that does what a patch does, the preferred path is to adopt upstream's mechanism, even when that costs a consumer-facing contract change (a new bsf to chain, a new option name) and a coordinated release. Bumps stay minimal (the pin and the regenerated headers, nothing else), and patch retirement is its own investigated change.

## Considered options

- **Self-contained patches for good.** Keep `convert=p81` doing the whole profile 7 to 8.1 job inside one bsf because it works and is measured. Rejected as a standing rule: it lets the patch set grow with every bump, and a patch that duplicates upstream logic drifts from it silently.
- **Retire a patch inside the bump that makes it possible.** Rejected: a bump must be two lines so it lands on the gate alone (ADR 0001); retirement needs its own proof and its own release.

## Consequences

- FFmpeg 9.0's `dovi_split` bsf walks every NAL and could take over the enhancement-layer stripping half of patch 0005. It is not adopted in the 9.0.1 bump; an investigation ticket weighs chaining it (a consumer contract change), submitting the patches upstream so they vanish, or the status quo, and recommends one.
- A patch that stops applying on a bump is first asked "does upstream now do this?" before it is rebased.

## Addendum 2026-09-08 — the `dovi_split` investigation ran, and the chain landed

The investigation the consequences above called for was done (`docs/research/patch-0005-toward-upstream.md`), and its recommendation — adopt `dovi_split` rather than keep duplicating it — was accepted. It landed at `da793aa`: the component set enables `dovi_split`, consumers chain `dovi_split=mode=bl_rpu` ahead of `dovi_rpu=convert=p81`, and 0005 shrank to the RPU mutation and the configuration-record rewrite, removing no upstream line at all. This is the rule working as written, consumer contract change and coordinated release included; the sentence above that says `dovi_split` "is not adopted in the 9.0.1 bump" records where that bump stood, not where the repo stands now.
