#!/usr/bin/env bash
# pr-autopilot v0.5 — PreToolUse hard gate: block writes outside specs/ until
# /pr-autopilot:approve-spec has flipped the claim file to `implementing` (or later).
#
# Receives Claude Code tool-call JSON on stdin (tool_name, tool_input, cwd).
# Contract (Claude Code PreToolUse): to BLOCK, print
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
#    "permissionDecisionReason":"..."}}
# on stdout and exit 0. If jq is unavailable the fallback is exit 2 + reason on stderr.
# Exit 0 with no output = allow. NOTE: exit 1 does NOT block in Claude Code (it is a
# non-blocking error); earlier versions of this script used exit 1 and never blocked.
#
# Gated tools (settings matcher: Write|Edit|MultiEdit|NotebookEdit|Bash):
#   - Write / Edit / MultiEdit → .tool_input.file_path
#   - NotebookEdit             → .tool_input.notebook_path
#   - Bash                     → write targets parsed heuristically from .tool_input.command
#
# Policy (per spec §"Hook policy summary"):
#   - Honors ~/.pr-autopilot/paused sentinel (skips gate if paused).
#   - Honors ~/.pr-autopilot/allowed-repos allowlist (case-insensitive match).
#   - Gate-lifted states: implementing, pr_opened, pr_review_requested, pr_revising, merged.
#   - Pre-approval states: spec_drafting, spec_review_requested, spec_revising, spec_review_complete.
#   - Allowed paths during pre-approval: specs/* and .claude/assignment-claims/*.
#   - Integrity check: a claim file claiming a gate-lifted subStatus but with approvedAt=null
#     is treated as TAMPERED and blocks all writes.
#   - Approval fields (approvedAt, approvedBy, approvalContext) in claim files are never
#     writable by the agent, in any state. Only skills/approve-spec/scripts/approve-claim.sh,
#     run by the user in their own terminal (it reads a typed confirmation from /dev/tty),
#     sets them. Concretely the hook denies:
#       * Write/Edit/MultiEdit on a claim file whose resulting JSON changes any approval
#         field, flips subStatus to a gate-lifted state while approvedAt is null, or is not
#         valid JSON;
#       * any Bash command that writes into .claude/assignment-claims/ (claim updates must
#         go through Edit/Write so the resulting content can be checked);
#       * any Bash command that mentions an approval field together with a write-ish
#         token (redirect, tee, -i, mv, cp, an interpreter);
#       * any Bash command that mentions approve-claim.sh.
#
# WHAT REMAINS BYPASSABLE (this is a guard rail against accidental or casual writes, not a
# security boundary — the agent has a shell):
#   - Bash writes the parser does not recognise: interpreters (python3 -c, node -e, perl
#     without -i, ruby), dd of=, install, ln, touch, truncate, patch / git apply /
#     git checkout -- <file> / git restore, eval, scripts written to /tmp and then run,
#     targets built from variables or command substitution ($X, `...`), quoted targets
#     containing spaces, and relative targets after a `cd` inside the same command
#     (relative paths are resolved against the hook's cwd).
#   - Deleting or moving the claim file away (rm, git rm, git worktree remove): with no
#     claim file the gate is off by design.
#   - Creating ~/.pr-autopilot/paused or editing ~/.pr-autopilot/allowed-repos.
#   - Running approve-claim.sh under a pseudo-terminal the agent controls (e.g. `script`).
#   - Write/Edit to absolute paths outside the repo are still blocked pre-approval (as in
#     v0.5.0), but Bash writes outside the repo (e.g. /tmp) are allowed.

set -euo pipefail

LIFTED_STATES="implementing pr_opened pr_review_requested pr_revising merged"
APPROVAL_FIELDS_RE='approvedAt|approvedBy|approvalContext'

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

# deny <reason> — emit the blocking decision and exit.
deny() {
  local reason="[pr-autopilot/spec-gate] BLOCKED: $1"
  if [ "$HAVE_JQ" = "1" ]; then
    jq -cn --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
  printf '%s\n' "$reason" >&2
  exit 2
}

