# Research: retiring patch 0005 toward upstream

Researched 2026-09-08 against primary sources only: the pinned FFmpeg 9.0.1
release tarball as this repo's own `scripts/fetch-ffmpeg.sh` places it under
`vendor/ffmpeg-9.0.1/`, FFmpeg's contribution documents in that tarball, the
FFmpeg Forgejo instance and Patchwork, and this repo's own patches, ADRs and
`docs/research/ffmpeg-9-upgrade.md`. Every claim cites its source inline, as
`ffmpeg-9.0.1/<path>:<line>` or as a URL. Anything not confirmed from a
primary source is marked UNVERIFIED.

Written for issue #3 (parent spec #1), under ADR 0002 — upstream is the gold
standard; every patch is debt.

## Summary

1. **Option 1 is real and cheap in the build.** Chaining upstream's new
   `dovi_split=mode=bl_rpu` before `dovi_rpu` takes over the whole
   enhancement-layer stripping half of patch 0005. Enabling it costs one
   object file: `dovi_split` selects only `hevcparse`, which the pinned
   component set already enables through the HEVC parser (§1.2).
2. **It deletes 0005's most delicate code.** The descending fragment walk that
   finds and removes interleaved `UNSPEC63` NALs — the largest hunk, and the
   one most coupled to upstream's coded-bitstream internals — goes away. What
   remains is the `convert` option, a three-field RPU mutation and a
   configuration-record rewrite. Counted on the patch file, 0005 is 106 added
   and 9 removed lines today; after Option 1 it is about 69 added and **none
   removed** — a purely additive patch, which matters more for submitting it
   upstream than the line count does (§1.3).
3. **It also repairs a defect the 9.0.1 bump introduced.** FFmpeg 9.0 demuxers
   export the enhancement layer's `hvcE` record as `AV_PKT_DATA_HEVC_CONF`, and
   the MP4 muxer writes it back whenever `strict_std_compliance` is
   `unofficial` — which any Dolby Vision writer must set, because `dvcC`/`dvvC`
   is gated on the same flag. Today's stripped, converted output can therefore
   carry an `hvcE` box describing an enhancement layer 0005 just deleted.
   `dovi_split` removes that side data; 0005 does not (§1.4).
4. **Its cost is a consumer contract change and a coordinated release**: a new
   entry in `--enable-bsf`, a second bitstream filter the consumer must
   instantiate and chain, and a release of this repo that precedes the
   consumer's change (§1.5).
5. **Option 2 pays off in quarters, not tickets.** A feature merged upstream
   never enters a point release, so it reaches a tarball only at the next
   major — measured cadence about four months, and `dovi_split`'s own history
   is eleven weeks from submission to tarball *because* it landed four weeks
   before a branch cut (§2.1). Of the five patches, only 0005's conversion is
   a strong candidate; 0002/0003 are unlikely to be accepted in their present
   shape (§2.2). Its contract cost is *lower* than Option 1's — none at all if
   the patch is accepted unchanged, and a renamed option if it is not (§2.3).
   Option 3, the status quo, has no contract cost and no release at all, and
   carries the §1.4 defect instead (§3).
6. **Recommendation (§4): take Option 1 as its own ticket, then submit the
   shrunken `convert=p81` upstream; keep 0001–0004 at status quo.**

---

## 1. Option 1 — chain `dovi_split=mode=bl_rpu` before `dovi_rpu`

### 1.1 What `dovi_split` is, and what `bl_rpu` mode does

`dovi_split` is new in FFmpeg 9.0: "Bitstream filter to split Dolby Vision
multi-layer HEVC" (`ffmpeg-9.0.1/Changelog:108`). It was submitted as Forgejo
pull request 23122 by Kacper Michajłow, opened 2026-05-16 and merged
2026-05-31 (<https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls/23122>; the same
series is mirrored at
<https://patchwork.ffmpeg.org/project/ffmpeg/list/?q=dovi_split&state=*&archive=both>,
where it is the only match).

Its four modes are documented at `ffmpeg-9.0.1/doc/bitstream_filters.texi`,
section `dovi_split`, and defined at
`ffmpeg-9.0.1/libavcodec/bsf/dovi_split.c:250-257`. In `bl_rpu` mode
(`ffmpeg-9.0.1/libavcodec/bsf/dovi_split.c:60-62`) the filter keeps base-layer
NALs and the RPU and drops the enhancement layer:

* `nal_is_kept()` (`:137-167`) walks **every** NAL of the packet. `UNSPEC63`
  (enhancement layer) returns 0 unless the mode keeps EL; `UNSPEC62` (RPU) is
  kept **verbatim**, `*payload = nal->raw_data`, `*payload_size =
  nal->raw_size` (`:152-158`); anything else is base layer and is kept
  verbatim (`:159-165`).
