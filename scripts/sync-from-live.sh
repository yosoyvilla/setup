#!/usr/bin/env bash
#
# sync-from-live.sh — sanitized live -> repo sync for this setup repo.
#
# Stages the live workstation harness config (Claude Code, opencode, Zed,
# ~/.agents/skills) into a temp dir, templatizes machine paths
# (__HOME__ / __ENGRAM__), applies the client-name sanitize map, then verifies
# hard gates before mirroring the staging tree into this repo's working tree:
#   1. no sanitize-map token survives in file CONTENT or file NAMES
#   2. no secret-shaped string (token prefixes, private keys, JWTs, live key values)
#   3. AGENTS.md byte-parity between the opencode and Zed copies
# Any gate failure aborts with the staging dir preserved for inspection and the
# repo untouched. The script NEVER commits and NEVER writes to live config.
#
# The sanitize map is deliberately NOT in this repo (committing it would reveal
# the very names it scrubs). It lives at ~/.config/setup-sync/sanitize-map.txt:
# tab-separated "pattern<TAB>replacement" lines, applied top-to-bottom,
# case-insensitive. Format: see scripts/sanitize-map.example. Keep the most
# specific patterns first (foo.com before foo).
#
# Usage:
#   scripts/sync-from-live.sh [--dry-run]
#
# Env overrides (used by the test harness):
#   SYNC_LIVE_HOME  read live config from this home dir instead of $HOME
#   SYNC_MAP_FILE   sanitize map path (default ~/.config/setup-sync/sanitize-map.txt)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE_HOME="${SYNC_LIVE_HOME:-$HOME}"
MAP_FILE="${SYNC_MAP_FILE:-$HOME/.config/setup-sync/sanitize-map.txt}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# Repo files with intentional divergence from live (e.g. REQUIRES SECRET
# annotations not present in the live copies). The repo version wins; the
# sanitized live version is shown as a diff for awareness.
PROTECTED="agents/airbyte.md skills/scalr-deploy/SKILL.md"

# Repo dirs fully mirrored from staging (rsync --delete).
MANAGED_DIRS="agents skills hooks rules zed-skills opencode-agents opencode-commands opencode-plugins opencode-scripts"

c_red=$'\033[0;31m'; c_green=$'\033[0;32m'; c_yellow=$'\033[0;33m'; c_blue=$'\033[0;34m'; c_off=$'\033[0m'
section(){ printf "\n%s==> %s%s\n" "$c_blue" "$1" "$c_off"; }
ok(){ printf "  %s+%s %s\n" "$c_green" "$c_off" "$1"; }
warn(){ printf "  %s!%s %s\n" "$c_yellow" "$c_off" "$1"; }
KEEP_STAGE=0
STAGE=""
die(){ printf "%sFAIL: %s%s\n" "$c_red" "$1" "$c_off" >&2; KEEP_STAGE=1; exit 1; }

[ -f "$MAP_FILE" ] || die "sanitize map not found: $MAP_FILE
  Create it as tab-separated 'pattern<TAB>replacement' lines (most specific
  first, e.g. foo.com before foo). Format: scripts/sanitize-map.example.
  On a fresh machine, recreate it from the Obsidian vault notes."

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/setup-sync.XXXXXX")"
TEXT_LIST="$(mktemp "${TMPDIR:-/tmp}/setup-sync-textfiles.XXXXXX")"
SCAN_ERR="${TEXT_LIST}.err"
cleanup(){
  rm -f "$TEXT_LIST" "$SCAN_ERR"
  if [ "$KEEP_STAGE" -eq 1 ] && [ -n "$STAGE" ]; then
    printf "  %s!%s staging kept for inspection: %s\n" "$c_yellow" "$c_off" "$STAGE" >&2
  else
    [ -n "$STAGE" ] && rm -rf "$STAGE"
  fi
}
trap cleanup EXIT

# ── stage live config (live side is strictly read-only) ─────────────
section "Staging live config from $LIVE_HOME"
EXCLUDES=(--exclude '*.bak*' --exclude '*.backup*' --exclude '*.premigration*'
          --exclude '__pycache__/' --exclude '*.pyc' --exclude 'node_modules/'
          --exclude 'logs/' --exclude 'tasks/' --exclude '.DS_Store'
          --exclude 'package.json' --exclude 'package-lock.json')

