#!/usr/bin/env bash
#
# install.sh — reproduce this developer workstation on a fresh machine.
#
# Supports: macOS (Homebrew) and Debian/Ubuntu (apt).
# Idempotent: safe to re-run. Unattended: never prompts, never writes secrets.
# Installs the full stack (tools + Claude Code + opencode + pi/gentle-pi + Codex
# CLI + Herdr + Engram + Playwright) and places every vendored config/agent/
# skill/rule/hook. Zed was retired from this setup on 2026-09-21.
# Manual steps it cannot automate (API keys, auths, GUI) are printed as a TODO
# list at the end.
#
# Usage:  cd <this repo>  &&  ./install.sh
#
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODO=()
FAILED=()

# ── output helpers ────────────────────────────────────────────────
c_blue='\033[0;34m'; c_green='\033[0;32m'; c_yellow='\033[0;33m'; c_red='\033[0;31m'; c_off='\033[0m'
section(){ printf "\n${c_blue}==> %s${c_off}\n" "$1"; }
ok(){ printf "  ${c_green}✓${c_off} %s\n" "$1"; }
warn(){ printf "  ${c_yellow}!${c_off} %s\n" "$1"; }
err(){ printf "  ${c_red}✗${c_off} %s\n" "$1"; FAILED+=("$1"); }
have(){ command -v "$1" >/dev/null 2>&1; }
todo(){ TODO+=("$1"); }
# Run a command with root privileges: direct if already root (e.g. containers),
# via sudo otherwise. Avoids requiring sudo when none is installed.
as_root(){ if [ "$(id -u)" -eq 0 ]; then "$@"; elif command -v sudo >/dev/null 2>&1; then sudo "$@"; else warn "root needed for: $*"; return 1; fi; }

# ── OS detection ──────────────────────────────────────────────────
OS=""
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)
    if have apt-get; then OS="debian"; else
      printf "${c_red}Unsupported Linux (no apt). This script supports macOS and Debian/Ubuntu.${c_off}\n"; exit 1
    fi ;;
  *) printf "${c_red}Unsupported OS: $(uname -s)${c_off}\n"; exit 1 ;;
esac
section "Detected OS: $OS  |  repo: $REPO_DIR"

# back up a file once before overwriting (timestamped, only if it differs)
backup(){
  local f="$1"
  if [ -f "$f" ] && ! cmp -s "$f" "$2" 2>/dev/null; then
    cp "$f" "$f.bak-$(date +%Y%m%dT%H%M%S)" 2>/dev/null && warn "backed up existing $(basename "$f")"
  fi
}

# ════════════════════════════════════════════════════════════════════
# 1. Package manager + core packages
# ════════════════════════════════════════════════════════════════════
section "Package manager and core packages"
if [ "$OS" = "macos" ]; then
  if ! have brew; then
    warn "Homebrew not found — installing"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null || err "Homebrew install failed"
    # add brew to PATH for the rest of this run (Apple Silicon default)
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  have brew && ok "Homebrew present"
  for pkg in gh ripgrep fzf terraform terraform-docs kubectl helm jq; do
    brew list "$pkg" >/dev/null 2>&1 && ok "$pkg" || { brew install "$pkg" >/dev/null 2>&1 && ok "installed $pkg" || warn "skip $pkg"; }
  done
else
  as_root apt-get update -y >/dev/null 2>&1 && ok "apt updated"
  as_root apt-get install -y curl wget git build-essential unzip ripgrep fzf jq zsh >/dev/null 2>&1 && ok "base packages" || err "apt base packages"
  # gh
  if ! have gh; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | as_root dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null 2>&1
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | as_root tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    as_root apt-get update -y >/dev/null 2>&1 && as_root apt-get install -y gh >/dev/null 2>&1 && ok "gh" || warn "gh install"
  else ok "gh"; fi
  # terraform
  if ! have terraform; then
    wget -qO- https://apt.releases.hashicorp.com/gpg | as_root gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
    CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $CODENAME main" | as_root tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    as_root apt-get update -y >/dev/null 2>&1 && as_root apt-get install -y terraform >/dev/null 2>&1 && ok "terraform" || warn "terraform install"
  else ok "terraform"; fi
fi

# ════════════════════════════════════════════════════════════════════
# 2. Node.js 20
# ════════════════════════════════════════════════════════════════════
section "Node.js 20"
if [ "$OS" = "macos" ]; then
  brew list node@20 >/dev/null 2>&1 || brew install node@20 >/dev/null 2>&1
  export PATH="/opt/homebrew/opt/node@20/bin:$PATH"
  grep -q 'node@20/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="/opt/homebrew/opt/node@20/bin:$PATH"' >> ~/.zshrc
