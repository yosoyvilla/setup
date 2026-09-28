#!/usr/bin/env bash
# SessionStart: regenerate every tool's config from ~/.harness so live can never drift.
# Drift appeared within a day of the cutover, which is why this runs on a trigger rather
# than from memory. Fails soft: a broken sync must never block a session from starting.
H="$HOME/.harness"
[ -d "$H" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

out=$(cd "$HOME" && /usr/bin/env python3 "$H/sync.py" 2>&1) || {
  printf 'harness sync failed; live config may be stale. Run: python3 ~/.harness/sync.py\n'
  exit 0
}
# Report only when something actually changed, so a clean session stays silent.
changed=$(printf '%s' "$out" | /usr/bin/python3 -c '
import json,sys
raw=sys.stdin.read()
try: d=json.loads(raw.split("sync result: ",1)[1])
except Exception: sys.exit(0)
diff={k:v for k,v in d.items() if ("same" not in k) and v!="same"}
if diff: print("harness sync applied: "+", ".join(f"{k}={v}" for k,v in diff.items()))
' 2>/dev/null)
[ -n "$changed" ] && printf '%s\n' "$changed"
exit 0
