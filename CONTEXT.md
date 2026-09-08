# finly-ffmpeg

The build pipeline that turns a pinned FFmpeg release into Apple xcframeworks, and the C-interop module that surfaces them to Swift. It exists so that the consuming engine depends on a versioned binary artefact, never on an FFmpeg checkout.

## Language

### The product

**Slice**:
One platform-and-variant bucket of an xcframework (iOS device, iOS simulator, tvOS device, tvOS simulator); a simulator slice is fat (arm64 + x86_64).
_Avoid_: arch, target, build

**Patch**:
One of the numbered files under `scripts/patches/`, applied to the pristine upstream tree at fetch time; each exists because this build has no video decoder.
_Avoid_: fork, hack, fix

**Bump**:
A change to the pinned FFmpeg version, and only that: two lines in `scripts/config.sh` plus the tracked headers the build regenerates.
_Avoid_: upgrade, update

**LGPL bundle**:
The corresponding-source package (tarball, patches, scripts, configure options, licences) shipped beside every release so a recipient can rebuild and relink.

### The lifecycle of a change

**Gate**:
The check a change must pass before it lands: the full pipeline plus the simulator probe, as written in `docs/agents/loop.md`.
_Avoid_: tests, suite, CI

**Land**:
Fast-forward a change onto `main` after it passes the gate. Landing proves the build; it does not prove behaviour.
_Avoid_: merge, ship

**Release**:
Cut a tag `v{ffmpeg}-{N}` from the locally built artefacts with `scripts/release.sh`. Immutable; John's hands only; `N` resets to 1 on a bump.
_Avoid_: publish, deploy, ship

**Release notes**:
The short document John reads to decide a release: the breaking changes, then the list of tickets landed since the last tag. The human checkpoint of the loop. Drafted by `scripts/release-notes.sh`, opening with the breaking changes because `v{ffmpeg}-{N}` cannot signal a break the way a semver major would; the gate evidence stays on each ticket.
_Avoid_: changelog, summary

**Breaking change**:
A change a consumer must act on to move to the new tag: a bitstream filter to chain, a chain order, an option or symbol removed or renamed, a library major, a removed component. Its ticket carries the label `breaking` and a `## Consumer-facing change` section that the release notes quote.
_Avoid_: major, API change

**Confirm**:
Run the consuming engine's suite against a released tag and find it green. Confirmation follows a release; it gates neither landing nor releasing. A red confirmation burns the tag number and reopens the work.
_Avoid_: verify, validate, test