# 1. Honor pause sentinel.
[ -f "$HOME/.pr-autopilot/paused" ] && exit 0

# 2. Parse tool call from stdin.
INPUT=$(cat)
if [ "$HAVE_JQ" = "1" ]; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
  FILE_TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || echo "")
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
else
  TOOL=""; CWD=""; FILE_TARGET=""; COMMAND=""
fi
{ [ -n "$CWD" ] && [ -d "$CWD" ]; } || CWD=$(pwd)

# 3. Honor allowlist (P1-5 v2.1 fix: case-insensitive match, consistent with /allow).
# Uses awk because `grep -qiFx` core-dumps on some Git Bash builds when matching
# UTF-8 lines — observed by hooks/tests/test-spec-gate.sh T1/T5/T9.
# Repo names may contain dots (e.g. owner/my.repo): strip `.git` first, then take the
# last two path segments.
REPO=$(git -C "$CWD" remote get-url origin 2>/dev/null | sed -E 's|\.git/*$||; s|/*$||; s|.*[:/]([^/:]+/[^/:]+)$|\1|' || echo "")
ALLOWLIST="$HOME/.pr-autopilot/allowed-repos"
if [ -f "$ALLOWLIST" ] && [ -n "$REPO" ]; then
  ALLOW_MATCH=$(awk -v r="$REPO" 'tolower($0) == tolower(r) {print "1"; exit}' "$ALLOWLIST" 2>/dev/null)
  if [ "$ALLOW_MATCH" != "1" ]; then
    exit 0  # not opted in, no gate
  fi
fi

# 4. Repo root + claim directory. Claim files live at <repo-root>/.claude/assignment-claims/
# by convention (spec §"Atomic claim — git as primitive"); no need to walk up the
# filesystem. This avoids two failure modes uncovered by hooks/tests/test-spec-gate.sh
# T10: (a) reading a sibling project's claim file, (b) string-mismatch between
# `pwd` and `git rev-parse --show-toplevel` on Windows (UNIX `/tmp/...` vs `C:/Users/...`).
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
[ -z "$REPO_ROOT" ] && exit 0
CLAIM_DIR="$REPO_ROOT/.claude/assignment-claims"
[ -d "$CLAIM_DIR" ] || exit 0   # outside the pre-PR lifecycle

if [ "$HAVE_JQ" = "0" ]; then
  deny "jq is required by enforce-spec-gate.sh in a repo with claim files (install: apt install jq / brew install jq)."
fi

# Infer the tool when tool_name is missing (older harnesses, unit tests).
if [ -z "$TOOL" ]; then
  if [ -n "$COMMAND" ]; then TOOL="Bash"
  elif printf '%s' "$INPUT" | jq -e '.tool_input.notebook_path' >/dev/null 2>&1; then TOOL="NotebookEdit"
  elif [ -n "$FILE_TARGET" ]; then TOOL="Write"
  fi
fi

# ─── Path helpers ──────────────────────────────────────────────────────────

# Normalise Windows paths so the `case` matches work regardless of OS
# (Claude Code on Windows may pass `C:\repo\specs\foo.md`). P1-5 from v0.5 PR review.
to_slashes() { printf '%s' "$1" | tr '\\' '/'; }

# Lexically resolve a path against CWD (no filesystem access; handles . and ..).
abs_path() {
  local p="$1" out="" seg
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    /*|[A-Za-z]:/*) : ;;
    *) p="$CWD/$p" ;;
  esac
  local IFS='/'
  for seg in $p; do
    case "$seg" in
      ''|.) continue ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  printf '%s' "${out:-/}"
}

# Prints the repo-relative path of $1 if it is inside REPO_ROOT, else nothing.
repo_rel() {
  local a; a=$(abs_path "$1")
  case "$a" in
    "$REPO_ROOT") printf '.' ;;
    "$REPO_ROOT"/*) printf '%s' "${a#"$REPO_ROOT"/}" ;;
  esac
}

is_claim_path() {  # $1 = path as given by the tool (relative or absolute)
  case "$1" in
    .claude/assignment-claims/*|*/.claude/assignment-claims/*) return 0 ;;
  esac
  return 1
}

# ─── Bash write-target parser (heuristic; see "WHAT REMAINS BYPASSABLE") ────

# Drop here-doc bodies (their content is data, not commands).
strip_heredocs() {
  awk '
    inhd { t=$0; if (strip) sub(/^\t+/, "", t); if (t == delim) inhd=0; next }
    {
      print
      line=$0
      while (match(line, /<<-?[ \t]*["'\'']?[A-Za-z_][A-Za-z0-9_]*/)) {
        tok=substr(line, RSTART, RLENGTH)
        pre=(RSTART > 1) ? substr(line, RSTART-1, 1) : ""
        line=substr(line, RSTART+RLENGTH)
        if (pre == "<") continue            # <<< here-string
        strip=(tok ~ /^<<-/)
        sub(/^<<-?[ \t]*["'\'']?/, "", tok)
        delim=tok; inhd=1
      }
    }'
}

