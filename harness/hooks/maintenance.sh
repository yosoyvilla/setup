#!/bin/bash
# Weekly harness maintenance: report available updates, then clean verified-stale state.
#
# DESIGN CHOICE — checks and reports, does NOT auto-apply, unless --apply is passed.
# Silently upgrading a working harness is how a working harness stops working, and this
# machine's own history shows why: a self-installing tool wrote 7 hook registrations into
# settings.json on 2026-06-10 that were still there, dead, two months later. Updates are
# surfaced; a human decides. `--apply` exists for when that decision is already made.
#
# Cleaning is deliberately narrow. Only artifacts proven disposable are touched, and
# transcripts / audit logs are NEVER deleted — the user's position is that they are
# evidence, and `cleanupPeriodDays: 90` already prunes what Claude Code owns.
#
# Usage: maintenance.sh [--apply] [--quiet]

CLAUDE_DIR="$HOME/.claude"
LOG="$CLAUDE_DIR/maintenance.log"
APPLY=0; QUIET=0
for a in "$@"; do
  [ "$a" = "--apply" ] && APPLY=1
  [ "$a" = "--quiet" ] && QUIET=1
done

say() { [ "$QUIET" = 1 ] || echo "$*"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

LOCK="$CLAUDE_DIR/.maintenance.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || exit 0
  else exit 0; fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

say "=== maintenance start (apply=$APPLY) ==="

# ---------- 1. UPDATES ----------
say "--- updates ---"
say "claude CLI: $(claude --version 2>&1 | head -1)"
if [ "$APPLY" = 1 ]; then
  claude update >/dev/null 2>&1 && say "claude update: done (restart to apply)" || say "claude update: failed or already current"
  claude plugin marketplace update >/dev/null 2>&1 && say "marketplaces refreshed" || say "marketplace refresh failed"
  # Update only ENABLED plugins; a disabled plugin does not need to be current.
  for p in $(python3 - <<'PY' 2>/dev/null
import json,os
d=json.load(open(os.path.expanduser("~/.claude/settings.json")))
print("\n".join(k for k,v in d.get("enabledPlugins",{}).items() if v))
PY
  ); do
    claude plugin update "$p" >/dev/null 2>&1 && say "updated plugin $p" || true
  done
  claude plugin prune >/dev/null 2>&1 && say "pruned orphaned auto-installed plugin deps" || true
else
  say "check-only. Run with --apply to install: claude update; claude plugin marketplace update; claude plugin update <name>; claude plugin prune"
fi

# ---------- 2. CLEAN (narrow, verified-safe only) ----------
say "--- clean ---"
freed=0
count_rm() { # $1=description, rest=find args already resolved to a file list on stdin
  local n=0
  while IFS= read -r f; do [ -n "$f" ] || continue; rm -f "$f" 2>/dev/null && n=$((n+1)); done
  [ "$n" -gt 0 ] && say "removed $n $1"
  freed=$((freed+n))
}

# Stale locks from killed runs. Anything older than an hour is not a live holder.
find "$CLAUDE_DIR" -maxdepth 1 -type d -name '.*.lock' -mmin +60 2>/dev/null | while IFS= read -r d; do
  rmdir "$d" 2>/dev/null && say "reclaimed stale lock $(basename "$d")"
done

# Per-session test-tamper state: worthless once the session is gone.
find "$CLAUDE_DIR/.test-tamper-state" -type f -mtime +7 2>/dev/null | count_rm "old test-tamper state files"

# Plugin warning-state: one file per session, never pruned by cleanupPeriodDays.
find "$CLAUDE_DIR/security" -maxdepth 1 -name 'security_warnings_state_*' -mtime +30 2>/dev/null | count_rm "old security_warnings_state files (>30d)"

# Orphaned plugin data dirs for plugins that are no longer enabled.
python3 - <<'PY' 2>/dev/null
import json,os,shutil
base=os.path.expanduser("~/.claude/plugins/data")
try: enabled={k.split("@")[0] for k,v in json.load(open(os.path.expanduser("~/.claude/settings.json"))).get("enabledPlugins",{}).items() if v}
except Exception: raise SystemExit
if os.path.isdir(base):
    for d in sorted(os.listdir(base)):
        name=d.rsplit("-claude-plugins-official",1)[0].rsplit("-ponytail",1)[0]
        if name not in enabled:
            print(f"ORPHAN_PLUGIN_DATA {d}")
PY

# Log rotation is owned by rotate-logs.sh; invoke rather than duplicate the logic.
[ -x "$CLAUDE_DIR/hooks/rotate-logs.sh" ] && "$CLAUDE_DIR/hooks/rotate-logs.sh" && say "log rotation checked"

# Self-bound: this log must not become the thing it cleans.
if [ -f "$LOG" ] && [ "$(/usr/bin/stat -f%z "$LOG" 2>/dev/null || echo 0)" -gt 1048576 ]; then
  tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  say "truncated own log to last 500 lines"
fi

say "=== maintenance done (removed $freed files) ==="
exit 0
