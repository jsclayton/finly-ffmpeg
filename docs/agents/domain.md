# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists: it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo. Neither `CONTEXT.md` nor `docs/adr/` exists yet; the layout below is where they go when `/domain-modeling` creates them. `CLAUDE.md` and `README.md` carry the project vocabulary until then.

```
/
├── CLAUDE.md                     ← hard rules, the vendored-patch rationale, release model
├── README.md                     ← what the pipeline produces, design constraints
├── CONTEXT.md                    ← (not yet) glossary
├── docs/
│   ├── adr/                      ← (not yet) decisions
│   ├── agents/                   ← this file, issue-tracker.md, triage-labels.md, loop.md
│   └── research/                 ← research findings (primary-source notes)
├── build.sh                      ← one-command driver: fetch → cross-compile → xcframeworks → LGPL bundle
├── scripts/
│   ├── config.sh                 ← single source of truth: FFmpeg version, arch matrix, configure set
│   ├── patches/                  ← the five vendored FFmpeg patches (0001–0005)
│   └── *.sh                      ← fetch, build, package, smoke test, release
├── Sources/CFFmpeg/              ← the Swift-facing C-interop module (cff_* shims + tracked libav* headers)
└── Package.swift                 ← vends CFFmpeg + four binary xcframework targets
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
