#!/bin/bash
# Auto-sync Claude config to Obsidian vault after each session.
# Called by the Stop and PostCompact hooks in settings.json (async).
# Syncs: memory, agents, skills, rules

CLAUDE_DIR="$HOME/.claude"
# Claude encodes the cwd into the project dir name (/Users/alice -> -Users-alice).
# Derive it from the real $HOME so this works for any user/machine.
HOME_ENC="${HOME//\//-}"
MEMORY_SRC="$CLAUDE_DIR/projects/$HOME_ENC/memory"
VAULT="$HOME/Documents/obsidian-vault"
LOG="$CLAUDE_DIR/sync.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# The vault is optional (personal machines only). Bail out BEFORE any mkdir:
# the sync_dir calls below would otherwise materialize a phantom vault tree on
# machines that never cloned it.
[ -d "$VAULT/.git" ] || { log "Vault not cloned at $VAULT — skipping sync"; exit 0; }

# Concurrency lock (2026-08-21). Two Stop hooks could previously run at once.
# Because the home-memory sync's destination is the PARENT of the per-project
# subdirs written below, a racing pair could commit a tree mid-delete: that is
# what produced b9547e3 (46 removed, 0 added) and c9f2568 (46 added) in the SAME
# second on 2026-07-27. engram-sync.py already locked for this reason; this did not.
LOCK="$CLAUDE_DIR/.auto-sync.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  # Reclaim on PID LIVENESS, not on age. A fixed mtime TTL reintroduces the very race
  # this lock closes: a sync that legitimately runs longer than the TTL (large corpus,
  # slow network on the push, machine resumed from sleep mid-run) gets its lock stolen
  # by the next invocation, and two writers proceed concurrently — exactly the condition
  # that produced the 2026-07-27 mid-delete commit. A holder whose process is alive keeps
  # the lock however long it takes; only a dead holder is displaced.
  HOLDER=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$HOLDER" ] && kill -0 "$HOLDER" 2>/dev/null; then
    log "Another sync (pid $HOLDER) is running — skipping this run"
    exit 0
  fi
  # No pid file, or the holder is gone: the lock is orphaned.
  log "Reclaiming orphaned lock (holder pid '${HOLDER:-none}' not alive)"
  rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || { log "Lock contended — skipping"; exit 0; }
fi
echo "$$" > "$LOCK/pid" 2>/dev/null
trap 'rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

# Secret pre-flight (2026-08-21). engram-sync.py filters secrets before writing to a
# LOCAL sqlite store, while this script — the one that pushes to a GitHub remote — had
# none. Two live credentials reached the remote that way (a BasicAuth pair on
# 2026-04-09, a vendor-prefixed API token on 2026-05-08), neither of which
# engram-sync.py's regex would have matched anyway.
#
# Failure mode is deliberate: offending FILES are excluded from the sync and loudly
# logged. Aborting the whole push instead would wedge the vault permanently, because
# the offending file stays on disk and every later session would fail too.

# Benign filter. Without it the scanner withheld 8 legitimate memory files forever —
# silently ending their backup. All 8 were verified non-credentials on 2026-08-21:
#   $CLICKHOUSE_* env-var references, literal <password> placeholders, localhost /
#   docker-compose dev credentials, and AWS access key IDs (an AKIA id without its
#   paired secret is an identifier, not a usable credential).
# `secret-scan-ok` is a human opt-out marker for a reviewed file.
secret_excludes=()   # rsync --exclude args for files that must not leave this machine
withheld_names=()    # basenames withheld this run, so the vault can be marked

