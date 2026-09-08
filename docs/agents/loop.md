# Implementation loop — project facts

The per-repo half of the conductor plugin's loop. The rules are the
plugin's `docs/workflow.md`; every skill in the loop reads this file for
the facts below. Keep each entry true; a stale test gate lands red code.

## Project

- **Name:** `finly-ffmpeg` — conductor sessions are named `finly-ffmpeg conductor · <date time>`.
- **Repo:** `jsclayton/finly-ffmpeg` — the slug in the implementer launch prompt.
- **Landing:** rebase onto `main`, fast-forward, no merge commits, no PRs unless John asks.
- **Memory file:** `implementation-loop.md` — the project-memory file the conductor keeps its state and handoff block in.

## Test gate

Run verbatim at every landing and at the end of every implementer run.
This repo has no unit-test suite: its only check is the full pipeline —
fetch + verify the pinned tarball, apply the five patches (a patch that
does not apply is red), cross-compile the six slices, assemble the four
xcframeworks, package the LGPL bundle, then link and run a probe in an
iOS simulator (`SMOKE_OK`). That build is the gate, from the repo root:

```
perl -e 'alarm 1200; exec @ARGV' ./build.sh --smoke
```

- **Wall clock:** bounded at 20 minutes by the `alarm` wrapper. Measured
  2026-09-08 on a fresh worktree (no `vendor/`, `build/` or `artifacts/`,
  so tarball download + all six slices from scratch): **2 min 48 s, green**
  on FFmpeg 9.0.1 (exit 0, `SMOKE_OK`, `avformat 63.1.101`); 3 min 14 s on
  8.1.2 before the bump. Re-measure on every bump — the version and the
  library number here are what a reader checks a gate run against. The
  bound is six times the measurement; a run that hits it is a hung
  simulator or a stuck download, not a slow build. A worktree never shares
  build state with the main checkout, so every implementer run and every
  landing pays the full build.
- **Retry policy:** red is red for anything the build or the patches
  report. The one environment flake is the simulator: `no simulator
  available to boot`, a `simctl boot` failure, or `simctl spawn` printing
  nothing — retry `bash scripts/smoke-test.sh` alone once after
  `xcrun simctl shutdown all`; a second failure is red.
- **Build check:** the CFFmpeg shims must still compile against the
  tracked headers (the one thing a bump breaks that the build itself
  never compiles). Seconds, from the repo root:
  `xcrun clang -fsyntax-only -target arm64-apple-ios26.0-simulator -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" -I Sources/CFFmpeg/include Sources/CFFmpeg/shim.c`
  — exit 0 is green (measured 2026-09-08: under a second). Run it before
  the gate; it names the broken shim where the gate would only say the
  probe failed to link.
- **Not a landing check:** the consumer engine's suite lives in the engine
  repo and cannot run here. Per ADR 0001, a change **lands** on the gate
  alone; engine **confirmation** (through a local package override) gates
  the **release**, which is John's. A bump or patch change files one
  `needs-hands` issue at its end: confirm, then release. That issue never
  blocks landing.

## Review duties

Personas in `.claude/agents/` review; implementers write. Every persona's
frontmatter carries `disallowedTools: ["Bash(git push:*)"]`.

| Touchpoint | Persona | Checks |
| --- | --- | --- |
| everything | none — this repo has no `.claude/agents/` personas | the `code-review` skill reviews every change |

No matching row → the `code-review` skill is the reviewer. Reviewers of
`scripts/patches/*` and `scripts/config.sh` hold the change to the hard
rules in `CLAUDE.md`: no GPL, no non-free, no video codecs, and
`AVSTREAM_PARSE_HEADERS` in 0002/0003 must still neither repack packets
nor set `has_b_frames`.

## Read before briefing

Project docs a brief must read for the ticket's area, and the vocabulary
it must use:

- `CLAUDE.md` — the CFFmpeg/engine line, the five patches and why they exist, the hard rules, the release model.
- `README.md` — what the pipeline produces, the design constraints, the patch rationale in full (0005 included), consumption and releasing.
- `scripts/config.sh` — the configure component set and its comments; the single source of truth for what is built.
- `.claude/skills/bump-ffmpeg/SKILL.md` — the bump procedure, for any ticket that changes `FFMPEG_VERSION`.
- `NOTICE.md` — LGPL obligations, for any ticket that touches packaging or linkage.
- `docs/research/` — primary-source findings; a brief cites the note its ticket came from.
- `CONTEXT.md` — the glossary (slice, patch, bump, LGPL bundle; gate, land, release, confirm); use its words and avoid the ones it lists.
- `docs/adr/` — ADR 0001 (landing proves the build; confirmation gates the release) and ADR 0002 (upstream is the gold standard; every patch is debt). A brief that touches a bump, a patch or the release step cites them.

## Research notes

- `docs/research/ffmpeg-9-upgrade.md` — FFmpeg 9 versus 8.1.2: release state, Changelog, API removals touching the `cff_*` shims, which of patches 0001–0005 still apply, new features for a decoder-less remux build.
- Traps an implementer must know, from the repo docs: never `source scripts/config.sh` into an interactive zsh (`set -euo pipefail`); a bump that breaks a patch must fail loudly at fetch time, never skip a hunk; the API headers under `Sources/CFFmpeg/include/` are tracked and regenerated by the build — a diff there belongs in the same commit as the bump; `vendor/`, `build/` and `artifacts/` are gitignored and per-checkout; releases (`scripts/release.sh`) push and tag, so they are never an implementer's job.

## Implementers

- **Default model:** opus. Sonnet only when the brief marks every bullet mechanical.
- **Patches are never mechanical:** any ticket whose touchpoints include `scripts/patches/` — or whose gate could fail there (an `FFMPEG_VERSION` bump) — is briefed as **opus**, never sonnet, and the brief says so. A hunk that stops applying means upstream moved the hook site; deciding whether the patch is still needed, and where it now belongs, is judgment work, not a rebase.
- **Concurrency:** 1 — and hold it there: every implementer's gate is a full six-slice FFmpeg cross-compile in its own worktree, so two at once double the CPU time of both. Cap 2 only when John says so.
- **Needs-hands:** yes, and it means the release step (ADR 0001). A bump or patch change is machine-verified here by the gate and lands on it; the implementer files one `needs-hands` issue asking John to confirm through a local package override and then release. Everything else in this repo (scripts, docs, CI workflow) is machine-verifiable and files nothing.