# Inside quotes, replace shell operator characters with "_" and drop the quote
# characters, so `echo "a > b"` is not mistaken for a redirect.
neutralise_quotes() {
  awk '
    BEGIN { q="" }
    {
      out=""
      n=length($0)
      for (i=1; i<=n; i++) {
        c=substr($0, i, 1)
        if (q == "" && c == "\\") { out=out "_"; i++; continue }
        if (q == "" && (c == "\"" || c == "'\''")) { q=c; continue }
        if (q != "" && c == q) { q=""; continue }
        if (q != "" && index("><|;&(){}", c)) { out=out "_"; continue }
        out=out c
      }
      print out
    }'
}

# Prints one write target per line.
bash_write_targets() {
  local cmd="$1" clean seg w first n inplace tdir
  clean=$(printf '%s\n' "$cmd" | strip_heredocs | neutralise_quotes)
  # fd duplication / closing (2>&1, >&2, 1>&-) is not a file write
  clean=$(printf '%s\n' "$clean" | sed -E 's/[0-9]*>&[0-9-]+//g; s/&>/>/g; s/>\|/>/g')

  # Redirect targets: > file, >> file, 2> file
  printf '%s\n' "$clean" | grep -oE '>>?[[:space:]]*[^[:space:];&|()<>]+' | sed -E 's/^>>?[[:space:]]*//' || true

  # Command-based writes, per pipeline/list segment.
  set -f
  while IFS= read -r seg; do
    # shellcheck disable=SC2086
    set -- $seg
    # skip env assignments and simple wrappers
    while [ $# -gt 0 ]; do
      case "$1" in
        *=*|sudo|command|env|nohup|time|xargs|then|do|else|'!') shift ;;
        *) break ;;
      esac
    done
    [ $# -gt 0 ] || continue
    first="${1##*/}"; shift
    case "$first" in
      tee)
        for w in "$@"; do case "$w" in -*) ;; *) printf '%s\n' "$w" ;; esac; done
        ;;
      sed|gsed|perl)
        # Only the last argument is treated as the edited file.
        inplace=0
        for w in "$@"; do case "$w" in -i*|--in-place*|-pi*|-ni*) inplace=1 ;; esac; done
        if [ "$inplace" = "1" ] && [ $# -gt 0 ]; then
          n=$#; eval "w=\${$n}"; printf '%s\n' "$w"
        fi
        ;;
      cp|mv)
        n=$#; tdir=""
        for w in "$@"; do
          if [ "$tdir" = "next" ]; then tdir="$w"; fi
          case "$w" in -t) tdir="next" ;; --target-directory=*) tdir="${w#*=}" ;; esac
        done
        if [ -n "$tdir" ] && [ "$tdir" != "next" ]; then printf '%s\n' "$tdir"
        elif [ "$n" -ge 2 ]; then eval "w=\${$n}"; printf '%s\n' "$w"
        fi
        ;;
    esac
  done < <(printf '%s\n' "$clean" | awk '{ gsub(/&&|\|\||[;|(){}&]/, "\n"); print }')
  set +f
}

# ─── 5. Claim-file protections (all states) ────────────────────────────────