* `dovi_split_filter()` (`:169-246`) splits the packet with
  `ff_h2645_packet_split()`, sizes the output from the kept NALs, then copies
  each kept NAL's **raw** (escaped) bytes into a fresh buffer with a fresh
  length prefix (`:212-229`), and carries the packet's properties with
  `av_packet_copy_props()` (`:231`).
* `dovi_split_init()` (`:57-129`) masks three flags in the Dolby Vision
  configuration record in place: `bl_present_flag &= keep_bl`,
  `el_present_flag &= keep_el`, `rpu_present_flag &= keep_rpu` (`:68-79`). In
  `bl_rpu` mode that clears `el_present_flag` and leaves the other two set.
* It also removes `AV_PKT_DATA_HEVC_CONF` from the output parameters, "as it's
  no longer valid on output" (`:117-121`).

**What it does not do.** `dv_profile` and `dv_bl_signal_compatibility_id` are
read but never written (`:77` reads `dv_profile` only to pick an
enhancement-layer size divisor), and the RPU payload is copied byte for byte.
So `dovi_split` alone produces a stream that still *declares itself* profile 7
and still carries a profile-7 RPU. It cannot produce a valid single-layer 8.1
stream. This confirms and refines the finding already recorded in
`docs/research/ffmpeg-9-upgrade.md` §4.

### 1.2 Build cost: one object file

`configure` selects `dovi_split_bsf_select="hevcparse"`
(`ffmpeg-9.0.1/configure:3756`), and `hevcparse_select="golomb"`
(`:3096`). This repo's component set already enables the HEVC parser
(`scripts/config.sh`, `--enable-parser=h264,hevc,…`), and
`hevc_parser_select="hevcparse hevc_sei"` (`ffmpeg-9.0.1/configure:3742`), so
`CONFIG_HEVCPARSE` — and with it `h2645data.o h2645_parse.o h2645_vui.o`
(`ffmpeg-9.0.1/libavcodec/Makefile:119`) — is already compiled into every
slice. Adding `dovi_split` to `--enable-bsf` therefore adds
`libavcodec/bsf/dovi_split.o` (278 lines of source) and nothing else. For
comparison, `dovi_rpu_bsf_select="cbs_h265 cbs_av1 dovi_rpudec dovi_rpuenc"`
(`:3755`) is the entry the configure-set comment in `scripts/config.sh`
already calls out as the expensive one; `dovi_split` is nowhere near it.

Hard-rule check (`CLAUDE.md`): `hevcparse`/`golomb` are parsing helpers, not a
video decoder; nothing in the chain is GPL- or nonfree-gated. Enabling
`dovi_split` keeps the build LGPL-clean and decoder-less.

### 1.3 What patch 0005 would still have to do

After `dovi_split=mode=bl_rpu` has run, `dovi_rpu` receives an access unit with
no `UNSPEC63` NALs and an unmodified profile-7 RPU, and a configuration record
whose `el_present_flag` is already cleared. Patch 0005 would still be
responsible for **all three of the following**, none of which upstream does:

1. **The RPU three-field mutation**, in `update_rpu()`:
   `disable_residual_flag = 1`, `el_spatial_resampling_filter_flag = 0`,
   `nlq_method_idc = AV_DOVI_NLQ_NONE`
   (`scripts/patches/0005-dovi-rpu-bsf-profile7-to-81.patch`, hunk 3).
   `dovi_split` copies the RPU verbatim
   (`ffmpeg-9.0.1/libavcodec/bsf/dovi_split.c:152-158`) and no other component
   in 9.0.1 rewrites RPU fields for a profile change.
2. **The configuration-record rewrite**, in `dovi_rpu_init()`:
   `dv_profile = 8`, `dv_bl_signal_compatibility_id = 1`, `el_present_flag = 0`,
   `dv_md_compression = AV_DOVI_COMPRESSION_NONE` (hunk 6). `dovi_split` writes
   only `el_present_flag`; the other three fields are untouched by it, and a
   record still saying profile 7 makes the muxer write the wrong fourcc.
3. **The option and its guards**: the `convert` option itself (hunk 7), the
   `strip`/`convert` mutual exclusion and the forcing of
   `compression = NONE` (hunk 5), the "input must be profile 7" check and the
   "refuse to convert without a configuration record" check (hunk 6).

**What drops out** is hunk 4 — the rewrite of `dovi_rpu_update_fragment_hevc()`
that walks the fragment in descending order deleting every `UNSPEC63` unit and
then re-finds the RPU by search. Counted on
`scripts/patches/0005-dovi-rpu-bsf-profile7-to-81.patch`, the seven hunks add
106 lines and remove 9; hunk 4 alone is +37 −9, so it is the largest hunk and
the **only** one that removes an upstream line. It is also the most
upstream-coupled code in the repo: it depends on `ff_cbs_delete_unit()`
shifting the unit array, on unit ordering within a coded-bitstream fragment,
and on the empirical claim that the RPU is the last NAL of the access unit.