else
  if [ ! -d "$HOME/.nvm" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1
  fi
  export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 20 >/dev/null 2>&1 && nvm alias default 20 >/dev/null 2>&1
fi
have node && ok "node $(node --version)" || err "node not on PATH"

# ════════════════════════════════════════════════════════════════════
# 3. Bun (opencode plugin manager uses it)
# ════════════════════════════════════════════════════════════════════
section "Bun"
if ! have bun && [ ! -x "$HOME/.bun/bin/bun" ]; then
  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1
fi
export PATH="$HOME/.bun/bin:$PATH"
have bun && ok "bun $(bun --version 2>/dev/null)" || warn "bun not on PATH (restart shell)"

# ════════════════════════════════════════════════════════════════════
# 4. Cloud / infra CLIs (best-effort)
# ════════════════════════════════════════════════════════════════════
section "Cloud and infra CLIs"
# AWS CLI v2
if ! have aws; then
  if [ "$OS" = "macos" ]; then
    curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg && as_root installer -pkg /tmp/AWSCLIV2.pkg -target / >/dev/null 2>&1 && ok "aws cli" || warn "aws cli"
  else
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip && unzip -oq /tmp/awscliv2.zip -d /tmp && as_root /tmp/aws/install --update >/dev/null 2>&1 && ok "aws cli" || warn "aws cli"
  fi
else ok "aws cli"; fi
# kubectl (mac via brew above; linux direct)
if ! have kubectl && [ "$OS" = "debian" ]; then
  curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && as_root install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm -f kubectl && ok "kubectl" || warn "kubectl"
fi
have kubectl && ok "kubectl present" || warn "kubectl missing"
# helm (linux)
if ! have helm && [ "$OS" = "debian" ]; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null 2>&1 && ok "helm" || warn "helm"
fi
have gcloud || todo "Install gcloud SDK: https://cloud.google.com/sdk/docs/install  (then: gcloud auth login)"

# ════════════════════════════════════════════════════════════════════
# 5. zsh / oh-my-zsh
# ════════════════════════════════════════════════════════════════════
section "zsh / oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended >/dev/null 2>&1 && ok "oh-my-zsh" || warn "oh-my-zsh"
else ok "oh-my-zsh present"; fi
[ "$SHELL" = "$(command -v zsh)" ] || todo "Set zsh as default shell: chsh -s \"\$(command -v zsh)\"  (log out/in after)"

# ════════════════════════════════════════════════════════════════════
# 6. AI tools: Claude Code, opencode, pi, Codex CLI, Herdr, Engram
# ════════════════════════════════════════════════════════════════════
section "AI tools"
# Claude Code — CLI install + all ~/.claude assets live in install-claude.sh
# (single source of truth; teammates who only use Claude Code run it directly)
export PATH="$HOME/.local/bin:$PATH"
bash "$REPO_DIR/install-claude.sh" && ok "Claude Code setup (install-claude.sh)" || err "Claude Code setup (see install-claude.sh output above)"
# opencode
if ! have opencode; then
  if [ "$OS" = "macos" ]; then brew install anomalyco/tap/opencode >/dev/null 2>&1 && ok "opencode" || err "opencode";
  else curl -fsSL https://opencode.ai/install | bash >/dev/null 2>&1 && ok "opencode" || err "opencode"; fi
else ok "opencode present"; fi
# pi coding agent (npm; --ignore-scripts per pi's own install docs)
if ! have pi; then
  npm install -g --ignore-scripts @earendil-works/pi-coding-agent >/dev/null 2>&1 && ok "pi" || err "pi (npm install -g @earendil-works/pi-coding-agent)"
else ok "pi present ($(pi --version 2>/dev/null))"; fi
# Codex CLI (npm)
if ! have codex; then
  npm install -g @openai/codex >/dev/null 2>&1 && ok "codex" || warn "codex (npm install -g @openai/codex)"
else ok "codex present"; fi
# Herdr (official installer; package-manager installs update through that manager instead)
if ! have herdr; then
  curl -fsSL https://herdr.dev/install.sh | sh >/dev/null 2>&1 && ok "herdr" || warn "herdr (https://herdr.dev/docs/install/)"
else ok "herdr present ($(herdr --version 2>/dev/null))"; fi
# gentle-ai (configurator used only for pi here; the same tap ships Engram)
if ! have gentle-ai; then
  if have brew; then brew install gentleman-programming/tap/gentle-ai >/dev/null 2>&1 && ok "gentle-ai" || warn "gentle-ai";
  else warn "gentle-ai: no Homebrew here; the pi section prints the manual step"; fi
else ok "gentle-ai present"; fi
# Engram
if ! have engram; then
  if [ "$OS" = "macos" ]; then brew install gentleman-programming/tap/engram >/dev/null 2>&1 && ok "Engram" || warn "Engram";
  elif have brew; then brew install gentleman-programming/tap/engram >/dev/null 2>&1 && ok "Engram" || warn "Engram";
  else todo "Install Engram on Linux: https://github.com/Gentleman-Programming/engram (Homebrew tap or 'go install')"; fi
else ok "Engram present"; fi

# ════════════════════════════════════════════════════════════════════
# 7. Place vendored config / agents / skills / rules / hooks
# ════════════════════════════════════════════════════════════════════
section "Placing configs and assets"
mkdir -p "$HOME/.config/opencode/agents" "$HOME/.config/opencode/commands" "$HOME/.config/opencode/scripts" \
         "$HOME/.config/opencode/plugins" "$HOME/.agents/skills" "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/scripts" \
         "$HOME/.pi/agent/skills" "$HOME/.pi/gentle-ai" "$HOME/.codex"

# Claude Code assets already placed by install-claude.sh (AI tools section)

# opencode
backup "$HOME/.config/opencode/opencode.jsonc" "$REPO_DIR/config/opencode.jsonc"
sed "s#__HOME__#$HOME#g" "$REPO_DIR/config/opencode.jsonc" > "$HOME/.config/opencode/opencode.jsonc" && ok "opencode.jsonc (paths templatized)"
cp "$REPO_DIR/config/tui.json" "$HOME/.config/opencode/tui.json" && ok "opencode tui.json"
mkdir -p "$HOME/.opencode"
cp "$REPO_DIR/config/opencode-secondary.json" "$HOME/.opencode/opencode.json" && ok "opencode secondary config (.opencode/opencode.json, prevents drift)"
cp "$REPO_DIR/oh-my-openagent.json" "$HOME/.config/opencode/oh-my-openagent.json" && ok "oh-my-openagent.json"
cp "$REPO_DIR/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" && ok "opencode AGENTS.md"
cp "$REPO_DIR"/opencode-agents/*.md "$HOME/.config/opencode/agents/" && ok "opencode agents"
cp "$REPO_DIR"/opencode-commands/*.md "$HOME/.config/opencode/commands/" && ok "opencode commands"
cp "$REPO_DIR"/opencode-scripts/*.mjs "$HOME/.config/opencode/scripts/" && ok "opencode scripts (check-harness + harness-guards lib/tests)"
if ls "$REPO_DIR"/opencode-plugins/*.js >/dev/null 2>&1; then
  cp "$REPO_DIR"/opencode-plugins/*.js "$HOME/.config/opencode/plugins/" && ok "opencode plugins (harness-guards)"
fi

# Shared skills dir (~/.agents/skills): read by opencode, pi and the Claude Code symlinks
cp -R "$REPO_DIR"/agents-skills/* "$HOME/.agents/skills/" && ok "agents-skills → ~/.agents/skills (incl. webapp-testing/scripts)"
# webapp-testing must be a SYMLINK to the Claude Code copy (single source of
# truth; the harness checker enforces this topology)
if [ -f "$HOME/.claude/skills/webapp-testing/SKILL.md" ]; then
  ln -sf "$HOME/.claude/skills/webapp-testing/SKILL.md" "$HOME/.agents/skills/webapp-testing/SKILL.md"
  rm -rf "$HOME/.agents/skills/webapp-testing/scripts"
  ln -s "$HOME/.claude/skills/webapp-testing/scripts" "$HOME/.agents/skills/webapp-testing/scripts" 2>/dev/null
  ok "webapp-testing symlinked → ~/.claude/skills copy"
fi

# ── pi + gentle-pi ────────────────────────────────────────────────
# Policy mirrors opencode: NaN default at thinking low, Claude only on gentle-pi's
# review lenses (8k cap), harness-guards extension because pi has no permission layer.
# Order matters: gentle-pi install + `gentle-ai sync` first (they edit settings.json,
# mcp.json and skills), then the vendored files are placed so they are authoritative.
if have pi; then
  if ! [ -d "$HOME/.pi/agent/npm/node_modules/gentle-pi" ]; then
    (cd "$HOME" && pi install npm:gentle-pi </dev/null >/dev/null 2>&1) && ok "gentle-pi package" || warn "gentle-pi (run: pi install npm:gentle-pi)"
  else ok "gentle-pi package present"; fi
  if have gentle-ai; then
    if (cd "$HOME" && gentle-ai sync --agents pi </dev/null >/dev/null 2>&1); then
      ok "gentle-ai sync (pi only)"
      # gentle-ai writes its SDD skills into the SHARED ~/.agents/skills (opencode loads that dir too).
      # Every run: replace pi's copy with the fresh one and remove the shared source (list: pi/gentle-skills.txt).
      moved=0
      while read -r skill; do
        [ -n "$skill" ] && [ -d "$HOME/.agents/skills/$skill" ] || continue
        rm -rf "$HOME/.pi/agent/skills/$skill"
        mv "$HOME/.agents/skills/$skill" "$HOME/.pi/agent/skills/" && moved=$((moved + 1))
      done < "$REPO_DIR/pi/gentle-skills.txt"
      ok "gentle skills quarantined under ~/.pi/agent/skills ($moved moved)"
    else
      warn "gentle-ai sync --agents pi failed — skills left untouched; run it manually, then move the generated skills out of ~/.agents/skills"
    fi
  else
    todo "gentle-ai missing: install it (brew tap gentleman-programming/tap, or the Linux release from github.com/Gentleman-Programming/gentle-ai), then run: gentle-ai sync --agents pi"
  fi
  for f in models.json settings.json AGENTS.md mcp.json; do
    backup "$HOME/.pi/agent/$f" "$REPO_DIR/pi/$f"
    sed "s#__HOME__#$HOME#g" "$REPO_DIR/pi/$f" > "$HOME/.pi/agent/$f" && ok "pi $f"
  done
  cp "$REPO_DIR/pi/gentle-ai-models.json" "$HOME/.pi/gentle-ai/models.json" && ok "gentle-pi per-agent routing"
  cp "$REPO_DIR"/pi/extensions/*.ts "$HOME/.pi/agent/extensions/" && ok "pi extensions (harness-guards)"
  cp "$REPO_DIR"/pi/scripts/*.mjs "$HOME/.pi/agent/scripts/" && ok "pi scripts (check-pi-harness + guard tests)"
  # Skills pi should see but opencode should not: the herdr skill (dagr-producer is a shared-dir skill already)
  [ -d "$HOME/.claude/skills/herdr" ] && { mkdir -p "$HOME/.pi/agent/skills/herdr"; cp "$HOME/.claude/skills/herdr/SKILL.md" "$HOME/.pi/agent/skills/herdr/"; }
  todo "pi: store the Anthropic key with /login (API key) inside pi, or write ~/.pi/agent/auth.json (mode 600) — never in models.json"
else warn "pi not installed — pi configs not placed"; fi

# ── Codex CLI ──────────────────────────────────────────────────────
if [ -d "$HOME/.codex" ]; then
  backup "$HOME/.codex/AGENTS.md" "$REPO_DIR/codex/AGENTS.md"
  cp "$REPO_DIR/codex/AGENTS.md" "$HOME/.codex/AGENTS.md" && ok "codex AGENTS.md"
  if [ ! -f "$HOME/.codex/config.toml" ]; then
    sed "s#__HOME__#$HOME#g" "$REPO_DIR/codex/config.toml" > "$HOME/.codex/config.toml" && ok "codex config.toml (curated policy; codex adds marketplaces/projects itself)"
  else ok "codex config.toml present — deliberately not overwritten: Codex writes marketplace, trust and desktop state into it; apply codex/config.toml changes by hand (known non-converging step)"; fi
  backup "$HOME/.codex/hooks.json" "$REPO_DIR/codex/hooks.json"
  sed "s#__HOME__#$HOME#g" "$REPO_DIR/codex/hooks.json" > "$HOME/.codex/hooks.json" && ok "codex hooks.json (Herdr re-adds its SessionStart entry below)"
  todo "Codex: run 'codex login' (ChatGPT/OpenAI account); plugins in config.toml install on first launch"
fi

# ── Herdr: plugins + agent integrations (idempotent; each install checks its own state) ──
if have herdr; then
  if [ -f "$REPO_DIR/herdr/plugins.txt" ]; then
    while IFS=$'\t' read -r src commit plugin_id state _comment; do
      case "$src" in ''|'#'*) continue;; esac
      if herdr plugin install --ref "$commit" "$src" --yes </dev/null >/dev/null 2>&1; then ok "herdr plugin $src@${commit:0:8}"
      else warn "herdr plugin $src (run: herdr plugin install --ref $commit $src)"; fi
      if [ "$state" = "disabled" ]; then
        if herdr plugin disable "$plugin_id" >/dev/null 2>&1; then ok "herdr plugin $plugin_id disabled (as on the source machine)"
        else warn "herdr plugin disable $plugin_id"; fi
      fi
    done < "$REPO_DIR/herdr/plugins.txt"
  fi
  if [ -f "$REPO_DIR/herdr/integrations.txt" ]; then
    while read -r integ; do
      [ -n "$integ" ] || continue
      herdr integration install "$integ" </dev/null >/dev/null 2>&1 && ok "herdr integration $integ" || warn "herdr integration $integ"
    done < "$REPO_DIR/herdr/integrations.txt"
  fi
  # dagr binary on PATH for the dagr-producer skill (`dagr check`)
  for cand in "$HOME"/.config/herdr/plugins/github/herdr-dagr-*/bin/dagr; do
    if [ -x "$cand" ]; then ln -sfn "$cand" "$HOME/.local/bin/dagr" && ok "dagr → ~/.local/bin/dagr"; break; fi
  done
  todo "Herdr: run 'herdr' once to start the server; integrations report state only inside Herdr panes"
fi

# ════════════════════════════════════════════════════════════════════
# 8. Playwright (browser/E2E + vision)
# ════════════════════════════════════════════════════════════════════
section "Playwright (browser/E2E)"
if have pip3 || have pip; then
  PIP="$(command -v pip3 || command -v pip)"
  "$PIP" install --user --quiet playwright >/dev/null 2>&1 && python3 -m playwright install chromium >/dev/null 2>&1 && ok "python playwright + chromium" || warn "playwright (install manually: pip install playwright && python -m playwright install chromium)"
else
  todo "Install Playwright for E2E: pip install playwright && python -m playwright install chromium"
fi
ok "Playwright MCP auto-installs via opencode on first launch (npx @playwright/mcp)"

# ════════════════════════════════════════════════════════════════════
# 9. Validate the opencode harness
# ════════════════════════════════════════════════════════════════════
section "Validating harness"
if have node; then
  node "$HOME/.config/opencode/scripts/check-harness.mjs" >/dev/null 2>&1 && ok "opencode harness checker passed" || warn "opencode harness checker reported issues — run: node ~/.config/opencode/scripts/check-harness.mjs"
  if have pi && [ -f "$HOME/.pi/agent/scripts/check-pi-harness.mjs" ]; then
    node "$HOME/.pi/agent/scripts/check-pi-harness.mjs" >/dev/null 2>&1 && ok "pi harness checker passed" || err "pi harness checker failed — run: node ~/.pi/agent/scripts/check-pi-harness.mjs"
  fi
fi

# ── shell env reminders ───────────────────────────────────────────
grep -q 'HOME/.local/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
grep -q 'HOME/.bun/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.zshrc
grep -q 'KREW_ROOT' ~/.zshrc 2>/dev/null || echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.zshrc

# ════════════════════════════════════════════════════════════════════
# Manual TODO (cannot be automated)
# ════════════════════════════════════════════════════════════════════
todo "Export API keys in ~/.zshrc:  export NAN_API_KEY=\"sk-...\"   export NEW_RELIC_API_KEY=\"NRAK-...\""
todo "Anthropic key (pay-as-you-go review seats): ~/.local/share/opencode/auth.json for opencode and ~/.pi/agent/auth.json for pi, both mode 600 — never in a config file"
todo "Authenticate: gh auth login ;  aws configure (or awsume) ;  gcloud auth login"
todo "Launch opencode once so it auto-installs the oh-my-openagent plugin (needs NAN_API_KEY set)"
todo "Claude Code manual steps: see the install-claude.sh TODO list printed above (login, plugin trust prompts, optional vault clone)"

section "Done"
[ ${#FAILED[@]} -eq 0 ] && ok "core install completed with no hard failures" || { printf "${c_red}Failures:${c_off}\n"; for x in "${FAILED[@]}"; do echo "  - $x"; done; }
printf "\n${c_yellow}Manual steps remaining:${c_off}\n"
for x in "${TODO[@]}"; do echo "  • $x"; done
printf "\nReopen your shell (or 'source ~/.zshrc') to pick up PATH changes.\n"
