#!/usr/bin/env bash
#
# release-notes.sh — draft the release notes for the next tag, on stdout.
#
# ADR 0003 makes the release notes the human checkpoint of the loop: John reads
# one document and says cut, instead of reading every issue. This assembles that
# document from the two places the truth already lives — the tracker (GitHub
# issues, via `gh`) and the git history — so nothing has to be remembered.
#
#   bash scripts/release-notes.sh                    # <newest v* tag>..main
#   bash scripts/release-notes.sh --range v8.1.2-3..v9.0.1-1
#
# READ-ONLY, always: it never commits, tags, pushes, comments or posts, and it
# reads no build artifacts. Cutting stays `scripts/release.sh`, and John's act.
# Output is plain Markdown — no colour, no progress — so a skill can pipe it.
#
# Sections, in this order (ADR 0003 + the breaking-changes convention in
# docs/agents/loop.md): header, Breaking changes, landed issues with their gate
# evidence, closed-but-not-landed, commits by prefix, open needs-hands, trailer.
# "Breaking changes" and "needs-hands" always print, saying "None" when empty,
# so a reader can tell none from forgotten.
#
# The decisions a reader will want explained:
#
#   * WHAT COUNTS AS LANDED. The loop lands by fast-forward, so there are no
#     PRs to read: an issue is landed when it carries a comment beginning
#     `Landed:` that cites a sha, and that sha is in the range. The range, not
#     the close date, is the authority — an issue can close after a tag while
#     its commit shipped before it. An issue closed in the window with no such
#     sha in the range is listed under "closed, not landed" rather than
#     dropped, because a silently missing ticket is the failure this document
#     exists to prevent. Open issues are scanned too: a ticket that ends in a
#     decision (a research doc) lands its commit and stays open for John, and
#     it belongs in the notes as much as any other.
#
#   * QUOTED, NOT PARAPHRASED. The gate evidence is the `Tests:` paragraph of
#     the newest `## Done` comment, and the `Deviations:` paragraph beside it,
#     copied through unaltered — a paragraph, not a line, because implementers
#     hard-wrap. Verbatim is the point: a summary of a gate result is not
#     evidence. A paragraph that ends mid-thought (the Done comment continued
#     into a code block) is left as it stands; the issue number is right there.
#
#   * COMMIT GROUPS. A commit's group is the first word of its subject prefix,
#     so `patch 0005:` groups under `patch` and `release v9.0.1-1:` under
#     `release`. The prefixes ADR 0003 names come first, in its order; any
#     other prefix keeps its own group after them, alphabetically, rather than
#     being swept into "other" — `review:` and `package-lgpl:` are real work
#     and a fixed list would hide them the day someone coins a prefix. Only a
#     subject with no prefix at all lands under "other". Nothing is dropped:
#     the group counts sum to the range count, which the header prints.
#
#   * NOT git-cliff. It was installed (Homebrew, 2.14.1) and tried against
#     this history: with a tuned `cliff.toml` it produces exactly the section
#     below, both as a fixed parser list and with `group = "$1"` for derived
#     groups. It was still not adopted — it is a global dependency and a Tera
#     template to learn, bought for one of six sections, while the other five
#     are `gh` and `jq` work it cannot do at all. The commit half is the six
#     lines of `git log` and `sed` below. GitHub's own generator was ruled out
#     upstream of this: it builds notes from PRs, and this repo has none.
#
#   * THE DRY RUN. The trailer quotes `scripts/release.sh --dry-run`, which is
#     what checks that a cut would work at all. It needs repository credentials
#     (it fetches tags), so from an unattended session it fails — and a failed
#     dry run must not cost John his notes. It is reported as not run, with its
#     exit code, and the draft goes on. The next tag in the trailer is computed
#     here the way release.sh computes it, from local tags.
#
# Requires: bash, git, gh (authenticated), jq. Exits non-zero with one line on
# stderr and nothing on stdout when gh is unauthenticated, when the repository
# has no `v*` tag, or when `--range` names something git cannot resolve.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

die() { echo "$*" >&2; exit 1; }

RANGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --range) [[ $# -ge 2 ]] || die "--range needs a value: --range <ref>..<ref>"; RANGE="$2"; shift 2 ;;
    --range=*) RANGE="${1#--range=}"; shift ;;
    *) die "unknown flag: $1" ;;
  esac
done

