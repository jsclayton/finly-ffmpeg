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

**Confirm**:
Run the consuming engine's suite against a landed change (through a local package override) and find it green. Confirmation is what a release requires; it is not what landing requires.
_Avoid_: verify, validate, test
