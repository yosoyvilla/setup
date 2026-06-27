#!/bin/bash
# Auto-sync Claude config to Obsidian vault after each session.
# Called by the Stop and PostCompact hooks in settings.json (async).
# Syncs: memory, agents, skills, rules

CLAUDE_DIR="$HOME/.claude"
MEMORY_SRC="$CLAUDE_DIR/projects/-Users-user/memory"
VAULT="$HOME/Documents/obsidian-vault"
LOG="$CLAUDE_DIR/sync.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

sync_dir() {
  local src="$1" dst="$2" label="$3"
  mkdir -p "$dst"
  if rsync -a --checksum --delete "$src/" "$dst/" 2>/dev/null; then
    log "$label synced"
  else
    log "$label rsync failed or nothing to sync"
  fi
}

# Sync all Claude config to vault
sync_dir "$MEMORY_SRC"              "$VAULT/claude-code/memory"  "Memory"
sync_dir "$CLAUDE_DIR/agents"       "$VAULT/claude-code/agents"  "Agents"
sync_dir "$CLAUDE_DIR/skills"       "$VAULT/claude-code/skills"  "Skills"
sync_dir "$CLAUDE_DIR/rules"        "$VAULT/claude-code/rules"   "Rules"
sync_dir "$CLAUDE_DIR/hooks"        "$VAULT/claude-code/hooks"   "Hooks"

# Sync settings.json (hooks, plugins, env vars, model)
cp "$CLAUDE_DIR/settings.json" "$VAULT/claude-code/settings.json" 2>/dev/null \
  && log "settings.json synced" || log "settings.json copy failed"

# Sync agent memories
sync_dir "$CLAUDE_DIR/agent-memory" "$VAULT/claude-code/agent-memory" "Agent Memory"

# Sync project-specific memories
sync_dir "$CLAUDE_DIR/projects/-Users-user-Documents-project-b/memory" \
         "$VAULT/claude-code/memory/project-b"  "Memory/project-b"
sync_dir "$CLAUDE_DIR/projects/-Users-user-Documents-project-c/memory" \
         "$VAULT/claude-code/memory/project-c" "Memory/Project-c"
sync_dir "$CLAUDE_DIR/projects/-Users-user-Documents-Project-a/memory" \
         "$VAULT/claude-code/memory/project-a" "Memory/Project-a"
sync_dir "$CLAUDE_DIR/projects/-Users-user-Documents-project-d/memory" \
         "$VAULT/claude-code/memory/project-d" "Memory/Project-d"

# Push vault if there are changes
cd "$VAULT" || { log "Cannot cd to vault"; exit 0; }
if git status --porcelain | grep -q .; then
  git add -A
  git commit -m "auto-sync $(date '+%Y-%m-%d %H:%M')"
  if git push origin main 2>/dev/null; then
    log "Vault pushed to origin/main"
  else
    log "Vault push failed — check SSH key / network"
  fi
else
  log "Vault up to date, nothing to push"
fi
