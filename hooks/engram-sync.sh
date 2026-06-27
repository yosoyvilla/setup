#!/usr/bin/env bash
# Mirror new/edited Claude memory files into Engram. Async hook on Stop + PostCompact.
# Locking now lives INSIDE engram-sync.py (atomic mkdir lock) so that BOTH this
# hook-triggered path AND any direct manual `engram-sync.py` run are serialized
# against each other. Previously the lock was only here, so a manual run could race
# a hook run and corrupt the save/delete sequence (tombstoned a memory, 2026-06-19).
python3 "$HOME/.claude/hooks/engram-sync.py" "${1:-sync}" >>"$HOME/.claude/engram-sync.log" 2>&1
exit 0