stage_dir(){ # src dst [rsync extra flags]
  local src="$1" dst="$2"; shift 2
  if [ -d "$src" ]; then
    rsync -a "$@" "${EXCLUDES[@]}" "$src/" "$STAGE/$dst/" || die "staging $dst/ failed"
    ok "$dst/"
  else
    warn "missing $src (skipped)"
  fi
}
stage_file(){ # src dst
  if [ -f "$1" ]; then
    mkdir -p "$STAGE/$(dirname "$2")"
    cp "$1" "$STAGE/$2" || die "staging $2 failed"
    ok "$2"
  else
    warn "missing $1 (skipped)"
  fi
}

# Claude-only policy: the vendored Claude Code config is shared with a team
# that uses Claude Code only — the engram-sync hooks (Engram/opencode-ecosystem
# memory bridge) are excluded from vendoring. The live machine keeps them.
stage_dir "$LIVE_HOME/.claude/agents"            agents
stage_dir "$LIVE_HOME/.claude/skills"            skills
stage_dir "$LIVE_HOME/.claude/hooks"             hooks --exclude 'engram-sync.*'
stage_dir "$LIVE_HOME/.claude/rules"             rules
stage_dir "$LIVE_HOME/.agents/skills"            zed-skills -L   # resolve symlinks to real files
stage_dir "$LIVE_HOME/.config/opencode/agents"   opencode-agents
stage_dir "$LIVE_HOME/.config/opencode/commands" opencode-commands
stage_dir "$LIVE_HOME/.config/opencode/plugins"  opencode-plugins
stage_dir "$LIVE_HOME/.config/opencode/scripts"  opencode-scripts

stage_file "$LIVE_HOME/.claude/CLAUDE.md"                     config/CLAUDE.md
stage_file "$LIVE_HOME/.claude/settings.json"                 config/claude-settings.json
stage_file "$LIVE_HOME/.claude/settings.local.json"           config/claude-settings.local.json
stage_file "$LIVE_HOME/.config/opencode/opencode.jsonc"       config/opencode.jsonc
stage_file "$LIVE_HOME/.config/opencode/tui.json"             config/tui.json
stage_file "$LIVE_HOME/.opencode/opencode.json"               config/opencode-secondary.json
stage_file "$LIVE_HOME/.config/zed/settings.json"             config/zed-settings.json
stage_file "$LIVE_HOME/.config/opencode/oh-my-openagent.json" oh-my-openagent.json
stage_file "$LIVE_HOME/.config/opencode/AGENTS.md"            AGENTS.md
stage_file "$LIVE_HOME/.config/zed/AGENTS.md"                 .zed-AGENTS.md

# Strip engram-sync hook entries from the staged Claude settings (same
# Claude-only policy as the hooks exclusion above).
if [ -f "$STAGE/config/claude-settings.json" ]; then
  command -v python3 >/dev/null 2>&1 || die "python3 required to filter claude-settings.json hooks"
  # explicit || die: a failed left side of '&&' would NOT abort under set -e
  python3 - "$STAGE/config/claude-settings.json" <<'PY' || die "failed to strip engram-sync hooks from claude-settings.json"
import json, sys
p = sys.argv[1]
d = json.load(open(p))
hooks = d.get("hooks", {})
for ev in list(hooks):
    kept = []
    for m in hooks[ev]:
        hs = [h for h in m.get("hooks", []) if "engram-sync" not in h.get("command", "")]
        if hs:
            m["hooks"] = hs
            kept.append(m)
    if kept:
        hooks[ev] = kept
    else:
        del hooks[ev]
