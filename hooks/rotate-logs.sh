#!/bin/bash
# Rotate the append-only logs written by this machine's OWN hooks.
#
# Why this exists: settings.json's `cleanupPeriodDays: 90` prunes session
# transcripts and Claude Code's own caches (verified empirically — the oldest
# surviving projects/**/*.jsonl was exactly 91 days old). It does NOT reach
# anything a user hook writes, so these three grew without bound:
#   command-audit.log   ~164 KB/day  (~60 MB/yr)   PostToolUse Bash hook
#   sync.log            ~54  KB/day                auto-sync.sh
#   engram-sync.log     ~8.8 KB/day                engram-sync.sh
#
# ROTATE, NOT DELETE: the user's position is that these are evidence. Nothing is
# discarded until KEEP generations have accumulated, and the oldest generation is
# the only thing ever removed.
#
# Safe against live appenders: hooks open these with >> (O_APPEND) per invocation
# rather than holding a long-lived fd, so a rename between invocations cannot
# strand writes. We copy-and-truncate anyway (cp then : >file) rather than mv, so
# any fd that IS open keeps pointing at the same inode and keeps working.

CLAUDE_DIR="$HOME/.claude"
MAX_BYTES=${MAX_BYTES:-5242880}   # rotate at 5 MB
KEEP=${KEEP:-5}                   # retained generations per log
STAMP="$(date '+%Y-%m-%d %H:%M:%S')"
SELF_LOG="$CLAUDE_DIR/rotate-logs.log"

log() { echo "[$STAMP] $*" >> "$SELF_LOG"; }

# Serialize against a concurrent run.
LOCK="$CLAUDE_DIR/.rotate-logs.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

rotate() {
  local f="$1" size
  [ -f "$f" ] || return 0
  size=$(/usr/bin/stat -f%z "$f" 2>/dev/null || echo 0)
  [ "$size" -lt "$MAX_BYTES" ] && return 0

  # Reclaim an UNCOMPRESSED .1 left behind by a previous gzip failure. The shift loop
  # below only moves *.gz, so such an orphan was invisible to it and the rename at the
  # end would overwrite it — silently destroying a generation while the log claimed
  # success. That directly contradicted this file's own "nothing is discarded" promise.
  if [ -f "$f.1" ]; then
    if gzip -f "$f.1" 2>/dev/null; then
      log "recovered uncompressed orphan $(basename "$f").1 from a previous failed gzip"
    else
      mv -f "$f.1" "$f.1.orphan" 2>/dev/null
      log "WARNING: could not gzip orphan $(basename "$f").1 — preserved as .1.orphan"
    fi
  fi

  # Drop only the oldest generation, then shift the rest down.
  [ -f "$f.$KEEP.gz" ] && rm -f "$f.$KEEP.gz"
  local i=$((KEEP-1))
  while [ "$i" -ge 1 ]; do
    [ -f "$f.$i.gz" ] && mv -f "$f.$i.gz" "$f.$((i+1)).gz"
    i=$((i-1))
  done

  # RENAME, not copy-and-truncate. The original used `cp f f.1` then `: > f`, which has a
  # data-loss window: auto-sync.sh, engram-sync.sh and this script are three separate
  # async Stop-hook entries with no shared lock, so a `log()` append landing between the
  # cp and the truncate was written into the original file and then destroyed by the
  # truncate — captured in neither the archive nor the live log. A rename has no such
  # window: an already-open O_APPEND fd follows the inode into the archive (preserved,
  # not lost), and the next `>>` from any hook recreates the live file.
  if mv "$f" "$f.1" 2>/dev/null; then
    : > "$f"          # recreate immediately so nothing races on a missing path
    chmod 644 "$f" 2>/dev/null
    # gzip's exit code is CHECKED. Previously this log line ran unconditionally and
    # named a .gz that would not exist if gzip had failed — the script misreported its
    # own outcome, which is worse than failing loudly.
    if gzip -f "$f.1" 2>/dev/null; then
      log "rotated $(basename "$f") at $size bytes -> $(basename "$f").1.gz (keeping $KEEP generations)"
    else
      log "WARNING: rotated $(basename "$f") at $size bytes but gzip FAILED — archive left UNCOMPRESSED at $(basename "$f").1 (it will be recovered on the next run)"
    fi
  else
    log "FAILED to rotate $(basename "$f")"
  fi
}

rotate "$CLAUDE_DIR/command-audit.log"
rotate "$CLAUDE_DIR/sync.log"
rotate "$CLAUDE_DIR/engram-sync.log"
rotate "$CLAUDE_DIR/maintenance.log"
# The rotator's own log was the one file in this design guaranteed to grow forever —
# a literal instance of the problem this script exists to solve, inside the solution.
rotate "$SELF_LOG"
exit 0