**Net, in two variants**, both worth putting side by side because the choice
between them is a real one:

* **Drop hunk 4 entirely** and let `dovi_rpu` go back to upstream's single-unit
  probe, which is correct once the enhancement layer is gone (the RPU was
  already last in the source, and `dovi_split` preserves NAL order). 0005
  becomes six hunks, **+69 −0**: a patch that only adds. That is a 35 % line
  reduction, but the number that matters is the zero — a purely additive patch
  against an untouched upstream function is far easier both to carry across
  bumps and to submit (§2.2).
* **Keep three lines of hunk 4** — the loop that finds the `UNSPEC62` unit by
  search rather than by position — and 0005 is seven hunks at roughly **+79
  −1**. Upstream inspects only the last unit
  (`docs/research/ffmpeg-9-upgrade.md` §4, `dovi_rpu.c:83-98` in the pristine
  tree), which is correct only if the RPU is last, and the evidence that it is
  last is indirect: patch 0005's own comment records that on a real dual-layer
  source `strip=1` deleted 99 of 99 RPUs through exactly that last-unit probe.
  The three lines buy independence from that assumption.

Either way the change in kind is the same, and it is larger than the change in
size: 0005 stops manipulating NAL structure and becomes metadata-field writes.
The first variant is the better one to submit upstream; the second is the safer
one to carry if the byte-equality check of §1.6 ever shows the RPU is not last
in some source.

### 1.4 A defect in the status quo that Option 1 also fixes

FFmpeg 9.0 added export of the enhancement layer's own
HEVCDecoderConfigurationRecord as `AV_PKT_DATA_HEVC_CONF` coded side data,
from both demuxers this build ships (`docs/research/ffmpeg-9-upgrade.md` §4:
`mov.c:8866`, `matroskadec.c:2518-2524`), and both muxers write it back — MP4
as an `hvcE` box (`ffmpeg-9.0.1/libavformat/movenc.c:2543`, written at
`:3010-3017`), Matroska as an `hvcE` BlockAdditionMapping
(`ffmpeg-9.0.1/libavformat/matroskaenc.c:1789-1800`).

The MP4 write is gated: `if (hvce && mov->fc->strict_std_compliance <=
FF_COMPLIANCE_UNOFFICIAL)` (`movenc.c:3013`). The Dolby Vision configuration
box immediately above it carries the *same* gate: `if (dovi &&
mov->fc->strict_std_compliance <= FF_COMPLIANCE_UNOFFICIAL)`
(`movenc.c:3004-3008`). `FF_COMPLIANCE_UNOFFICIAL` is `-1` and the default
`FF_COMPLIANCE_NORMAL` is `0` (`ffmpeg-9.0.1/libavcodec/defs.h:59-61`), so a
writer that wants a `dvvC` box at all **must** be running at `unofficial` —
and then the `hvcE` gate is open too.

Consequence for the status quo on 9.0.1: converting a profile-7 source whose
container carried an `hvcE`/BlockAdditionMapping produces an MP4 with a
`dvvC` that says single-layer 8.1 and an `hvcE` that describes an enhancement
layer no longer present in the bitstream. `dovi_split` removes the side data
(`dovi_split.c:117-121`); patch 0005 has no equivalent, because when it was
written no FFmpeg release exported `AV_PKT_DATA_HEVC_CONF` at all.

This is not a reason to rush: whether any real source in the consumer's
library carries an `hvcE` is UNVERIFIED here and belongs in the consumer's own
tracker. But it means Option 1 is a correctness improvement, not only a
simplification — and it means the status quo (Option 3) now has a defect
attached to it that 0005 would otherwise have to grow a fourth hunk to fix.

### 1.5 The consumer contract change, and the coordinated release

Two changes, in this order:

1. **This repo.** Add `dovi_split` to the `--enable-bsf=` list in
   `scripts/config.sh` (per §1.2 this adds one object and no new subsystem),
   shrink `scripts/patches/0005-*.patch` to §1.3's three hunks, and extend the
   simulator probe to look `dovi_split` up by name and find its `mode` option
   — the same shape as the probe assertion spec #1 added for `dovi_rpu`'s
   `convert` option, and a check the gate can make with no media fixture.
2. **The consumer.** Instantiate a second `AVBSFContext` for `dovi_split` with
   `mode=bl_rpu`, run it ahead of `dovi_rpu`, and carry the first filter's
   `par_out` into the second filter's `par_in`. That copy is not optional:
   `dovi_rpu_init()` reads and mutates `bsf->par_out->coded_side_data`
   (visible in the patched
   `vendor/ffmpeg-9.0.1/libavcodec/bsf/dovi_rpu.c:275-288`, and in hunk 6 of
   the patch), so the record `dovi_split` masked has to be the record
   `dovi_rpu` sees.