command -v gh  >/dev/null || die "gh not found — the tracker half of the notes needs it"
command -v jq  >/dev/null || die "jq not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run \`gh auth login\`"

# The range. Default: the newest tag reachable from main, up to main. `describe`
# rather than a version sort of `git tag -l`, so the previous tag is the one
# this history actually came through.
if [[ -n "$RANGE" ]]; then
  [[ "$RANGE" == *..* ]] || die "--range wants <ref>..<ref>, got: $RANGE"
  FROM="${RANGE%%..*}"
  TO="${RANGE##*..}"
  [[ -n "$FROM" && -n "$TO" ]] || die "--range wants <ref>..<ref>, got: $RANGE"
  git rev-parse --verify -q "${FROM}^{commit}" >/dev/null || die "no such commit or tag: ${FROM}"
  git rev-parse --verify -q "${TO}^{commit}"   >/dev/null || die "no such commit or tag: ${TO}"
else
  TO=main
  git rev-parse --verify -q "main^{commit}" >/dev/null || TO=HEAD
  FROM="$(git describe --tags --abbrev=0 --match 'v*' "$TO" 2>/dev/null || true)"
  [[ -n "$FROM" ]] || die "no v* tag reachable from ${TO} — nothing to draft notes against"
fi
FROM_SHA="$(git rev-parse "${FROM}^{commit}")"
TO_SHA="$(git rev-parse "${TO}^{commit}")"
COUNT="$(git rev-list --count "${FROM_SHA}..${TO_SHA}")"

# The tag a cut would take next: v{FFMPEG_VERSION}-{N}, N one past the highest
# existing tag for this version — release.sh's own arithmetic, minus its
# `git fetch --tags` (this script stays credential-free; the dry run below is
# what confirms the number against the remote).
VER="$(sed -n 's/^FFMPEG_VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' scripts/config.sh | head -1)"
[[ -n "$VER" ]] || die "could not read FFMPEG_VERSION from scripts/config.sh"
last="$(git tag -l "v${VER}-*" | sed -n "s/^v${VER}-\([0-9]*\)$/\1/p" | sort -n | tail -1)"
NEXT_TAG="v${VER}-$(( ${last:-0} + 1 ))"

# Every issue, with its comments, in one call.
ISSUES="$(mktemp)"; trap 'rm -f "$ISSUES"' EXIT
gh issue list --state all --limit 200 \
  --json number,title,state,labels,closedAt,body,comments > "$ISSUES"