# approval_fields <json-text> → compact JSON array of the approval fields + subStatus,
# or "INVALID" when the text is not a JSON object.
approval_fields() {
  printf '%s' "$1" | jq -c 'if type == "object" then [.approvedAt, .approvedBy, .approvalContext, .subStatus] else error("not an object") end' 2>/dev/null || echo "INVALID"
}

check_claim_write() {  # $1 = target path as given; uses INPUT
  local target="$1" abs cur new before after old_s new_s all k count
  abs=$(abs_path "$target")
  cur=""
  [ -f "$abs" ] && cur=$(cat "$abs")
  case "$TOOL" in
    Write)
      new=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""')
      ;;
    Edit)
      old_s=$(printf '%s' "$INPUT" | jq -r '.tool_input.old_string // ""')
      new_s=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""')
      all=$(printf '%s' "$INPUT" | jq -r '.tool_input.replace_all // false')
      if [ "$all" = "true" ]; then new="${cur//"$old_s"/"$new_s"}"; else new="${cur/"$old_s"/"$new_s"}"; fi
      ;;
    MultiEdit)
      new="$cur"
      count=$(printf '%s' "$INPUT" | jq -r '.tool_input.edits | length' 2>/dev/null || echo 0)
      for ((k=0; k<count; k++)); do
        old_s=$(printf '%s' "$INPUT" | jq -r --argjson k "$k" '.tool_input.edits[$k].old_string // ""')
        new_s=$(printf '%s' "$INPUT" | jq -r --argjson k "$k" '.tool_input.edits[$k].new_string // ""')
        all=$(printf '%s' "$INPUT" | jq -r --argjson k "$k" '.tool_input.edits[$k].replace_all // false')
        if [ "$all" = "true" ]; then new="${new//"$old_s"/"$new_s"}"; else new="${new/"$old_s"/"$new_s"}"; fi
      done
      ;;
    *)
      deny "claim files under .claude/assignment-claims/ may only be changed with the Edit or Write tool."
      ;;
  esac

  after=$(approval_fields "$new")
  [ "$after" = "INVALID" ] && deny "the new content of $target is not a valid JSON object; claim files must stay valid JSON."
  before='[null,null,null,null]'
  if [ -n "$cur" ]; then before=$(approval_fields "$cur"); fi
  [ "$before" = "INVALID" ] && before='[null,null,null,null]'

  if [ "$(printf '%s' "$before" | jq -c '.[0:3]')" != "$(printf '%s' "$after" | jq -c '.[0:3]')" ]; then
    deny "approvedAt / approvedBy / approvalContext in $target can only be set by the user via /pr-autopilot:approve-spec (approve-claim.sh run in the user's own terminal). Do not edit them."
  fi
  local new_sub new_appr
  new_sub=$(printf '%s' "$after" | jq -r '.[3] // "none"')
  new_appr=$(printf '%s' "$after" | jq -r '.[0] // "null"')
  case " $LIFTED_STATES " in
    *" $new_sub "*)
      if [ "$new_appr" = "null" ]; then
        deny "subStatus=$new_sub requires approvedAt, which only /pr-autopilot:approve-spec can set. Ask the user to run /pr-autopilot:approve-spec."
      fi
      ;;
  esac
  return 0
}

