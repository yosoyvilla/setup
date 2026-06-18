#!/usr/bin/env bash
# Mirror new/edited Claude memory files into Engram. Async hook on Stop + PostCompact.
# macOS has no flock; use an atomic mkdir lock so concurrent session-ends don't race.
LOCK=/tmp/engram-sync.lock
# Clear a stale lock left by a hard-killed process (older than 60 min), so a
# crash can never permanently disable syncing.
if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
  rmdir "$LOCK" 2>/dev/null
fi
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

python3 "$HOME/.claude/hooks/engram-sync.py" "${1:-sync}" >>"$HOME/.claude/engram-sync.log" 2>&1
exit 0