with open(p, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  ok "claude-settings.json: engram-sync hooks stripped"
fi

# Refuse to mirror if any managed dir staged empty — with rsync --delete an
# empty staging dir would wipe the repo copy (e.g. mistyped SYNC_LIVE_HOME).
for d in $MANAGED_DIRS; do
  n="$(find "$STAGE/$d" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "${n:-0}" -ge 1 ] || die "staged $d/ is empty or missing — refusing to mirror (would delete repo content)"
done

# ── AGENTS.md parity gate (opencode copy must equal Zed copy) ───────
section "Gate: AGENTS.md parity"
if [ -f "$STAGE/AGENTS.md" ] && [ -f "$STAGE/.zed-AGENTS.md" ]; then
  cmp -s "$STAGE/AGENTS.md" "$STAGE/.zed-AGENTS.md" \
    || die "AGENTS.md drift: opencode and Zed copies differ — reconcile live copies first"
  rm -f "$STAGE/.zed-AGENTS.md"
  ok "opencode == Zed"
else
  die "AGENTS.md missing from live opencode or Zed config"
fi

# ── templatize machine-specific paths (BEFORE the sanitize map runs, ──
#    so real home paths become __HOME__ tokens instead of sanitized paths)
section "Templatizing machine paths"
ENGRAM_BIN="$(command -v engram || echo /opt/homebrew/bin/engram)"
if [ -f "$STAGE/config/zed-settings.json" ]; then
  perl -pi -e "s#\Q$ENGRAM_BIN\E#__ENGRAM__#g" "$STAGE/config/zed-settings.json" \
    || die "engram templating failed"
  ok "zed-settings.json: engram binary -> __ENGRAM__"
fi
for f in "$STAGE"/config/claude-settings.json "$STAGE"/config/claude-settings.local.json \
         "$STAGE"/config/opencode.jsonc "$STAGE"/config/zed-settings.json \
         "$STAGE"/config/CLAUDE.md "$STAGE"/oh-my-openagent.json; do
  if [ -f "$f" ]; then
    perl -pi -e "s#\Q$LIVE_HOME\E#__HOME__#g" "$f" || die "__HOME__ templating failed for $f"
  fi
done
ok "absolute home paths -> __HOME__"

# ── apply sanitize map to every text file in staging ────────────────
section "Sanitizing"
# NOTE: --null (long form) is mandatory — BSD grep's -Z means "decompress",
# only GNU grep aliases -Z to --null. Both support --null with -l.
find "$STAGE" -type f -print0 | xargs -0 grep -Il --null -e '' -- > "$TEXT_LIST" || true
if [ -s "$TEXT_LIST" ]; then
  # shellcheck disable=SC2016  # $ENV{...} is perl, not shell
  MAP_FILE="$MAP_FILE" xargs -0 perl -i -pe '
    BEGIN {
      open my $m, "<", $ENV{MAP_FILE} or die "cannot read map: $!";
      while (my $l = <$m>) {
        chomp $l; next if $l =~ /^\s*(?:#|$)/;
        my ($p, $r) = split /\t+/, $l, 2;
        die "malformed map line: $l\n" unless defined $r && length $r;
        push @MAP, [qr/\Q$p\E/i, $r];
      }
      close $m;
    }
    for my $e (@MAP) { s/$e->[0]/$e->[1]/g }
  ' < "$TEXT_LIST" 2> "$SCAN_ERR" || die "sanitize pass failed: $(cat "$SCAN_ERR")"
  [ -s "$SCAN_ERR" ] && die "sanitize pass reported errors: $(cat "$SCAN_ERR")"
  ok "map applied to $(tr -cd '\0' < "$TEXT_LIST" | wc -c | tr -d ' ') text files"
else
  die "no text files staged — nothing to sanitize (staging broken?)"
fi

# ── gates ────────────────────────────────────────────────────────────
# Scan regex derives from the map patterns with a LEADING word boundary only:
# trailing \b would miss prefix forms (e.g. token 'acme' inside 'acmegcp').
section "Gate: no client-name token survives"
GATE_RE="$(perl -ne 'chomp; next if /^\s*(?:#|$)/; my ($p) = split /\t+/, $_, 2; push @t, quotemeta($p); END { print join("|", @t) }' "$MAP_FILE")"
[ -n "$GATE_RE" ] || die "sanitize map produced an empty scan regex"
# A scan that ERRORS must abort — an empty result from a failed scanner would
# otherwise read as "clean". Scanner stderr is captured and checked after each.
# shellcheck disable=SC2016  # $ENV{...} is perl, not shell
content_hits="$(GATE_RE="$GATE_RE" xargs -0 perl -lne 'print "$ARGV:$.: $_" if /\b(?:$ENV{GATE_RE})/i' < "$TEXT_LIST" 2> "$SCAN_ERR" || true)"
[ -s "$SCAN_ERR" ] && die "content scan errored (treating as failure): $(cat "$SCAN_ERR")"
[ -z "$content_hits" ] || die "client-name tokens survived sanitization:
$content_hits"
# shellcheck disable=SC2016
name_hits="$( { find "$STAGE" -print | GATE_RE="$GATE_RE" perl -lne 'print if /\b(?:$ENV{GATE_RE})/i'; } 2> "$SCAN_ERR" || true)"
[ -s "$SCAN_ERR" ] && die "name scan errored (treating as failure): $(cat "$SCAN_ERR")"
[ -z "$name_hits" ] || die "client-name tokens in file/dir NAMES (rename manually, then re-run):
$name_hits"
ok "0 hits in content and names"

section "Gate: no secrets"
SECRET_RE='ghp_[A-Za-z0-9]{20}|github_pat_[A-Za-z0-9_]{20}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10}|sk-ant-[A-Za-z0-9_-]{10}|-----BEGIN [A-Z ]*PRIVATE KEY|eyJ[A-Za-z0-9_-]{20,}\.eyJ'
secret_hits="$(xargs -0 grep -EHn -e "$SECRET_RE" -- < "$TEXT_LIST" 2> "$SCAN_ERR" || true)"
[ -s "$SCAN_ERR" ] && die "secret scan errored (treating as failure): $(cat "$SCAN_ERR")"
[ -z "$secret_hits" ] || die "secret-shaped strings found:
$secret_hits"
if [ -n "${NAN_API_KEY:-}" ]; then
  key_hits="$(xargs -0 grep -Fln -e "$NAN_API_KEY" -- < "$TEXT_LIST" 2> "$SCAN_ERR" || true)"
  [ -s "$SCAN_ERR" ] && die "key scan errored (treating as failure): $(cat "$SCAN_ERR")"
  [ -z "$key_hits" ] || die "literal NAN_API_KEY value found in:
$key_hits"
fi
ok "0 hits"

# ── protected files: repo version wins ───────────────────────────────
section "Protected files (repo version kept)"
for p in $PROTECTED; do
  if [ -f "$REPO_DIR/$p" ]; then
    if [ -f "$STAGE/$p" ] && ! cmp -s "$REPO_DIR/$p" "$STAGE/$p"; then
      warn "$p: sanitized live differs from repo — repo version kept; diff (live -> repo):"
      diff -u "$STAGE/$p" "$REPO_DIR/$p" | sed 's/^/    /' || true
    fi
    mkdir -p "$STAGE/$(dirname "$p")"
    cp "$REPO_DIR/$p" "$STAGE/$p"
    ok "$p"
  else
    warn "$p not in repo yet — taking sanitized live version (re-add annotations before committing)"
  fi
done

# ── dry-run or apply ─────────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  section "Dry run — incoming changes (repo vs staged)"
  for d in $MANAGED_DIRS; do
    if [ -d "$REPO_DIR/$d" ]; then diff -ruN "$REPO_DIR/$d" "$STAGE/$d" || true
    else warn "$d/ is new to the repo:"; find "$STAGE/$d" -type f | sed "s#^$STAGE/#  + #"; fi
  done
  [ -d "$STAGE/config" ] && { diff -ruN "$REPO_DIR/config" "$STAGE/config" || true; }
  [ -f "$STAGE/AGENTS.md" ] && { diff -u "$REPO_DIR/AGENTS.md" "$STAGE/AGENTS.md" || true; }
  [ -f "$STAGE/oh-my-openagent.json" ] && { diff -u "$REPO_DIR/oh-my-openagent.json" "$STAGE/oh-my-openagent.json" || true; }
  section "Dry run complete — repo untouched"
  exit 0
fi

section "Mirroring staging into repo working tree"
for d in $MANAGED_DIRS; do
  # re-verify non-empty right before --delete (staging could have been cleaned
  # under us between the earlier gate and now)
  [ -n "$(find "$STAGE/$d" -type f 2>/dev/null | head -1)" ] || die "staged $d/ vanished before mirror — aborting"
  rsync -a --delete "$STAGE/$d/" "$REPO_DIR/$d/" || die "mirror failed for $d/"
  ok "$d/"
done
[ -n "$(find "$STAGE/config" -type f 2>/dev/null | head -1)" ] || die "no staged config files — aborting"
cp "$STAGE"/config/* "$REPO_DIR/config/" || die "config copy failed"
ok "config/"
cp "$STAGE/AGENTS.md" "$REPO_DIR/AGENTS.md" || die "AGENTS.md copy failed"
ok "AGENTS.md"
cp "$STAGE/oh-my-openagent.json" "$REPO_DIR/oh-my-openagent.json" || die "oh-my-openagent.json copy failed"
ok "oh-my-openagent.json"

section "Done — review and commit manually"
git -C "$REPO_DIR" status --short || true
warn "review 'git diff' carefully, then commit yourself (single-line message, no emojis, no session URLs)"
if git -C "$REPO_DIR" status --porcelain 2>/dev/null | grep -qE 'config/(opencode\.jsonc|zed-settings\.json)'; then
  warn "config/opencode.jsonc or config/zed-settings.json changed — README keeps INLINE copies of both; update README manually"
fi