# Detection lives in secret-scan.py, not in a grep pipeline. Two reasons, both learned
# the hard way on 2026-08-21:
#   1. A grep pipeline classifies LINES. One benign `$VAR` on the same line as a live
#      token suppressed the whole line and the token shipped. Reproduced. The scanner
#      classifies each MATCH instead, so a benign neighbour cannot mask a real secret.
#   2. `grep` on PATH here is ugrep, whose `-qv` returns 0 on EMPTY input where GNU grep
#      returns 1 — an inversion that made every clean file look like a hit.
# It also scans EVERY file, not just *.md: the old glob was *.md while the sync copied
# the whole directory, so a .json dropped into a memory dir went out unscanned.
SCANNER="$CLAUDE_DIR/hooks/secret-scan.py"
scan_secrets() {
  local dir="$1" base
  secret_excludes=(); withheld_names=()
  [ -d "$dir" ] || return 0
  # -f, not -x: the scanner is invoked as `python3 "$SCANNER"`, so its exec bit is
  # irrelevant — and editing the file resets that bit, which on 2026-08-21 silently
  # turned this check false and pushed all six memory dirs UNSCANNED.
  #
  # FAIL CLOSED. If the scanner cannot run, withhold the whole directory rather than
  # mirror it unchecked: this is the one control standing between a live credential and
  # a git remote, and "warn but push anyway" defeats it. The caller marks the gap in the
  # vault so a skipped sync is visible rather than silently stale.
  if [ ! -f "$SCANNER" ] || ! python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$SCANNER" 2>/dev/null; then
    log "ERROR: secret scanner unusable at $SCANNER — WITHHOLDING $dir entirely (fail-closed). Fix the scanner to resume mirroring."
    secret_excludes=( "--exclude=*" )
    SCANNER_BROKEN=1
    return 0
  fi
  while IFS= read -r base; do
    [ -n "$base" ] || continue
    secret_excludes+=( "--exclude=$base" )
    withheld_names+=( "$base" )
    log "SECRET WITHHELD: $dir/$base contains credential material — not synced. Rotate it, then redact."
  done < <(python3 "$SCANNER" "$dir" 2>>"$LOG")
  [ ${#withheld_names[@]} -gt 0 ] && log "WARNING: ${#withheld_names[@]} file(s) withheld from vault this run"
  return 0
}

# A withheld file must not leave a STALE copy behind. rsync's --exclude protects the
# destination from --delete as well as from transfer, so an already-synced file that
# later trips the scanner would silently freeze at its last-good content, with nothing
# in the vault to show it had stopped updating — worse than either syncing or removing.
# So: remove the vault copy and drop a visible marker in its place.
mark_withheld() {
  local dst="$1" base
  for base in "${withheld_names[@]}"; do
    [ -n "$base" ] || continue
    rm -f "$dst/$base" 2>/dev/null
    printf '%s\n' \
      "# WITHHELD — not synced" "" \
      "\`$base\` is present on the source machine but is NOT mirrored here: it contains" \
      "credential material. This marker exists so the gap is visible instead of the file" \
      "silently freezing at stale content." "" \
      "Fix by ROTATING the credential first, then redacting the value in the source file." \
      "Redaction alone does not help — anything already pushed is in this repo's history." "" \
      "Marker written $(date '+%Y-%m-%d %H:%M:%S') by auto-sync.sh." \
      > "$dst/${base%.md}.WITHHELD.md" 2>/dev/null
  done
}

sync_dir() {
  local src="$1" dst="$2" label="$3"; shift 3
  local extra=("$@")
  mkdir -p "$dst"
  if rsync -a --checksum --delete "${extra[@]}" "$src/" "$dst/" 2>/dev/null; then
    log "$label synced"
  else
    log "$label rsync failed or nothing to sync"
  fi
}

# Sync all Claude config to vault.
# The Memory line passes --exclude='*/' so this flat sync cannot delete the
# per-project subdirs written into the same parent at the bottom of this script.
# Verified on the installed openrsync 2.6.9: excluded destination paths survive
# --delete (only --delete-excluded would remove them).
scan_secrets "$MEMORY_SRC"
sync_dir "$MEMORY_SRC"              "$VAULT/claude-code/memory"  "Memory" --exclude='*/' "${secret_excludes[@]}"
mark_withheld "$VAULT/claude-code/memory"
sync_dir "$CLAUDE_DIR/agents"       "$VAULT/claude-code/agents"  "Agents"
sync_dir "$CLAUDE_DIR/skills"       "$VAULT/claude-code/skills"  "Skills"
sync_dir "$CLAUDE_DIR/rules"        "$VAULT/claude-code/rules"   "Rules"
sync_dir "$CLAUDE_DIR/hooks"        "$VAULT/claude-code/hooks"   "Hooks"

# Sync settings.json (hooks, plugins, env vars, model)
cp "$CLAUDE_DIR/settings.json" "$VAULT/claude-code/settings.json" 2>/dev/null \
  && log "settings.json synced" || log "settings.json copy failed"

# Sync agent memories
sync_dir "$CLAUDE_DIR/agent-memory" "$VAULT/claude-code/agent-memory" "Agent Memory"

# Sync project-specific memories — discovered dynamically, so it works for any
# user and any set of projects (no hardcoded usernames or project names).
for proj_mem in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$proj_mem" ] || continue
  # Skip de-siloed subproject dirs (2026-08-21). Those are symlinks pointing at their
  # parent project's memory so a session in a subdirectory can see the whole project's
  # memory instead of an isolated shard. Without this guard the same content would be
  # mirrored into ~40 vault subdirectories under different names.
  [ -L "$proj_mem" ] && continue
  enc="$(basename "$(dirname "$proj_mem")")"
  [ "$enc" = "$HOME_ENC" ] && continue          # home/global memory already synced above
  name="${enc##*-Documents-}"                    # decode to a clean project name
  scan_secrets "$proj_mem"
  sync_dir "$proj_mem" "$VAULT/claude-code/memory/$name" "Memory/$name" "${secret_excludes[@]}"
  mark_withheld "$VAULT/claude-code/memory/$name"
done

# Push vault if there are changes
cd "$VAULT" || { log "Cannot cd to vault"; exit 0; }
if git status --porcelain | grep -q .; then
  git add -A
  # Descriptive commit subject (2026-08-21). Previously every commit was
  # "auto-sync <timestamp>" — 925 of 1046 commits, 88.4% of the whole history — which
  # made `git log` useless for answering "when did the networking agent change?".
  # Now the subject names what actually moved, so the vault becomes searchable.
  AREAS=$(git diff --cached --name-only \
            | sed -n 's|^claude-code/\([^/]*\).*|\1|p' \
            | sed 's/\.md$//; s/\.json$//; s/\.sh$//' \
            | sort -u | tr '\n' ' ' | sed 's/ $//')
  NFILES=$(git diff --cached --name-only | wc -l | tr -d ' ')
  [ -z "$AREAS" ] && AREAS="vault"
  git commit -q -m "sync: ${AREAS} (${NFILES} file$([ "$NFILES" = 1 ] || echo s)) $(date '+%Y-%m-%d %H:%M')"
  if git push origin main 2>/dev/null; then
    log "Vault pushed to origin/main"
  else
    log "Vault push failed — check SSH key / network"
  fi
else
  log "Vault up to date, nothing to push"
fi