BASH_TARGETS=""
case "$TOOL" in
  Bash)
    [ -z "$COMMAND" ] && exit 0
    if printf '%s' "$COMMAND" | grep -q 'approve-claim\.sh'; then
      deny "approve-claim.sh is user-only: the user runs it in their own terminal (see /pr-autopilot:approve-spec)."
    fi
    if printf '%s' "$COMMAND" | grep -qE "$APPROVAL_FIELDS_RE"; then
      # strip harmless redirects before looking for write-ish tokens
      STRIPPED=$(printf '%s' "$COMMAND" | sed -E 's/[0-9]*>&[0-9-]+//g; s#[0-9]*>>?[[:space:]]*/dev/null##g')
      if printf '%s' "$STRIPPED" | grep -qE '>|(^|[^[:alnum:]_-])(tee|mv|cp|sponge|python[0-9.]*|node|perl|ruby|dd)([^[:alnum:]_-]|$)|[[:space:]](-i|--in-place)'; then
        deny "Bash commands must not write approvedAt / approvedBy / approvalContext; only /pr-autopilot:approve-spec sets them."
      fi
    fi
    BASH_TARGETS=$(bash_write_targets "$COMMAND")
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      t=$(to_slashes "$t")
      rel=$(repo_rel "$t")
      case "$rel" in
        .claude/assignment-claims|.claude/assignment-claims/*)
          deny "Bash writes into .claude/assignment-claims/ are not allowed (target: $t). Update claim files with the Edit or Write tool so the gate can verify the approval fields."
          ;;
      esac
    done <<< "$BASH_TARGETS"
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    [ -z "$FILE_TARGET" ] && exit 0
    FILE_TARGET=$(to_slashes "$FILE_TARGET")
    if is_claim_path "$FILE_TARGET"; then
      check_claim_write "$FILE_TARGET"
    fi
    ;;
  *)
    exit 0  # not a gated tool
    ;;
esac

# ─── 6. Find the claim file for this branch ────────────────────────────────
# Prefer the claim whose .branch matches the current branch; fall back to the first one.
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
CLAIM=""
FIRST=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -z "$FIRST" ] && FIRST="$f"
  if [ -n "$BRANCH" ] && [ "$(jq -r '.branch // empty' "$f" 2>/dev/null || true)" = "$BRANCH" ]; then
    CLAIM="$f"; break
  fi
done < <(find "$CLAIM_DIR" -maxdepth 1 -name "*.json" 2>/dev/null | sort || true)
[ -z "$CLAIM" ] && CLAIM="$FIRST"

# No claim found → outside the pre-PR lifecycle, allow.
[ -z "$CLAIM" ] && exit 0

# 7. Read claim file state.
SUB_STATUS=$(jq -r '.subStatus // "none"' "$CLAIM" 2>/dev/null || echo "none")
APPROVED_AT=$(jq -r '.approvedAt // "null"' "$CLAIM" 2>/dev/null || echo "null")

# 8. Gate logic.
case " $LIFTED_STATES " in
  *" $SUB_STATUS "*)
    # Gate is lifted — but only if approvedAt is set (P0-2 v2.1 integrity check).
    if [ "$APPROVED_AT" = "null" ] || [ -z "$APPROVED_AT" ]; then
      deny "subStatus=$SUB_STATUS but approvedAt is null — the claim file appears tampered. /pr-autopilot:approve-spec must set approvedAt + approvedBy. If this is intentional (e.g. recovering from a corrupted state), use /pr-autopilot:unassign first."
    fi
    exit 0
    ;;
esac

# 9. Pre-approval states: allow only writes to specs/ + claim files.
PRE_APPROVAL_MSG="spec not approved (subStatus=$SUB_STATUS). Allowed paths during pre-approval: specs/*, .claude/assignment-claims/*. Workflow: 1) finish the spec at specs/<date>-<id>.md; 2) run /pr-autopilot:review-spec; 3) after 0 P0 findings, ask the user to run /pr-autopilot:approve-spec; 4) sub-status flips to 'implementing' and this gate lifts."

if [ "$TOOL" = "Bash" ]; then
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    t=$(to_slashes "$t")
    case "$t" in /dev/*|-|*'$'*|*'`'*) continue ;; esac   # devices, stdin, unresolvable
    rel=$(repo_rel "$t")
    [ -z "$rel" ] && continue                              # outside the repo (e.g. /tmp)
    case "$rel" in
      specs|specs/*|*/specs/*|.claude/assignment-claims/*) continue ;;
    esac
    deny "$PRE_APPROVAL_MSG (Bash write target: $t)"
  done <<< "$BASH_TARGETS"
  exit 0
fi

# Path patterns cover both relative paths (`specs/foo.md` from CWD) and absolute
# paths (`/repo/specs/foo.md`). P1-pattern fix from v0.5 PR review hook-tests.
case "$FILE_TARGET" in
  specs/*|*/specs/*|.claude/assignment-claims/*|*/.claude/assignment-claims/*)
    exit 0
    ;;
  *)
    deny "$PRE_APPROVAL_MSG"
    ;;
esac