# jq helpers: a "paragraph" is the run of non-blank lines starting at the first
# line with the given prefix. Used for the Done evidence and for the
# `## Consumer-facing change` section (which runs to the next heading instead).
JQ_LIB='
def lines: split("\n") | map(if test("^[[:space:]]*$") then "" else . end);
def para($prefix):
  lines as $l
  | ([$l | to_entries[] | select(.value | startswith($prefix)) | .key] | first) as $i
  | if $i == null then "" else
      ($l[$i:]) as $rest
      | (($rest | index("")) // ($rest | length)) as $e
      | ($rest[0:$e] | join("\n"))
    end;
def section($heading):
  lines as $l
  | ([$l | to_entries[] | select(.value | startswith($heading)) | .key] | first) as $i
  | if $i == null then "" else
      ($l[$i+1:]) as $rest
      | ([$rest | to_entries[] | select(.value | startswith("## ")) | .key] | first) as $e
      | ($rest[0:(($e) // ($rest | length))] | join("\n") | sub("^\n+"; "") | sub("\n+$"; ""))
    end;
def done_comment:
  ([.comments[] | select(.body | startswith("## Done"))] | last | .body) // "";
def landing:
  ([.comments[] | select(.body | test("^Landed:"; "m"))] | last | .body) // "";
def landing_sha:
  (landing | capture("^Landed:[^\n]*?\\b(?<sha>[0-9a-f]{7,40})\\b"; "m") | .sha) // "";
'

# Which issues landed inside the range: the landing sha must be an ancestor of
# the range end and not of its start.
in_range() {
  local s
  s="$(git rev-parse --verify -q "${1}^{commit}")" || return 1
  git merge-base --is-ancestor "$s" "$TO_SHA" || return 1
  ! git merge-base --is-ancestor "$s" "$FROM_SHA"
}

LANDED=""       # "number sha" per line
NOT_LANDED=""   # "number reason" per line, closed in the window without a landed sha
# In GitHub's own format and timezone: closedAt is UTC with a `Z`, and these
# two dates are compared as strings, so a local offset here would compare wrong.
FROM_DATE="$(TZ=UTC git log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ "$FROM_SHA")"
# Unit separator, not tab: tab counts as IFS whitespace even when IFS is set to
# tab alone, so `read` would fold the two delimiters around an empty sha into
# one and shift the closed date into $sha.
while IFS=$'\x1f' read -r num sha closed; do
  [[ -n "$num" ]] || continue
  if [[ -n "$sha" ]] && in_range "$sha"; then
    LANDED="${LANDED}${num} ${sha}
"
  elif [[ -n "$closed" && "$closed" > "$FROM_DATE" ]]; then
    if [[ -n "$sha" ]]; then
      NOT_LANDED="${NOT_LANDED}${num} landed ${sha}, outside this range
"
    else
      NOT_LANDED="${NOT_LANDED}${num} no landing comment citing a sha
"
    fi
  fi
done < <(jq -r "${JQ_LIB}"'
  .[] | [(.number|tostring), landing_sha, (.closedAt // "")] | join("\u001f")' "$ISSUES")

issue_field() { jq -r "${JQ_LIB}"'
  .[] | select(.number == '"$1"') | '"$2" "$ISSUES"; }

# --- the document -----------------------------------------------------------
# Assembled whole and printed at the end, so a failure anywhere leaves stdout
# empty (the two failure modes above promise that).
out=""
add() { out="${out}${1}
"; }

add "# Release notes — ${NEXT_TAG} (draft)"
add ""
add "Range: \`${FROM}..${TO}\` — ${COUNT} commit$([[ "$COUNT" == 1 ]] || echo s), \`$(git rev-parse --short "$FROM_SHA")\`..\`$(git rev-parse --short "$TO_SHA")\`."
add "Pinned FFmpeg: **${VER}**. Consumers pin \`.exact\` — \`${NEXT_TAG#v}\` once this is cut."
add ""
if [[ "$COUNT" -eq 0 ]]; then
  add "Nothing has landed since \`${FROM}\`. There is no release to cut."
  add ""
fi
add "Drafted $(date -u '+%Y-%m-%d %H:%M UTC') from the tracker and git; nothing here has been posted, tagged or pushed."

# --- breaking changes -------------------------------------------------------
add ""
add "## Breaking changes"
add ""
breaking=""
while read -r num sha; do
  [[ -n "$num" ]] || continue
  labels="$(issue_field "$num" '[.labels[].name] | join(",")')"
  case ",${labels}," in *,breaking,*) ;; *) continue ;; esac
  title="$(issue_field "$num" '.title')"
  cfc="$(issue_field "$num" '.body | section("## Consumer-facing change")')"
  breaking="yes"
  add "### #${num} — ${title}"
  add ""
  if [[ -n "$cfc" ]]; then
    add "$cfc"
  else
    add "Labelled \`breaking\` with no \`## Consumer-facing change\` section in its body — read the issue."
  fi
  add ""
done <<EOF
$LANDED
EOF
if [[ -z "$breaking" ]]; then
  add "None recorded: no issue landed in this range carries the \`breaking\` label."
  add ""
  add "_This section is only as good as the labelling — it reports what the tracker"
  add "says, not what a reader of the diff would conclude._"
  add ""
fi

# --- landed -----------------------------------------------------------------
add "## Landed since \`${FROM}\`"
add ""
if [[ -z "${LANDED// /}" ]]; then
  add "Nothing — no issue in the tracker carries a landing sha inside this range."
  add ""
fi
while read -r num sha; do
  [[ -n "$num" ]] || continue
  title="$(issue_field "$num" '.title')"
  state="$(issue_field "$num" '.state')"
  labels="$(issue_field "$num" '[.labels[].name] | join(", ")')"
  tests="$(issue_field "$num" 'done_comment | para("Tests:")')"
  devs="$(issue_field "$num" 'done_comment | para("Deviations:")')"
  add "### #${num} — ${title}"
  add ""
  add "Landed \`${sha}\`$( [[ "$state" == "OPEN" ]] && echo ", still open (it ends in a decision that is John's)" ). Labels: ${labels:-none}."
  add ""
  if [[ -n "$tests" ]]; then add "$tests"; else add "_No \`## Done\` comment with a \`Tests:\` line — gate evidence is in the landing comment on #${num}._"; fi
  add ""
  if [[ -n "$devs" ]]; then add "$devs"; else add "Deviations: none recorded."; fi
  add ""
done <<EOF
$LANDED
EOF

# --- closed, not landed -----------------------------------------------------
if [[ -n "${NOT_LANDED// /}" ]]; then
  add "## Closed since \`${FROM}\`, not landed in this range"
  add ""
  while read -r num rest; do
    [[ -n "$num" ]] || continue
    title="$(issue_field "$num" '.title')"
    add "- **#${num}** ${title} — ${rest}"
  done <<EOF
$NOT_LANDED
EOF
  add ""
fi

# --- commits ----------------------------------------------------------------
add "## Commits (${COUNT})"
add ""
COMMITS="$(mktemp)"; trap 'rm -f "$ISSUES" "$COMMITS"' EXIT
git log --reverse --format='%h	%s' "${FROM_SHA}..${TO_SHA}" \
  | sed -E 's/^([^	]*)	([a-z0-9][a-z0-9._-]*)( [a-z0-9._-]+)?:[[:space:]]/\2	\1	\2\3: /' \
  | awk -F'\t' 'NF==3 {print; next} {print "other\t" $1 "\t" $2}' > "$COMMITS"
# ^ three columns: group, sha, subject. The sed reprints the prefix it matched
#   so no subject is altered; a line it does not match keeps two columns and awk
#   files it under "other".
KNOWN="bump smoke docs loop research chore"
ordered=""
for g in $KNOWN; do
  cut -f1 "$COMMITS" | grep -qx "$g" && ordered="${ordered}${g}
"
done
for g in $(cut -f1 "$COMMITS" | sort -u | grep -vx other || true); do
  case " $KNOWN " in *" $g "*) ;; *) ordered="${ordered}${g}
" ;; esac
done
cut -f1 "$COMMITS" | grep -qx other && ordered="${ordered}other
"
while IFS= read -r g; do
  [[ -n "$g" ]] || continue
  add "### ${g}"
  add ""
  while IFS="	" read -r grp sha subject; do
    [[ "$grp" == "$g" ]] || continue
    add "- \`${sha}\` ${subject}"
  done < "$COMMITS"
  add ""
done <<EOF
$ordered
EOF

# --- needs-hands ------------------------------------------------------------
add "## Open needs-hands"
add ""
hands="$(jq -r '
  .[] | select(.state == "OPEN")
      | select([.labels[].name] | index("needs-hands"))
      | [(.number|tostring), .title,
         ((.body | split("\n") | map(select(startswith("Reason:") or startswith("Why hands:"))) | first)
          // "reason: unstated")] | join("\u001f")' "$ISSUES")"
if [[ -z "$hands" ]]; then
  add "None."
else
  while IFS=$'\x1f' read -r num title reason; do
    [[ -n "$num" ]] || continue
    add "- **#${num}** ${title} — ${reason}"
  done <<EOF
$hands
EOF
fi
add ""

# --- trailer ----------------------------------------------------------------
add "## What this release triggers"
add ""
add "- **Confirmation** (ADR 0003): the consumer's pin-bump ticket, in its own"
add "  repository, pins \`${NEXT_TAG#v}\` and runs its suite against the tag. Green is"
add "  the confirmation; red burns this \`N\` and reopens the work here, because the"
add "  tag is immutable and is never re-cut."
add "- The \`v*\` GitHub Action: a from-scratch reproducibility build that checks the"
add "  released bytes against the committed checksums. It never publishes."
add ""
add "## To cut it"
add ""
add "From a clean checkout of \`${TO}\` with fresh \`./build.sh --smoke\` artifacts —"
add "the local build is the bytes that ship:"
add ""
add '```'
add "bash scripts/release.sh          # tag ${NEXT_TAG}"
add '```'
add ""
dry="$(bash scripts/release.sh --dry-run 2>&1)" && dry_rc=0 || dry_rc=$?
if [[ "$dry_rc" -eq 0 ]]; then
  add "\`bash scripts/release.sh --dry-run\` agrees:"
  add ""
  add '```'
  add "$dry"
  add '```'
else
  add "dry-run: not run (exit ${dry_rc} — run \`bash scripts/release.sh --dry-run\` from an interactive shell)"
fi

printf '%s' "$out"
