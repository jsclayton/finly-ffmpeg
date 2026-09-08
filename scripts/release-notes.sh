#!/usr/bin/env bash
#
# release-notes.sh — draft the release notes for the next tag, on stdout.
#
# ADR 0003 makes the release notes the human checkpoint of the loop: John reads
# one short document and says cut, instead of reading every issue. This
# assembles that document from the tracker (GitHub issues, via `gh`) and the
# git history, so nothing has to be remembered.
#
#   bash scripts/release-notes.sh                    # <newest v* tag>..main
#   bash scripts/release-notes.sh --range v8.1.2-3..v9.0.1-1
#
# READ-ONLY: it writes nothing to the repository and nothing to the tracker —
# no commit, tag, push, comment, label or release. Cutting stays
# `scripts/release.sh`, and John's act. Output is plain Markdown — no colour,
# no progress — so a skill can pipe it.
#
# The repo is public (`docs/agents/loop.md`, Visibility): this document is
# world-readable, and its quoted parts come straight out of GitHub issues that
# already are. The fixed strings here keep the repo's generic rule — the
# consumer is "the consumer", its repository is never named.
#
# The document is SHORT, on purpose (John, 2026-09-08, on the first draft):
# a header, the breaking changes, and the list of what landed. No commit log,
# no quoted gate evidence, no needs-hands, no trailer. The evidence lives on
# each ticket's `## Done` and landing comments, one click away; the notes are
# what a reader needs to decide the cut, not the audit trail.
#
# The decisions a reader will want explained:
#
#   * WHAT COUNTS AS LANDED. The loop lands by fast-forward, so there are no
#     PRs to read: an issue is landed when it carries a comment beginning
#     `Landed:` that cites a sha, and that sha is in the range. The range, not
#     the close date, is the authority — an issue can close after a tag while
#     its commit shipped before it. Open issues are scanned too: a ticket that
#     ends in a decision (a research doc) lands its commit and stays open for
#     John, and it belongs in the notes as much as any other.
#
#   * BREAKING CHANGES ARE ONLY AS GOOD AS THE LABELLING. That section is built
#     from issues labelled `breaking`, quoting each one's `## Consumer-facing
#     change` section, so it reports the tracker and not the diff, and it says
#     so when it is empty. Label the ticket, or the notes cannot know.
#
#   * THE NEXT TAG is v{FFMPEG_VERSION}-{N}, N one past the highest existing
#     tag for this version — release.sh's own arithmetic from local tags.
#     Copied rather than sourced: `config.sh` sets up build paths this script
#     has no use for, and release.sh reads the pin the same way, by sed.
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

VER="$(sed -n 's/^FFMPEG_VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' scripts/config.sh | head -1)"
[[ -n "$VER" ]] || die "could not read FFMPEG_VERSION from scripts/config.sh"
last="$(git tag -l "v${VER}-*" | sed -n "s/^v${VER}-\([0-9]*\)$/\1/p" | sort -n | tail -1)"
NEXT_TAG="v${VER}-$(( ${last:-0} + 1 ))"

# Every issue, with its comments, in one call.
ISSUES="$(mktemp)"
trap 'rm -f "$ISSUES"' EXIT
GH_LIMIT=500
gh issue list --state all --limit "$GH_LIMIT" \
  --json number,title,state,labels,body,comments > "$ISSUES"
# A silently truncated page would drop landed tickets out of the notes, which is
# the one failure this document cannot have.
[[ "$(jq 'length' "$ISSUES")" -lt "$GH_LIMIT" ]] \
  || die "more than ${GH_LIMIT} issues — raise GH_LIMIT, the tracker page is truncated"

# jq helpers: `section` is the text under a heading up to the next `## `
# heading, used for `## Consumer-facing change`.
JQ_LIB='
def lines: split("\n") | map(if test("^[[:space:]]*$") then "" else . end);
def section($heading):
  lines as $l
  | ([$l | to_entries[] | select(.value | startswith($heading)) | .key] | first) as $i
  | if $i == null then "" else
      ($l[$i+1:]) as $rest
      | ([$rest | to_entries[] | select(.value | startswith("## ")) | .key] | first) as $e
      | ($rest[0:(($e) // ($rest | length))] | join("\n") | sub("^\n+"; "") | sub("\n+$"; ""))
    end;
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
while IFS=$'\x1f' read -r num sha; do
  [[ -n "$num" && -n "$sha" ]] || continue
  if in_range "$sha"; then
    LANDED="${LANDED}${num} ${sha}
"
  fi
done < <(jq -r "${JQ_LIB}"'
  .[] | [(.number|tostring), landing_sha] | join("\u001f")' "$ISSUES")

issue_field() { jq -r "${JQ_LIB}"'
  .[] | select(.number == '"$1"') | '"$2" "$ISSUES"; }

# --- the document -----------------------------------------------------------
# Assembled whole and printed at the end, so a failure anywhere leaves stdout
# empty (the failure modes above promise that).
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
  add "_Read from the tracker, not the diff: an unlabelled ticket cannot appear here._"
  add ""
fi

# --- landed -----------------------------------------------------------------
add "## Landed since \`${FROM}\`"
add ""
if [[ -z "${LANDED// /}" ]]; then
  add "Nothing — no issue in the tracker carries a landing sha inside this range."
fi
while read -r num sha; do
  [[ -n "$num" ]] || continue
  title="$(issue_field "$num" '.title')"
  state="$(issue_field "$num" '.state')"
  add "- **#${num}** ${title}$( [[ "$state" == "OPEN" ]] && echo " — still open: it ends in a decision that is John's" )"
done <<EOF
$LANDED
EOF

printf '%s' "$out"