The order is forced: `dovi_split` must run first, because after `dovi_rpu` has
rewritten the record to profile 8 with `el_present_flag = 0` there is nothing
left to tell `dovi_split` what to strip, and because `dovi_rpu` would still be
seeing interleaved `UNSPEC63` NALs it no longer has code to remove.

**Coordinated release.** The consumer cannot chain a bitstream filter that is
not compiled into the artefacts, and consumers pin exact tags. So the sequence
is the loop's ordinary one, read through ADR 0003: land the change here on the
gate (ADR 0001); the conductor drafts release notes naming the new component
and the new option as consumer-facing changes; John reads them and cuts the
tag; the consumer's own repository then bumps its pin to that tag, chains the
filter, and runs its suite — which is the confirmation, and it follows the
release. A red confirmation burns one `N` and reopens the work here. The
intermediate state is safe in one direction only: the new artefacts still work
with the old consumer, because `dovi_split` merely becomes available; the old
artefacts do not work with the new consumer.

### 1.6 Proving equivalence, without carrying media in this repo

**The fixture already exists upstream and is public.** FFmpeg's FATE suite
carries `dovi-p7-hvce.mkv`, 657 KB, dated 2026-05-17, downloadable from
<https://fate-suite.ffmpeg.org/mkv/>. It is used by four tests added with
`dovi_split` (`ffmpeg-9.0.1/tests/fate/hevc.mak:250-260`), and their reference
outputs establish what it contains: one 3840×2160 access unit whose base layer
is 491 260 bytes (`tests/ref/fate/hevc-bsf-dovi-split-bl`), whose base layer
plus RPU is 491 661 bytes (`…-bl-rpu`) — so the RPU NAL is 401 bytes — and
whose unwrapped enhancement layer is 1920×1080 and 175 255 bytes (`…-el`),
175 656 with the same 401-byte RPU (`…-el-rpu`). A single track carrying both
an interleaved enhancement layer and an `hvcE` record is exactly the input
shape patch 0005 was written for.

So the proof needs **no media in this repo and no private media anywhere**: a
public FFmpeg FATE sample, fetched at check time, is sufficient for the
bit-level comparison. Its one limitation is that it is a single access unit,
which cannot exercise the RPU rewrite across a GOP or the interaction with
non-keyframe RPU compression; a longer dual-layer profile-7 clip covers that,
it lives in the consumer's repository, and it belongs to the confirmation that
follows the release (ADR 0003), not to this repo's gate.

**The comparison, in three checks:**

1. **Byte equality of the elementary stream.** Run the same source through
   today's single filter (`dovi_rpu=convert=p81`) and through the chain
   (`dovi_split=mode=bl_rpu` then `dovi_rpu=convert=p81`) and compare the
   output packets byte for byte. If they are identical, checks 2 and 3 are
   already implied for the bitstream, and the whole equivalence question
   reduces to the container-level metadata. This is the check that should be
   run first, because it is cheap and it either settles the matter or points
   straight at the difference.
