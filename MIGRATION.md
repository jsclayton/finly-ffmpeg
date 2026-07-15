# Migration note

This repository was extracted on 2026-07-15 from a private, integrated repository
using `git filter-repo`, keeping only the FFmpeg build pipeline (`build.sh`, the
`scripts/` build/fetch/package steps, the vendored `scripts/patches/`, the LGPL
`NOTICE.md`, the CI workflow, and the `bump-ffmpeg` skill) with each file's own
commit history preserved. History before the extraction, and everything else —
the Swift demux/remux engine, its tests, and its tooling — remain in the private
archive repository; only tagged releases of this repo cross the boundary back to
that engine.