2. **RPU equality against an independent oracle.** Extract the RPUs from the
   converted output and diff them frame by frame against `dovi_tool`'s own
   profile-7 conversion of the same source — the same third-party tool patch
   0005's comment used to derive the three-field mutation in the first place
   (<https://github.com/quietvoid/dovi_tool>). This is the only expected value
   in the whole exercise that does not come from FFmpeg, so it is the one that
   proves the conversion is right rather than merely unchanged.
3. **Container metadata equality, plus the one intended difference.** The
   written `dvvC` must carry `dv_profile = 8`,
   `dv_bl_signal_compatibility_id = 1`, `el_present_flag = 0`,
   `dv_md_compression = 0`, identically on both paths; and the chained path
   must write **no** `hvcE` box where today's path writes one (§1.4). That
   difference is the point, not a regression, and it is the only expected
   divergence between the two paths.

### 1.7 Risks and things still unverified

* **Double parse per packet.** `dovi_split` runs `ff_h2645_packet_split()` and
  rebuilds the packet; `dovi_rpu` then parses the result again through the
  coded-bitstream layer. Kept NALs are copied from `nal->raw_data` verbatim
  (`dovi_split.c:212-229`), so the repack is byte-preserving, but it is a real
  extra pass over every video packet. Measure it against the previous
  artefacts, as the `scripts/config.sh` comment already asks for the DV path.
* **NAL length-prefix size.** The output prefix size follows
  `par_out->extradata` (`dovi_split.c:123-126`, used at `:179`); in `bl_rpu`
  mode `par_out->extradata` is untouched, so a length-prefixed input stays
  length-prefixed. UNVERIFIED against a real stream: the merged pull request's
  review discussion describes the filter as emitting Annex B exclusively
  (<https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls/23122>), which the merged
  source contradicts. The shipped source is what this build compiles, but this
  is the single most important thing to confirm empirically before committing
  to the chain.
* **`EAGAIN` on an all-dropped access unit.** `dovi_split_filter()` returns
  `AVERROR(EAGAIN)` when no NAL is kept (`dovi_split.c:200-203`). In `bl_rpu`
  mode every access unit has base-layer NALs, so it should never fire; a
  consumer must nonetheless treat `EAGAIN` as "no output yet", not as failure.
* **One silent drop path.** `ff_h2645_packet_split()` discards any NAL with
  `nuh_layer_id == 63` (`ffmpeg-9.0.1/libavcodec/h2645_parse.c:650-651`). The
  Dolby Vision wrappers use layer id 0 — the two-byte headers are `0x7E01`
  (type 63) and `0x7C01` (type 62), per the pull-request discussion — so they
  survive. Recorded because it is the one place a NAL can vanish without a log
  line.
* **RPU-is-last assumption.** Addressed in §1.3 by keeping 0005's search loop
  rather than reverting to upstream's last-unit probe.

---

## 2. Option 2 — submit the patches upstream

### 2.1 The path, and how long it takes

**Where patches go.** Forgejo pull requests at
<https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls> or the `ffmpeg-devel` mailing
list, with `git format-patch`/`git send-email`
(`ffmpeg-9.0.1/doc/developer.texi:758-766`). GitHub pull requests "are not part
of our review process and **will be ignored**"
(`ffmpeg-9.0.1/CONTRIBUTING.md`). The mailing list is subscribers-only
(`developer.texi:879-880`).

**Licence.** Contributions must be LGPL 2.1 "including an 'or any later
version' clause" — LGPL is preferred over the acceptable alternatives
(`developer.texi:434-444`). This repo's patches carry no licence header of
their own and modify existing LGPL files, so nothing here conflicts. Patches
must be signed off, `git commit -s` (`developer.texi:866-870`).

**What the checklist demands.** `make fate` must pass (`:862`); the change must
be minimal, "so that the same cannot be achieved with a smaller patch and/or
simpler final code" (`:883-884`); and "Consider adding a regression test for
your code. All new modules should be covered by tests. That includes …
bitstream filters, parsers. If its not possible to do that, add an explanation
why" (`:956-960`).

**Review.** "We will review all submitted patches, but sometimes we are quite
busy so especially for large patches this can take several weeks" (`:982-984`).
Resubmission cycles are expected (`:971-981`).

**Release.** This is the decisive constraint. Point releases accept only
security fixes, documented-bug fixes and documentation improvements, and must
retain source and binary compatibility (`developer.texi:1116-1137`). A new
feature therefore never reaches a point release: it reaches a tarball only at
the next **major**, and only if it is merged before that major's branch cut.

`dovi_split`'s own history is the measured example: pull request opened
2026-05-16, merged 2026-05-31; the 9.0 branch was cut from master 2026-06-26
and 9.0 was released 2026-08-03/04 (dates from
`docs/research/ffmpeg-9-upgrade.md` §1, which cites
<https://ffmpeg.org/download.html> and the signed git tags). That is about
eleven weeks from submission to a tarball — a best case, achieved by landing
four weeks before a branch cut. Missing a branch cut costs a whole cycle:
`ffmpeg-9.0.1/RELEASE_NOTES` puts 9.0 "about 4 months after the release of
FFmpeg 8.1".

**So upstreaming never removes a patch now.** Even a patch accepted on the
first review round stays vendored here until the pin reaches the release
containing it, and the patch must keep applying to every intermediate bump in
the meantime. Option 2's payoff is measured in quarters; Option 1's is
measured in one ticket. That asymmetry drives the recommendation in §4.

### 2.2 Per-patch upstreamability

| Patch | Shape upstream | Verdict |
|---|---|---|
| 0001 | ~17 lines in the HEVC parser | Plausible, needs a sample and a champion |
| 0002 | 2 lines in `matroskadec` | Unlikely as-is |
| 0003 | 2 lines in `mov` | Unlikely as-is |
| 0004 | ~110 lines, one new internal function | Best-shaped of 0001–0004, but bound to 0002/0003 |
| 0005 | +69 −0 after Option 1, one new option | **Strongest candidate of the five** |

**0001 — HEVC parser exports SPS VUI colour to `AVCodecContext`.** Small,
self-contained, mirrors what `hevcdec.c` already does, touches no public
interface. In its favour: the parser already decodes the VUI, so this is pure
gap-filling, and container colour still wins downstream
(`avformat` restores it over `codecpar`), so the change can only fill a silent
container. Against it: it changes probed output for every FFmpeg build, not
only decoder-less ones, and upstream's implicit answer to "no colour without a
decoder" has been "open the decoder". The regression-test requirement needs a
sample whose container carries no colour and whose SPS VUI does; whether any
existing FATE sample qualifies is UNVERIFIED. Maintainer: `hevc/*` — Anton
Khirnov (`ffmpeg-9.0.1/MAINTAINERS:197`). A search of Patchwork for prior
attempts at parser-side colour export returned no matching series
(<https://patchwork.ffmpeg.org/project/ffmpeg/list/?q=hevc+parser+color&state=*&archive=both>,
"No patches to display"); UNVERIFIED beyond that, because the `ffmpeg-devel`
pipermail archive offers no search facility and its monthly index stops at
August 2025, which leaves Patchwork the only searchable view of the list
(Sources).

**0002 and 0003 — demuxers run HEVC header parsing.** Two lines each, and the
hardest sell of the five. They turn the HEVC parser on for every HEVC stream in
every Matroska and MP4 file, for every FFmpeg user, to fix a problem only a
decoder-less build has. `matroskadec` excludes HEVC explicitly
(`if (par->codec_id != AV_CODEC_ID_HEVC)`) and `mov` omits it from the stsd
switch; the reason is not recorded in any source reachable from here — a blame
walk on `libavformat/matroskadec.c` at the `n9.0.1` tag reaches only
refactoring commits (`c2b8a694e` "Reindent after the previous commit",
2023-09-06, and its parent `c8903755a` "Factor generic parsing of video tracks
out", 2023-09-03), and a GitHub commit-message search over the repository for
the introducing change returned nothing. UNVERIFIED. What is certain is the
cost side: extra work in `find_stream_info` for a very large installed base,
and reference-output churn across many FATE tests, which reads to a reviewer as
the opposite of "minimal" (`developer.texi:883-884`). A shape that could pass
— an opt-in demuxer option, or making parsing conditional on the container
having declared no colour — is a new interface (`developer.texi:564`, "Adding
new interfaces") and a much larger negotiation.

**0004 — mastering-display and content-light SEI into `coded_side_data`.** The
best-shaped of the four. It adds one internal function,
`ff_h2645_sei_to_coded_side_data()`, behind the `ff_` prefix, so there is no
public API change and no version bump; and it is *bug-shaped*, which is the
strongest form a submission can take: a `-c copy` remux of an HEVC stream whose
HDR10 metadata lives only in SEI loses `mdcv`/`clli`, because the existing
export targets `decoded_side_data`, which
`avcodec_parameters_from_context()` does not propagate. Against it: it
duplicates the rescale-and-validate logic already in `h2645_sei.c` instead of
factoring it out, and the minimality rule guarantees a reviewer asks for the
shared helper. More importantly, upstreamed **alone** it changes nothing for
MP4 or Matroska, because the parser it hangs off only runs for those
containers when 0002/0003 are in effect. So 0004's upstream value is
conditional on the two patches least likely to be accepted.

**0005 — `dovi_rpu convert=p81`.** The strongest candidate, and the only one
whose value upstream is not conditional on another patch.

* It is a user-visible feature on an existing filter, of obvious general
  value: dual-layer profile 7 to single-layer 8.1 is the conversion users
  currently reach for the third-party `dovi_tool` to perform, piping through
  FFmpeg to do it (<https://github.com/quietvoid/dovi_tool>).
* The regression test the checklist asks for is straightforward, because
  upstream **already carries the sample**: `fate-suite/mkv/dovi-p7-hvce.mkv`
  (§1.6), with four existing `dovi_split` tests at
  `ffmpeg-9.0.1/tests/fate/hevc.mak:250-260` as the pattern to copy.
* The area is demonstrably active — `dovi_split` merged in 2026 — and
  `MAINTAINERS` lists no owner for `dovi_*` or `libavcodec/bsf/`, so review
  would go to the general list rather than through a single gatekeeper.
* After Option 1 the submission is a third of its current size and contains no
  NAL-structure manipulation at all, which materially improves its odds
  against the minimality rule.

Against it: the three-field mutation's justification in the patch comment is
empirical — measured by diffing `dovi_tool`'s conversion — and a reviewer may
want it argued from the Dolby specification, which is not public. And the
unconditional forcing of `compression = NONE` when converting is a policy
choice that upstream might prefer to express as rejecting a conflicting
`compression` value instead. Both are review-round comments, not rejections.

### 2.3 The consumer contract change, and the release it needs

Upstreaming looks contract-free. It is not, and the shape of the cost depends
on how the submission lands.

**Accepted unchanged.** The contract change is a *deletion*, and it is still
coordinated. The vendored patch cannot be dropped when the patch merges: it is
dropped at the bump that first pins a release containing it, because until then
this repo is still building an FFmpeg that lacks the feature. That bump is also
the moment the two copies would collide — a patch that no longer applies must
fail loudly at fetch time (`docs/agents/loop.md`, Research notes) — so the bump
ticket deletes the patch file in the same commit as the pin. One ordinary bump,
one release. The consumer's own code does not change at all, because the option
name and its behaviour are the same ones it already passes.

**Accepted in a different shape.** Then the contract change is real, and it is
exactly the class ADR 0002 named in advance: "a new bsf to chain, a new option
name". Resubmission after review comments is the normal path
(`ffmpeg-9.0.1/doc/developer.texi:971-981`), and renaming an option is among
the commonest of those comments, so `convert=p81` may well land upstream under
another spelling. The consumer passes that option string, so a rename is a
consumer change, and it lands the way Option 1's does: land here, release
notes, tag, then the consumer pins the new tag (§1.5).

**Rejected.** No contract change and no release; the status quo (§3) continues
and the only cost spent is review time — this repo's and upstream's.

So Option 2's coordinated release is *cheaper* than Option 1's in the
accepted-unchanged case and identical to it in the renamed case. What makes
Option 2 expensive is not its contract, it is its latency (§2.1). That is also
why it belongs *after* Option 1 rather than instead of it: Option 1's contract
change is paid once, and it is what makes the submission small enough — and
purely additive enough (§1.3) — to have a chance of being accepted unchanged.

---

## 3. Option 3 — status quo

Keep 0005 self-contained. No consumer contract change, no coordinated release,
no new component in the configure set.

The carrying cost, per bump, is what `CLAUDE.md` and the loop file already
describe: re-verify that all five patches apply, because their struct paths and
hook sites are version-specific. 0005 is measurably the most fragile of the
five — it is the only one that needed default fuzz on the 9.0.1 bump, when
`#include "hevc/hevc.h"` became `#include "libavcodec/hevc/hevc.h"`
(`docs/research/ffmpeg-9-upgrade.md` §4) — and its fragment walk is the code
most exposed to upstream churn in the coded-bitstream layer.

On top of that carrying cost, the status quo now owns the stale-`hvcE`
defect described in §1.4, which arrived with the 9.0.1 bump and which fixing
inside 0005 would mean growing the patch rather than shrinking it. That is the
opposite direction from ADR 0002.

Status quo remains the right answer for **0001–0004**: upstream 9 still does
none of what they do (`docs/research/ffmpeg-9-upgrade.md` §4, per-patch
analysis), they applied to 9.0.1 with offsets only, and §2.2 finds no viable
upstream path for the two that the other two depend on.

---

## 4. Recommendation

**Adopt Option 1 as its own ticket: enable `dovi_split` in the component set,
chain `dovi_split=mode=bl_rpu` ahead of `dovi_rpu`, and shrink patch 0005 to
the RPU and configuration-record rewrite. Then submit that shrunken
`convert=p81` upstream as Option 2's single candidate. Keep 0001–0004 at
status quo.**

The reasoning is ADR 0002's, applied literally. ADR 0002 decided that "whenever
upstream FFmpeg grows a mechanism that does what a patch does, the preferred
path is to adopt upstream's mechanism, even when that costs a consumer-facing
contract change (a new bsf to chain, a new option name) and a coordinated
release." `dovi_split=mode=bl_rpu` is precisely such a mechanism for the
stripping half of 0005: it is upstream-maintained, FATE-covered, and walks
every NAL by construction rather than by this repo's own measurement of where
the enhancement layer sits. The contract cost is the exact cost ADR 0002 named
in advance and accepted. ADR 0002 also anticipated this specific filter by
name in its consequences.

Three things make the case stronger than "the ADR says so":

1. **The build cost is one object file** (§1.2). The usual objection to
   adopting an upstream mechanism — that it drags in machinery a decoder-less
   build does not want — does not apply here.
2. **It is a correctness fix, not only a simplification** (§1.4). The status
   quo can now emit an `hvcE` box describing a layer it just deleted. Doing
   nothing means either accepting that or growing 0005 a fourth hunk.
3. **It is what makes Option 2 viable.** ADR 0002's other clause is that "a
   patch that duplicates upstream logic drifts from it silently". Today 0005
   duplicates NAL-walking logic that upstream now has; after Option 1 it
   contains only what upstream lacks. That is both a smaller carrying cost and
   a far more submittable patch (§2.2) — the same work serves both options.

**Sequencing.** Option 1 lands here on the gate alone (ADR 0001): a
`scripts/config.sh` component change, a shrunken patch, and a simulator probe
assertion that `dovi_split` exists with its `mode` option — all machine-checked
with no media. The release is John's, made on the release notes (ADR 0003),
and it is a coordinated one: the tag that adds `dovi_split` to the artefacts
must exist before the consumer can chain it (§1.5). The
byte-equality check of §1.6 against the public FATE sample is the evidence to
gather **before** proposing the change, because if the two paths do not agree
byte for byte the whole option needs rethinking.

**Explicitly not recommended: submitting 0002/0003 upstream.** They change
behaviour for every FFmpeg user to fix a decoder-less build's problem, the
minimality rule is squarely against them (§2.2), and a rejected series spends
review goodwill that 0005's conversion needs. If they are ever to go upstream
it is as an opt-in demuxer option, which is a new-interface negotiation and its
own spec — not a follow-on to this work.

**Not urgent.** Nothing here is a reason to reopen the 9.0.1 pin. Option 1 is a
change with its own gate run, its own release notes and its own release, exactly
as ADR 0002 says patch retirement should be.

---

## Sources

**The pinned tarball**, as `bash scripts/fetch-ffmpeg.sh` places it under
`vendor/ffmpeg-9.0.1/` (SHA-256 verified against `scripts/config.sh`:
`cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635`). Files
cited as `ffmpeg-9.0.1/<path>:<line>`. `libavcodec/bsf/dovi_rpu.c`,
`libavcodec/hevc/parser.c`, `libavformat/matroskadec.c`, `libavformat/mov.c`
and `libavcodec/h2645_sei.{c,h}` in that tree are **patched** by 0001–0005;
line numbers for those five files are cited from the patches or from
`docs/research/ffmpeg-9-upgrade.md`, never as pristine upstream. Every other
file cited — `libavcodec/bsf/dovi_split.c`, `libavcodec/h2645_parse.c`,
`libavformat/movenc.c`, `libavformat/matroskaenc.c`, `libavcodec/defs.h`,
`libavcodec/Makefile`, `configure`, `Changelog`, `MAINTAINERS`,
`CONTRIBUTING.md`, `RELEASE_NOTES`, `doc/developer.texi`,
`doc/bitstream_filters.texi`, `tests/fate/hevc.mak`,
`tests/ref/fate/hevc-bsf-dovi-split-*` — is untouched by the patches.

* <https://code.ffmpeg.org/FFmpeg/FFmpeg/pulls/23122> — "avcodec/bsf: add
  dovi_split BSF", Kacper Michajłow, opened 2026-05-16, merged 2026-05-31;
  review discussion on NAL wrapper prefixes and output format.
* <https://patchwork.ffmpeg.org/project/ffmpeg/list/?q=dovi_split&state=*&archive=both>
  — the mailing-list mirror of that series; the only match for `dovi_split`.
* <https://patchwork.ffmpeg.org/project/ffmpeg/list/?q=hevc+parser+color&state=*&archive=both>
  and <https://patchwork.ffmpeg.org/project/ffmpeg/list/?q=coded_side_data+mastering&state=*&archive=both>
  — both return "No patches to display": no prior upstream attempt at
  parser-side colour export or at SEI-to-`coded_side_data` was found.
  UNVERIFIED beyond Patchwork, and the archive itself is the reason: the
  pipermail index at <https://ffmpeg.org/pipermail/ffmpeg-devel/> is browsable
  by month but offers **no search facility**, and its monthly listing ends at
  August 2025 — so it cannot be queried for prior art, and Patchwork is the
  only searchable view of the list. A web search restricted to `ffmpeg.org`,
  `patchwork.ffmpeg.org` and `code.ffmpeg.org` for the `matroskadec`/`mov`
  `need_parsing` exclusion returned nothing relevant either.
* <https://fate-suite.ffmpeg.org/mkv/> — directory listing showing
  `dovi-p7-hvce.mkv`, 657 KB, 2026-05-17.
* <https://github.com/quietvoid/dovi_tool> — the independent profile-7
  conversion oracle patch 0005's own comment was measured against.
* GitHub mirror of the FFmpeg git history, via the GraphQL blame API on
  `libavformat/matroskadec.c` at tag `n9.0.1` and the commits API — used only
  for the (inconclusive) archaeology of the HEVC `need_parsing` exclusion.
* This repo: `scripts/config.sh`, `scripts/patches/000{1..5}-*.patch`,
  `CLAUDE.md`, `CONTEXT.md`, `docs/agents/loop.md`,
  `docs/adr/0001-landing-proves-the-build-not-the-behaviour.md`,
  `docs/adr/0002-upstream-is-the-gold-standard.md`,
  `docs/adr/0003-release-notes-are-the-human-checkpoint.md`,
  `docs/research/ffmpeg-9-upgrade.md` (§1 release dates, §4 per-patch analysis
  and the `dovi_split` finding this document extends).
