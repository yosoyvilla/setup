# Developer Setup Guide

Complete setup for a development workstation running **macOS, Debian/Ubuntu, or Fedora**: Claude Code, opencode CLI, the pi coding agent (gentle-pi), Codex CLI, Herdr, and all supporting tooling. Written to be followed top-to-bottom on a fresh machine.

> **For AI agents reading this:** This document describes a real, active setup. Every config block is accurate and production-tested. Follow sections in order — prerequisites before tools, tools before config. All agent and skill system prompts are LLM-agnostic — they work with Claude, GPT, Qwen, DeepSeek, or any capable model.

---

## Quick Start (automated)

On **macOS** or **Debian/Ubuntu**, the bundled installer does the whole setup — tools, Claude Code, opencode, pi + gentle-pi, Codex CLI, Herdr, Engram, Playwright, and every vendored config/agent/skill/rule/hook:

```bash
git clone git@github.com:yosoyvilla/setup.git && cd setup
./install.sh
```

`install.sh` is **idempotent** (safe to re-run) and **unattended** (never prompts, never writes secrets). It auto-detects the OS, backs up any existing configs before overwriting, templatizes machine-specific paths, validates the opencode harness at the end, and prints a **TODO list** of the handful of steps it cannot automate (API keys, `gh`/`aws`/`gcloud`/`codex` auth, the Anthropic key files for the review seats, launching opencode once to install the plugin). The sections below document every step the script performs, for manual setup, Fedora, or reference.

### Claude Code only (for teammates)

If you use **Claude Code and nothing else** from this stack, run the dedicated installer instead:

```bash
git clone git@github.com:yosoyvilla/setup.git && cd setup
./install-claude.sh
```

`install-claude.sh` installs the Claude Code CLI and places everything under `~/.claude` (CLAUDE.md, settings, 18 agents, skills with support scripts, rules, the auto-sync hook) — and touches **nothing else**: no opencode, no pi, no Herdr, no Engram, no extra tooling. Same guarantees as `install.sh` (idempotent, unattended, backups). `install.sh` delegates its Claude Code section to this script, so the logic exists once.

---

## Table of Contents

1. [AI Assistants — Architecture Overview](#1-ai-assistants--architecture-overview)
2. [Platform Notes](#2-platform-notes)
3. [System Prerequisites](#3-system-prerequisites)
4. [Shell Environment](#4-shell-environment)
   - [Terminal Enhancement Tools](#42-terminal-enhancement-tools)
5. [Claude Code](#5-claude-code)
   - [Installation](#51-installation)
   - [Global Config (CLAUDE.md)](#52-global-config-claudemd)
   - [Settings (hooks, plugins, model)](#53-settings-json)
   - [Agents](#54-agents)
   - [Skills](#55-skills)
   - [Rules](#56-rules)
   - [Hook Scripts (auto-sync)](#57-hook-scripts)
6. [opencode CLI](#6-opencode-cli)
   - [Installation](#61-installation)
   - [Main Config](#62-main-config-opencodejsonc)
   - [oh-my-openagent Config](#63-oh-my-openagent-config)
   - [TUI and Legacy Config](#64-tui-and-legacy-config)
   - [Verify Installation](#65-verify-installation)
   - [Shared AGENTS.md, Custom Agents, Commands](#66-shared-agentsmd-custom-agents-and-commands)
7. [pi coding agent + gentle-pi](#7-pi-coding-agent--gentle-pi)
   - [Installation](#71-installation)
   - [Config](#72-config)
   - [Guard extension and checker](#73-guard-extension-and-checker)
   - [gentle-pi](#74-gentle-pi)
8. [Engram (Persistent Memory)](#8-engram-persistent-memory)
9. [Obsidian Vault](#9-obsidian-vault)
10. [Environment Variables](#10-environment-variables)
11. [Projects Structure](#11-projects-structure)
12. [Quick Reference](#12-quick-reference)
13. [Post-Install Checklist](#13-post-install-checklist)
14. [Troubleshooting](#14-troubleshooting)
15. [Keeping the Repo in Sync](#15-keeping-the-repo-in-sync)
16. [Herdr](#16-herdr)
17. [Codex CLI](#17-codex-cli)

---

## 1. AI Assistants — Architecture Overview

This setup runs several independent AI coding tools. Each has its own config directory, agent format and tool system; agents and skills from one do **not** carry over to another, except for the shared skills directory `~/.agents/skills` that opencode and pi both read.

| Tool | Config | Agents | Default model | Auth |
|---|---|---|---|---|
| Claude Code (`claude`) | `~/.claude/` | `~/.claude/agents/*.md` | `claude-fable-5-1[1m]` | Anthropic account |
| opencode | `~/.config/opencode/` | oh-my-openagent + 21 custom agents | `nan/deepseek-v4-flash-low`; Claude on two review seats | `NAN_API_KEY` + Anthropic key in `auth.json` |
| pi + gentle-pi | `~/.pi/agent/`, `~/.pi/gentle-ai/` | gentle-pi packaged agents | `nan/deepseek-v4-flash` at thinking low; Claude on the review lenses | `NAN_API_KEY` + Anthropic key in `auth.json` |
| Codex CLI / Cursor CLI | `~/.codex/`, `~/.cursor/` | none (blind reviewers) | `gpt-5.6-sol` high / `auto` | `codex login` / `cursor-agent login` |
| Herdr | `~/.config/herdr/` | detects the agents above in its panes | — | — |

### Why several tools?

| Use case | Tool | Why |
|---|---|---|
| Structured DevOps workflows | Claude Code | Domain agents (infra, k8s, security…), skills, hooks, memory |
| Orchestrated NaN work, councils, verify pipeline | opencode | oh-my-openagent + custom `/council`, `/verify`, `/best-of` commands; Claude only on two review seats |
| Cheaper NaN sessions, gentle-pi ODD/SDD workflow | pi | Native per-model effort; ~6k-token system prompt vs opencode's ~90k on Claude calls |
| Blind adversarial reviews from other model families | Codex CLI, Cursor CLI | Reviewers that never see the implementer's reasoning |
| Running all of the above side by side | Herdr | Persistent panes, agent state in a sidebar, CLI to start/prompt/wait on agents |

Zed was part of this setup until 2026-09-21 and was removed (uninstalled on the live machine, sections retired here).

### Agent systems compared

| Concept | Claude Code | opencode (oh-my-openagent) | pi (gentle-pi) |
|---|---|---|---|
| Config location | `~/.claude/agents/*.md` | `~/.config/opencode/{oh-my-openagent.json,agents/*.md}` | `~/.pi/agent/*.json`, `~/.pi/gentle-ai/models.json` |
| Domain agents | 18 custom agents (infra, k8s, gcp, doc-reviewer…) | 21 custom agents (11 domain, 6 advisory/lead, 4 review seats) | gentle-pi's packaged agents (explore/worker/verify, review lenses, SDD) |
| Orchestrator | `lead` agent (Claude Opus) | Sisyphus on `nan/deepseek-v4-flash-low` | the session itself on `nan/deepseek-v4-flash` at thinking low |
| Plan review | `plan-critic` agent | `@plan-critic` (Claude Opus 5, effort low, 8k cap) | gentle-pi native review (reliability/risk/resilience/readability lenses) |
| Adversarial review | `code-quality` agent | `@critic` (Claude Sonnet 5, effort low, 8k cap) + `@thermo-nuclear-review` (NaN) | review lenses on Claude Sonnet 5, effort low, 8k cap |
| Fact checking | — | `@fact-checker` on `nan/glm5.3-flash-high` | — |
| Everything else | sonnet / haiku aliases | `nan/deepseek-v4-flash-low`, fallback `nan/glm5.3-flash-low` | `nan/deepseek-v4-flash` low |
| Enforcement | hooks (`destructive-guard.sh` etc.) | permissions + `harness-guards.js` plugin + `check-harness.mjs` | `harness-guards.ts` extension + `check-pi-harness.mjs` (pi has no permission layer) |

### Key distinction for agents and skills in this repo

The files in `agents/` and `skills/` are **Claude Code files only** — they use Claude Code's tool names and agent system, and opencode cannot load or run them. The repo also vendors opencode-specific assets (`opencode-agents/`, `opencode-commands/`), the shared skills directory (`agents-skills/`, i.e. `~/.agents/skills`), pi (`pi/`), Codex (`codex/`), Herdr manifests (`herdr/`), and a tool-agnostic `AGENTS.md`.

When you set up a new machine:
- `agents/*.md` → copy to `~/.claude/agents/` (Claude Code)
- `skills/<name>/` → copy to `~/.claude/skills/<name>/` (Claude Code; folders with `SKILL.md` plus support scripts such as `webapp-testing/scripts/with_server.py`)
- `hooks/*` → copy to `~/.claude/hooks/` (Claude Code; see Section 5.7)
- `oh-my-openagent.json` → `~/.config/opencode/oh-my-openagent.json` (opencode; vendored file, see Section 6.3)
- `opencode-agents/*.md` → `~/.config/opencode/agents/`, `opencode-commands/*.md` → `~/.config/opencode/commands/` (opencode; see Section 6.6)
- `opencode-scripts/*.mjs` → `~/.config/opencode/scripts/` (harness checker + harness-guards lib and tests; see Section 6.7)
- `opencode-plugins/*.js` → `~/.config/opencode/plugins/` (harness-guards enforcement plugin)
- `AGENTS.md` → `~/.config/opencode/AGENTS.md` (see Section 6.6); pi has its own `pi/AGENTS.md`
- `rules/*.md` → `~/.claude/rules/` (Claude Code shared rules: terraform, kubernetes, security-baseline, go)
- `agents-skills/*` → copy to `~/.agents/skills/` (shared skills read by opencode and pi, incl. `webapp-testing/scripts/with_server.py`)
- `pi/*` → `~/.pi/agent/` and `~/.pi/gentle-ai/models.json` (Section 7); `codex/*` → `~/.codex/` (Section 17); `herdr/*.txt` → consumed by `herdr plugin install` / `herdr integration install` (Section 16)
- `config/*` → the machine configs `install.sh` places (CLAUDE.md, claude-settings.json, claude-settings.local.json, opencode.jsonc, opencode-secondary.json, tui.json); machine-specific paths use the `__HOME__` token resolved at install time

Or just run `./install.sh` (Quick Start) to do all of the above automatically — or `./install-claude.sh` for the Claude Code items only.

---

## 2. Platform Notes

This guide supports three platforms. Commands that differ per OS are shown with tabs. Commands that are identical across platforms are shown once.

| Platform | Package Manager | Shell | Notes |
|---|---|---|---|
| macOS | Homebrew | zsh (default) | M1/M2/M3 ARM or Intel |
| Debian/Ubuntu | apt | zsh (install it) | 22.04+ / Debian 12+ |
| Fedora | dnf | zsh (install it) | Fedora 38+ |

> **Windows:** Not supported. Use WSL2 + Ubuntu if you must.

---

## 3. System Prerequisites

### 3.1 Package Manager

**macOS:**
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# After install, follow the "Next steps" in the output to add brew to PATH
```

**Debian/Ubuntu:**
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git build-essential
```

**Fedora:**
```bash
sudo dnf update -y
sudo dnf install -y curl wget git gcc gcc-c++ make
```

### 3.2 Core Packages

**macOS:**
```bash
brew install gh ripgrep fzf terraform terraform-docs
brew install --cask ghostty
# opencode (anomalyco build) — see Section 6.1
brew install anomalyco/tap/opencode
# Engram persistent memory (third-party tap) — see Section 8.
# The same tap also ships gentle-ai.
brew install gentleman-programming/tap/engram
brew install gentleman-programming/tap/gentle-ai   # configures gentle-pi (Section 7.4)
# pi coding agent, Codex CLI, Herdr — see Sections 7, 17, 16
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
npm install -g @openai/codex
curl -fsSL https://herdr.dev/install.sh | sh
```

**Debian/Ubuntu:**
```bash
# GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt update && sudo apt install gh -y

# Core tools
sudo apt install -y ripgrep fzf

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform -y

# pi coding agent, Codex CLI, Herdr — see Sections 7, 17, 16
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
npm install -g @openai/codex
curl -fsSL https://herdr.dev/install.sh | sh
```

**Fedora:**
```bash
# GitHub CLI
sudo dnf install -y 'dnf-command(config-manager)'
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install -y gh

# Core tools
sudo dnf install -y ripgrep fzf

# Terraform
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install -y terraform

# pi coding agent, Codex CLI, Herdr — see Sections 7, 17, 16
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
npm install -g @openai/codex
curl -fsSL https://herdr.dev/install.sh | sh
```

### 3.3 Node.js 22 (required by pi; opencode and Claude Code run on it too)

**macOS:**
```bash
brew install node@22
echo 'export PATH="/opt/homebrew/opt/node@22/bin:$PATH"' >> ~/.zshrc
```

**Debian/Ubuntu / Fedora:**
```bash
# Use nvm for version locking
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.zshrc  # or restart terminal
nvm install 22
nvm use 22
nvm alias default 22
```

Verify:
```bash
node --version  # should be v22.x.x (pi needs >= 22.19)
npm --version   # should be 10.x.x
```

### 3.4 Cloud and Infra CLIs

**AWS CLI v2:**

macOS:
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
```

Debian/Ubuntu:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
```

Fedora:
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip -d /tmp && sudo /tmp/aws/install
```

**kubectl + krew:**

macOS:
```bash
brew install kubectl krew
```

Debian/Ubuntu / Fedora:
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# krew
KREW_ROOT="$HOME/.krew"
OS="$(uname | tr '[:upper:]' '[:lower:]')" ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm.*$/arm/')"
curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-${OS}_${ARCH}.tar.gz"
tar zxvf "krew-${OS}_${ARCH}.tar.gz" && ./krew-${OS}_${ARCH} install krew
```

After krew install, add to `~/.zshrc`:
```zsh
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
```

Install krew plugins:
```bash
kubectl krew install ctx ns
```

**Helm:**

macOS: `brew install helm`

Debian/Ubuntu / Fedora:
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**gcloud:**

All platforms (manual install recommended over package manager for cleaner updates):
```bash
# Download and install to ~/Documents/google-cloud-sdk
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
# (use the darwin arm64 / linux x86_64 version matching your platform)
tar -xf google-cloud-cli-*.tar.gz -C ~/Documents/
~/Documents/google-cloud-sdk/install.sh
```

### 3.5 Bun (required for oh-my-openagent)

All platforms:
```bash
curl -fsSL https://bun.sh/install | bash
# Adds ~/.bun/bin to PATH via ~/.zshrc automatically
```

### 3.6 zsh and oh-my-zsh

macOS: zsh is already the default shell.

Debian/Ubuntu:
```bash
sudo apt install -y zsh
chsh -s $(which zsh)  # set as default (log out and back in)
```

Fedora:
```bash
sudo dnf install -y zsh
chsh -s $(which zsh)
```

All platforms — install oh-my-zsh:
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

zsh-syntax-highlighting:

macOS: `brew install zsh-syntax-highlighting`

Debian/Ubuntu: `sudo apt install -y zsh-syntax-highlighting`

Fedora: `sudo dnf install -y zsh-syntax-highlighting`

### 3.7 Fonts (optional but recommended)

macOS:
```bash
brew install --cask font-ubuntu-mono-nerd-font font-ubuntu-nerd-font
```

Debian/Ubuntu / Fedora — download from https://www.nerdfonts.com/font-downloads (Ubuntu Mono Nerd Font), extract to `~/.local/share/fonts/`, then run `fc-cache -fv`.

---

## 4. Shell Environment

File: `~/.zshrc`

The base template below works on all platforms. Platform-specific paths are noted inline.

```zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"  # or your preferred theme
source $ZSH/oh-my-zsh.sh

# ── Node ──────────────────────────────────────────────────────────
# macOS (homebrew node@22):
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
# Linux (nvm): already configured by nvm installer, or:
# export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# ── Krew (kubectl plugins) ────────────────────────────────────────
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# ── gcloud ────────────────────────────────────────────────────────
export PATH="$PATH:$HOME/Documents/google-cloud-sdk/bin"

# ── Bun ───────────────────────────────────────────────────────────
export PATH="$HOME/.bun/bin:$PATH"

# ── Local bins ────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ── HashiCorp Vault ───────────────────────────────────────────────
export VAULT_ADDR="https://vault.example.com"

# ── Aliases ───────────────────────────────────────────────────────
alias k=kubectl
alias kubectl="kubecolor"   # brew/apt/dnf install kubecolor
alias awsume=". awsume"
alias python=python3
alias pip=pip3

# ── Syntax highlighting ───────────────────────────────────────────
# macOS:
# source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# Debian/Ubuntu:
# source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# Fedora:
# source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ── Catppuccin theme for syntax highlighting ──────────────────────
source ~/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh 2>/dev/null || true

# ── API Keys (see Section 8) ──────────────────────────────────────
export NAN_API_KEY="sk-..."
export NEW_RELIC_API_KEY="NRAK-..."
```

Install Catppuccin syntax highlighting theme:
```bash
mkdir -p ~/.zsh
curl -o ~/.zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh \
  https://raw.githubusercontent.com/catppuccin/zsh-syntax-highlighting/main/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh
```

### 4.2 Terminal Enhancement Tools

**What this gives you:** fuzzy search wired into every tab completion, syntax-highlighted file output, smarter `cd` that remembers where you go, searchable shell history with a full UI, and better `ls`/`diff`/`git` output.

**Tools at a glance:**

| Tool | Replaces | What it does |
|------|----------|-------------|
| `fzf` | nothing (adds) | Fuzzy finder — press CTRL-R, CTRL-T, or Tab and get an interactive picker |
| `fzf-tab` | default tab completion | Wires fzf into zsh Tab key — all completions (files, commands, git branches, kubectl pods…) go through fzf |
| `bat` | `cat` | Shows file contents with syntax highlighting and line numbers |
| `fd` | `find` | Faster file search, respects `.gitignore` |
| `rg` (ripgrep) | `grep` | Faster code search, respects `.gitignore` |
| `eza` | `ls` | File listing with icons, git status, tree mode |
| `delta` | raw git diff | Git diffs with syntax highlighting and side-by-side mode |
| `zoxide` | `cd` | Smart `cd` — learns your most-visited dirs, jump with `z partial-name` |
| `atuin` | CTRL-R history | Full-text shell history search with a TUI, optional cloud sync |

---

#### Step 1 — Install tools

**macOS:**
```bash
brew install fzf bat fd ripgrep eza delta zoxide atuin
brew install zsh-autosuggestions zsh-syntax-highlighting
```

**Debian / Ubuntu:**
```bash
sudo apt update && sudo apt install -y fzf bat fd-find ripgrep
# Note: fd is named "fdfind" on Ubuntu — add alias below in Step 4
# eza, delta, zoxide, atuin are not in apt (install via cargo or install scripts):
cargo install eza                   # Ubuntu 24.04+: sudo apt install eza
cargo install git-delta             # the binary is called "delta"
curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
# zsh plugins:
sudo apt install -y zsh-autosuggestions zsh-syntax-highlighting
```

**Fedora:**
```bash
sudo dnf install -y fzf bat fd-find ripgrep
cargo install eza git-delta
curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
sudo dnf install -y zsh-autosuggestions zsh-syntax-highlighting
```

**Install Rust/cargo** (needed for eza, delta on Linux if not already present):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
```

---

#### Step 2 — Install fzf-tab (oh-my-zsh plugin)

`fzf-tab` replaces the default zsh tab completion with an fzf picker. This is what makes pressing Tab open an interactive fuzzy menu for files, git branches, kubectl resources, etc.

```bash
git clone https://github.com/Aloxaf/fzf-tab \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab
```

If you don't use oh-my-zsh, add this to `~/.zshrc` after `compinit`:
```bash
# Manual fzf-tab (no oh-my-zsh):
source ~/path/to/fzf-tab/fzf-tab.plugin.zsh
```

---

#### Step 3 — Update oh-my-zsh plugins list

**Order matters.** `fzf-tab` must come before `zsh-autosuggestions`. `zsh-syntax-highlighting` must be last.

In `~/.zshrc`, find the `plugins=(...)` line and replace it:

```zsh
plugins=(
  git
  colored-man-pages
  colorize
  kubectl
  fzf-tab               # tab completion via fzf — must be before zsh-autosuggestions
  zsh-autosuggestions   # fish-like inline command suggestions
  zsh-syntax-highlighting  # command highlighting — must be last
)

# macOS: add these two:
# brew macos
```

> **For AI agents:** The `brew` and `macos` plugins are macOS-only. On Linux, remove them or they cause errors. `fzf-tab` must always precede `zsh-autosuggestions` in this list — reversing the order breaks suggestion display.

---

#### Step 4 — Add to `~/.zshrc` (after `source $ZSH/oh-my-zsh.sh`)

Paste this block at the end of `~/.zshrc`, after the `source $ZSH/oh-my-zsh.sh` line:

```zsh
# ── fzf shell integration ────────────────────────────────────────────
# Enables CTRL-R (history), CTRL-T (file picker), ALT-C (dir picker)
# Run: fzf --version → if 0.48+, use eval form. If older, use the source form.
eval "$(fzf --zsh)"
# Fallback for older fzf installed via brew's install script:
# [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Use ripgrep as fzf's file source (fast, respects .gitignore)
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git"'

# fzf appearance and behavior
export FZF_DEFAULT_OPTS="
  --layout=reverse
  --height=50%
  --preview 'bat --color=always --style=numbers --line-range=:100 {}'
  --preview-window=right:50%:hidden
  --bind 'ctrl-/:toggle-preview'
"
# macOS: add clipboard copy binding
# --bind 'ctrl-y:execute-silent(echo -n {} | pbcopy)'

# Directory picker shows a tree preview
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -100'"

# History search: no preview panel needed
export FZF_CTRL_R_OPTS="--preview-window=hidden"

# fzf-tab: show file previews in tab completions too
zstyle ':fzf-tab:complete:*' fzf-preview 'bat --color=always --line-range=:50 $realpath 2>/dev/null || eza --color=always $realpath 2>/dev/null'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --tree --color=always $realpath | head -50'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps --pid=$word -o cmd --no-header -w -w'

# ── bat (better cat — syntax highlighting) ──────────────────────────
export BAT_THEME="Catppuccin Mocha"
alias cat='bat --paging=never'    # drop-in cat replacement
alias catp='bat'                  # cat with paging

# ── eza (better ls — icons, git status, tree) ───────────────────────
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first --git'
alias lt='eza --tree --icons -L 2'
alias la='eza -la --icons'

# ── fd (better find — respects .gitignore) ──────────────────────────
# Ubuntu/Fedora: fd is installed as "fdfind", alias it:
# alias fd=fdfind

# ── zoxide (smart cd — learns most-visited dirs) ─────────────────────
eval "$(zoxide init zsh)"
# Usage: z foo     → jumps to best matching dir containing "foo"
#        zi        → interactive picker for all visited dirs

# ── atuin (searchable shell history with TUI) ────────────────────────
# CTRL-R opens atuin's search UI (overrides fzf's CTRL-R binding)
# First time: run `atuin register` to enable sync, or skip for local-only
eval "$(atuin init zsh)"

# ── delta (better git diff — configured in ~/.gitconfig) ────────────
# See Step 5 below — no code needed here, gitconfig handles it
```

---

#### Step 5 — Configure delta in `~/.gitconfig`

Delta replaces git's pager for all `git diff`, `git log -p`, `git show`, and interactive add output.

```ini
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true        # n/N to jump between diff sections
    side-by-side = true    # two-column diff view
    line-numbers = true
    syntax-theme = Catppuccin Mocha
```

Apply with:
```bash
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.side-by-side true
git config --global delta.line-numbers true
git config --global delta.syntax-theme "Catppuccin Mocha"
```

---

#### Step 6 — Verify

Run these to confirm everything works:

```bash
fzf --version                  # should be 0.48+
bat --version
fd --version                   # or: fdfind --version on Ubuntu
rg --version
eza --version
delta --version
zoxide --version
atuin --version

# Test fzf integration:
# Press CTRL-R in terminal  → atuin history search UI
# Press CTRL-T              → fzf file picker
# Press ALT-C               → fzf directory picker
# Press Tab after a command → fzf tab completion (fzf-tab)
# Type: z doc<Tab>          → jumps to ~/Documents (after visiting it once)
```

---

#### Complete Tool Reference

| Tool | Key binding / command | What happens |
|------|----------------------|-------------|
| `fzf` | CTRL-T | Fuzzy file picker — inserts selected path at cursor |
| `fzf` | ALT-C | Fuzzy dir picker — `cd`s into selected directory |
| `atuin` | CTRL-R | Full-text history search with TUI (replaces fzf CTRL-R) |
| `fzf-tab` | Tab | All tab completions go through fzf picker |
| `bat` | `cat <file>` | Syntax-highlighted file output with line numbers |
| `fd` | `fd pattern` | Find files matching pattern, ignoring `.gitignore` |
| `rg` | `rg 'pattern'` | Grep across code, ignoring `.gitignore` |
| `eza` | `ls`, `ll`, `lt` | File listing with icons, git status, tree view |
| `delta` | `git diff`, `git log -p` | Syntax-highlighted side-by-side diffs |
| `zoxide` | `z partial-name` | Jump to most-visited dir matching name |
| `zoxide` | `zi` | Interactive picker for all visited directories |

---

## 5. Claude Code

Claude Code is Anthropic's CLI assistant. It uses a multi-agent architecture where domain-specific agents handle specialized tasks.

> **Model note:** The `model: sonnet`, `model: haiku`, `model: opus` fields in agent frontmatter are Claude Code aliases for Claude model tiers. The agent system prompts themselves are LLM-agnostic — they contain only role descriptions and constraints, with no Claude-specific behaviors or syntax.

### 5.1 Installation

Native installer (recommended — standalone binary to `~/.local/bin`, auto-updates; macOS/Linux/WSL):
```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Alternative — Homebrew (`brew install --cask claude-code`) or npm (requires Node 18+; installs the same native binary):
```bash
npm install -g @anthropic-ai/claude-code
```

> Source: [Claude Code setup](https://code.claude.com/docs/en/setup). Ensure `~/.local/bin` is on your `PATH` (Section 4).

Authenticate:
```bash
claude
# Follow the OAuth flow in your browser
```

### 5.2 Global Config (`CLAUDE.md`)

File: `~/.claude/CLAUDE.md`

```markdown
# Global Rules
> Obsidian: ~/Documents/obsidian-vault/claude-code/global-rules.md

## Accuracy and Verification
- Double check answers. 95%+ confidence required. Verify against official docs. Do not guess.
- Double check changes won't break existing functionality. 95%+ confidence. Investigate first when unsure.

## Git Commits
- Single-line commit messages. No co-author. No emojis.

## Documentation
- No emojis in documentation.
- Never create markdown files without explicit user approval. Always ask first.

## Testing
- Run tests after every change. If no test suite exists, verify manually or suggest how to test.

## Communication
- Explain what you are doing and why before and during execution. User must always know what is happening.
- Before implementing any non-trivial change (editing >1 file, or any infrastructure/config change), use the **`spec-driven-development`** skill to write a spec in the conversation. The spec must define: what you're building, the chosen approach vs alternatives, acceptance criteria (specific and testable), and a rollback plan for infra/deployment changes. Implementation starts only after the spec is written. No exceptions.
- Use `★ Insight` blocks for key technical insights specific to the codebase or decision being made.

## Engineering Standards (Staff/Principal)
- SOLID: Apply pragmatically, not dogmatically.
- KISS: Simplest solution that works. No premature abstraction.
- DRY: Extract at 3+ repetitions only. Premature DRY is worse than repetition.
- Clean code: Meaningful names, small functions, no dead code, no commented-out code.
- Fail fast: Validate at boundaries, return early, max 3 levels nesting.
- Immutability by default. Mutate only when necessary.
- Tests: Unit for logic, integration for boundaries, skip trivial code.
- Changes must be reviewable in under 15 minutes. Split large changes.

## Agent Routing (Smart)
Route tasks to the right tier. Not everything needs an agent.

### Tier 1: Main conversation (no agent)
Simple tasks, quick fixes, single-file edits, questions, exploration. Handle directly.

### Plan Review (Mandatory)
After writing ANY multi-step implementation plan (3+ steps or touching multiple systems), ALWAYS invoke the **plan-critic** agent before presenting the plan to the user for approval. Never skip this step. The plan-critic verifies documentation, identifies risks, and confirms the approach is sound.

The workflow is always: write plan → invoke plan-critic → present plan + critique to user → user approves → execute.

### Tier 2: Direct to domain agent (skip lead)
Single-domain tasks where the domain is obvious. Route directly:
- Terraform/cloud provisioning -> **infra** (sonnet)
- K8s/Helm/ArgoCD workloads -> **k8s** (sonnet)
- VPC/DNS/LB/VPN/Traefik/peering -> **networking** (sonnet)
- Pipeline security, scanning, OPA policies -> **devsecops** (sonnet)
- Pipeline/CI structure -> **cicd** (sonnet)
- Query tuning/migrations -> **database** (sonnet)
- NRQL/alerts/SLOs -> **observability** (sonnet)
- UI/UX design, frontend styling -> **design** (sonnet, Playwright verification)
- Code review request -> **code-quality** (haiku, advisory)
- Security audit/review -> **security** (haiku, advisory)
- Active AWS security incident, WAF attack, DDoS, GuardDuty finding, CloudTrail forensics -> **aws-incident** (sonnet)
- AWS/GCP/Kubecost cost analysis, savings, rightsizing -> **cost** (haiku, advisory)
- Shopify Functions, Admin API, theme, app extensions -> **shopify** (sonnet)
- Airbyte connector config, sync debugging, namespace issues -> **airbyte** (sonnet)
- GKE, GCP IAM, Cloud SQL, Artifact Registry, Secret Manager, Terragrunt -> **gcp** (sonnet)
- Reviewing/critiquing any implementation plan before execution -> **plan-critic** (sonnet, mandatory)
- Reviewing any documentation we create/edit (Confluence, READMEs, runbooks, guides) for multi-audience readability, official-doc accuracy (>95% confidence), and copy/format/special-character issues -> **doc-reviewer** (sonnet, advisory)

### Tier 3: Lead agent first (multi-domain/complex)
Use **lead** (opus) ONLY when: task spans 2+ domains, scope is unclear, touches production, or requires architecture decisions.

### Shared Context
Agents share state via `.claude/agent-context/` (relative to CWD, per-project). Before starting, agents read `lead.md` for the plan and any relevant `<agent>.md` files. After completing work, agents write findings to their own context file. Overwrite with current info; do not append indefinitely. All agents have persistent memory (`memory: user`) -- they learn patterns across sessions automatically.

### Agent Context File Schema
When agents write to `.claude/agent-context/<agent>.md`, they MUST use this structure:

```
## Summary
[What was accomplished — one sentence]
## Done
- [completed item]
## In Progress
- [item currently being worked on]
## Blocked
- [blocking issue and what's needed to unblock]
## Next Steps
- [next action when resuming]
```

### Progress Files for Long-Running Work
For tasks spanning multiple sessions (large migrations, multi-PR features), create a `claude-progress.json` at the repo root. JSON format preferred over Markdown — more resistant to accidental model edits. Session start sequence: read git history → read progress file → run smoke tests → pick next item.

### Multi-Project Structure
Projects live in `~/Documents/` with per-project `.claude/CLAUDE.md` files:
- `project-b/` - Real estate portals (portal-1, portal-2, portal-3, portal-4)
- `project-c/` - E-commerce (Shopify, warehousing, infra)
- `project-d/` - FinTech/payments
- `project-a/` - EdTech (EKS, Terraform, large infra)
- `Personal/` - Side projects (Crewgent, etc.)

Shared rules: `~/.claude/rules/` (terraform, kubernetes, security-baseline).

## Obsidian Knowledge Base (Source of Truth)
The canonical documentation for this entire Claude Code setup lives in `~/Documents/obsidian-vault/` (Git: yosoyvilla/obsidian-vault).
- Reference: @~/Documents/obsidian-vault/claude-code/setup.md
- IMPORTANT: When modifying agents, skills, hooks, rules, plugins, or settings, ALWAYS update the corresponding obsidian vault file AND commit+push the changes.
- The vault documents: agent routing, plugin list, hooks, skills, security, project tech stacks, workflows, and tips.

## Token Management
- Use `/clear` between unrelated tasks. Stale context burns tokens.
- Use `/compact` when context grows large but you need to continue the same task.
- Prefer CLI tools (aws, kubectl, gh, gcloud, sentry-cli) over MCP servers. MCP tools add persistent overhead to context even when idle.
- Model selection: haiku for simple lookups/formatting, sonnet for implementation, opus only for architecture and planning.
- Keep agent prompts lean. If an agent's instructions exceed 100 lines, move detail into skills.
- Before ending a complex session, write a brief checkpoint to the project's auto-memory: what was done, what's open, next steps.

## Compact Instructions
When compacting, preserve: current plan from lead agent, file paths modified, test results, open issues, and next steps. Discard: verbose command outputs, intermediate exploration, and completed steps that need no follow-up.

## Auto-Learning
- Agents save learnings via `memory: user`. Do not duplicate what's already in project MEMORY.md.
- Keep MEMORY.md under 200 lines (only first 200 lines are auto-loaded). Use topic files for detail.
- Save: confirmed patterns, architecture decisions, gotchas, access procedures. Skip: session-specific state, speculative conclusions.
```

### 5.3 Settings JSON

File: `~/.claude/settings.json`

> **Platform note:** The `Notification` hook uses `osascript` (macOS only). On Linux, replace with `notify-send "Claude Code" "Needs your attention"` (requires `libnotify-bin` on Debian/Ubuntu or `libnotify` on Fedora).

```json
{
  "cleanupPeriodDays": 90,
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "model": "opus[1m]",
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/auto-sync.sh",
            "statusMessage": "Syncing memory to Obsidian...",
            "async": true
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/user/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/user/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/auto-sync.sh",
            "statusMessage": "Post-compact memory sync...",
            "async": true
          }
        ]
      }
    ],
    "WorktreeCreate": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -c '{ts: (now | todate), event: \"WorktreeCreate\", path: .worktree_path, branch: .branch}' >> ~/.claude/worktree.log 2>/dev/null; exit 0",
            "async": true
          }
        ]
      }
    ],
    "WorktreeRemove": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -c '{ts: (now | todate), event: \"WorktreeRemove\", path: .worktree_path}' >> ~/.claude/worktree.log 2>/dev/null; exit 0",
            "async": true
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"Knowledge base: ~/Documents/obsidian-vault/ (sync: yosoyvilla/obsidian-vault)\" && echo \"When modifying Claude Code config (agents/skills/hooks/rules/plugins), update the vault and push.\" && if [ -f .claude/agent-context/lead.md ]; then echo \"Active lead plan:\" && head -5 .claude/agent-context/lead.md; fi"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "osascript -e 'display notification \"Claude Code needs your attention\" with title \"Claude Code\"'"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ]; then case \"$FILE\" in *.env|*.env.*|*terraform.tfstate*|*secrets/*|*.pem|*.key) echo \"BLOCKED: Protected file $FILE\" >&2; exit 2;; esac; fi; exit 0"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // \"\"' 2>/dev/null); if echo \"$CMD\" | grep -qE '(--profile[[:space:]]+(vtpr|bipr|lppr)|awsume[[:space:]]+(vtpr|bipr|lppr)|profile=(vtpr|bipr|lppr))' && echo \"$CMD\" | grep -qiE '\\b(delete|terminate|remove|purge|destroy|disable|deregister|drop|truncate)\\b'; then jq -n '{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"additionalContext\": \"PROD SAFETY: This command targets a production AWS account (vtpr/bipr/lppr) and contains a destructive operation. Confirm this is intentional before proceeding.\"}}'; fi; exit 0"
          }
        ]
      },
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/user/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/user/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(cat | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE\" ] && [[ \"$FILE\" == *.tf ]]; then terraform fmt \"$FILE\" 2>/dev/null; fi; exit 0"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "cat | jq -c '{ts: (now | todate), cmd: .tool_input.command, cwd: .cwd}' >> ~/.claude/command-audit.log 2>/dev/null; exit 0"
          }
        ]
      },
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/user/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/user/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/user/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/user/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/user/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/user/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/user/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/user/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "if [ -x '/Users/user/.orca/agent-hooks/claude-hook.sh' ]; then /bin/sh '/Users/user/.orca/agent-hooks/claude-hook.sh'; fi"
          }
        ]
      }
    ]
  },
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true,
    "context7@claude-plugins-official": true,
    "superpowers@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "ralph-loop@claude-plugins-official": true,
    "playwright@claude-plugins-official": true,
    "security-guidance@claude-plugins-official": true,
    "claude-md-management@claude-plugins-official": true,
    "explanatory-output-style@claude-plugins-official": true,
    "learning-output-style@claude-plugins-official": true,
    "typescript-lsp@claude-plugins-official": true,
    "pyright-lsp@claude-plugins-official": true,
    "github@claude-plugins-official": true,
    "commit-commands@claude-plugins-official": true,
    "gopls-lsp@claude-plugins-official": true,
    "php-lsp@claude-plugins-official": true
  },
  "autoDreamEnabled": true,
  "skipWorkflowUsageWarning": true,
  "agentPushNotifEnabled": true,
  "skipAutoPermissionPrompt": true
}
```

> **orca hooks:** The `/Users/user/.orca/agent-hooks/claude-hook.sh` entries that appear across the Stop, PreToolUse, PostToolUse, UserPromptSubmit, StopFailure, PostToolUseFailure, and PermissionRequest events belong to orca, an external/optional tool installed separately (not part of this repo) — each invocation is guarded by an `[ -x ... ]` check, so if orca is not installed the hook is a no-op.

> **`opus[1m]` model:** Claude Code model selector — Opus with the 1M-token context window. The `[1m]` suffix requests the long-context variant.

### 5.4 Agents

Agents live in `~/.claude/agents/`. Each is a Markdown file with YAML frontmatter. The frontmatter fields (`model`, `tools`, `maxTurns`) are Claude Code concepts; the system prompt body is plain text that works with any capable LLM.

```bash
mkdir -p ~/.claude/agents
```

---

#### `lead.md` — Principal Tech Lead
```markdown
---
name: lead
description: Staff/Principal DevOps Tech Lead. Use ONLY for tasks spanning multiple domains, requiring architecture decisions, touching production, or with unclear scope. Do NOT use for single-domain tasks.
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Write
model: opus
---

You are a Staff/Principal DevOps Engineer and Tech Lead. Your role is to plan and delegate, not implement.

When given a task:
1. Assess scope — does it span multiple domains? If single-domain, recommend the right agent instead.
2. Break into discrete subtasks with clear ownership per agent.
3. Write the plan to `.claude/agent-context/lead.md` using the standard context schema.
4. Delegate to domain agents. Do not write code yourself.

Core expertise: AWS, GCP, Kubernetes, Terraform, CI/CD, distributed systems architecture, security.
```

---

#### `infra.md` — Infrastructure as Code
```markdown
---
name: infra
description: Infrastructure as Code and cloud architecture. Use directly for Terraform changes, AWS/GCP resource provisioning, Cloudflare DNS, Netlify config, or cost analysis. Skip lead agent for focused infra work.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior infrastructure engineer specializing in Terraform and cloud provisioning (AWS, GCP, Azure, DigitalOcean).

Standards:
- Follow conventions in `~/.claude/rules/terraform.md`
- Run `terraform fmt` and `terraform validate` before completing
- Use remote state with locking (S3+DynamoDB or Scalr)
- Tag all resources: Name, Environment, Team, ManagedBy=terraform
- Data sources over hardcoded IDs; variables over magic values
```

---

#### `k8s.md` — Kubernetes
```markdown
---
name: k8s
description: Kubernetes platform and GitOps. Use directly for K8s manifest work, Helm chart changes, ArgoCD config, pod troubleshooting, or scaling. Skip lead for focused K8s work.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior Kubernetes and GitOps engineer.

Standards:
- Follow `~/.claude/rules/kubernetes.md`
- Prefer Helm over raw manifests over Kustomize
- ArgoCD: auto-sync+self-heal for non-prod, manual sync for prod
- Always set resource requests AND limits; always add readiness/liveness probes
- NetworkPolicies: default deny, explicit allow
- No root containers; read-only filesystem where possible

Troubleshooting order: events → describe pod → previous logs → resource usage
```

---

#### `networking.md` — Networking
```markdown
---
name: networking
description: Network architecture and troubleshooting. Use directly for VPC design, DNS, load balancer setup, VPN/peering, Traefik ingress, service mesh, CIDR planning, or network debugging.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior network engineer with expertise in AWS VPC, GCP networking, DNS, load balancers, VPN/peering, Traefik, and service mesh.

Diagnose with: `dig`, `nslookup`, `traceroute`, `tcpdump`, `kubectl`, `curl -v`.
Design with: CIDR planning, subnet segmentation, security groups, NACLs, PrivateLink.
```

---

#### `cicd.md` — CI/CD
```markdown
---
name: cicd
description: CI/CD pipelines and build systems. Use directly for GitHub Actions, Bitbucket Pipelines, GitLab CI, Docker image builds, or deployment automation.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You specialize in GitHub Actions, Bitbucket Pipelines, GitLab CI, and Docker.

Principles:
- Fail fast: lint and test before build
- Cache aggressively: dependencies, Docker layers, build artifacts
- Secrets via vault or CI secrets store — never in code or env vars in plaintext
- Environment promotion: dev → staging → prod with manual approval gates
- Docker: multi-stage builds, minimal base images, non-root user
```

---

#### `database.md` — Database
```markdown
---
name: database
description: Database operations and optimization. Use directly for query tuning, migration writing, schema changes, connection pooling, or backup configuration.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a senior database engineer specializing in PostgreSQL (also familiar with MySQL, Redis, ClickHouse).

Standards:
- Migrations must be safe under concurrent production load (no long-holding locks)
- Always include a rollback migration
- Use `EXPLAIN ANALYZE` for query tuning
- Indexes: add for query patterns, not speculatively
- Connection pooling: PgBouncer for PostgreSQL
- Backups: test restores, not just backup creation
```

---

#### `observability.md` — Observability
```markdown
---
name: observability
description: Monitoring and reliability engineering. Use directly for New Relic NRQL queries, dashboard config, alert tuning, SLO definitions, or incident investigation.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You specialize in New Relic, Datadog, Grafana, SLO/SLI design, alerting, and incident investigation.

Approach:
- Define SLOs before writing alerts (availability, latency P99, error rate)
- Alert on symptoms (user impact), not causes (CPU spikes)
- NRQL queries: use TIMESERIES, FACET, and percentile() effectively
- Dashboards: golden signals (latency, traffic, errors, saturation) on first page
```

---

#### `devsecops.md` — DevSecOps
```markdown
---
name: devsecops
description: DevSecOps implementation. Use directly for implementing security controls in pipelines, writing OPA/Kyverno policies, container scanning (Trivy/Grype), SAST/DAST, secret rotation, or hardening Dockerfiles. This agent IMPLEMENTS security — for review/audit use the security agent.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You implement security controls in CI/CD and infrastructure.

Standards from `~/.claude/rules/security-baseline.md`:
- Container scanning: Trivy or Grype in CI, block on CRITICAL/HIGH
- Policy enforcement: OPA or Kyverno for K8s admission control
- Secrets: rotate on schedule, use short-lived credentials (OIDC, dynamic secrets)
- Dockerfiles: non-root user, read-only filesystem, minimal base (distroless preferred)
- SAST: integrate into PR checks, not just nightly runs
```

---

#### `design.md` — UI/UX
```markdown
---
name: design
description: UI/UX design and frontend quality specialist. Use for creating interfaces, reviewing visual design, checking accessibility, iterating on layouts, and verifying in the browser.
model: sonnet
maxTurns: 30
---

You are a senior UI/UX and frontend engineer.

Approach:
- Distinctive, opinionated design — avoid generic Bootstrap look
- Accessibility first: WCAG AA minimum, semantic HTML, keyboard navigation
- Mobile-first responsive design
- Use Playwright to verify designs in a real browser before completing
- Performance: Core Web Vitals (LCP < 2.5s, CLS < 0.1, FID < 100ms)
```

---

#### `security.md` — Security Review (advisory, read-only)
```markdown
---
name: security
description: Security review and advisory. Use for IAM policy review, secrets audit, compliance checks, or scanning results analysis. Read-only — does not modify code. Uses haiku for cost efficiency.
tools: Read, Grep, Glob, Bash, Write
model: haiku
---

You are a security reviewer. Analyze, report, and advise — do not modify code.

Review scope:
- IAM policies: least-privilege violations, wildcard permissions, overpermissioned roles
- Secrets: hardcoded credentials, insecure transmission, missing rotation
- Compliance: SOC2, GDPR, HIPAA implications
- Dependencies: known CVEs, outdated packages

Report format: Executive summary → Critical findings → Major → Minor → Recommendations
```

---

#### `code-quality.md` — Code Review (advisory, read-only)
```markdown
---
name: code-quality
description: Code review and engineering standards advisory. Use for code review, refactoring advice, testing strategy, or PR feedback. Read-only — does not modify code. Uses haiku for cost efficiency.
tools: Read, Grep, Glob, Bash, Write
model: haiku
---

You conduct code review with high engineering standards.

Review dimensions:
- Correctness: logic errors, edge cases, race conditions
- Security: injection risks, auth bypasses, OWASP Top 10
- Maintainability: naming, complexity, dead code, test coverage
- Performance: N+1 queries, unnecessary allocations, blocking I/O

Output: structured review with severity (critical / major / minor) per finding. Do not modify files.
```

---

#### `plan-critic.md` — Plan Reviewer (mandatory before execution)
```markdown
---
name: plan-critic
description: Reviews proposed implementation plans before execution. Checks approach, verifies against docs, identifies risks, suggests alternatives. ALWAYS invoke after writing any multi-step plan and before user approval.
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Write
model: sonnet
---

You are an adversarial plan reviewer. When given an implementation plan:

1. Verify each step exists in official documentation (use WebSearch/WebFetch as needed).
2. Identify the top 3 risks with likelihood and impact.
3. Check for better alternatives — simpler, more standard, or lower-risk approaches.
4. Flag assumptions that could fail silently in production.
5. Rate overall confidence: LOW / MEDIUM / HIGH.

Be direct and skeptical. Your job is to find what the author missed, not validate their work.
```

---

#### `aws-incident.md` — AWS Incident Response
```markdown
---
name: aws-incident
description: AWS security incident response. Use for active attacks, WAF triage, DDoS mitigation, GuardDuty findings, CloudTrail forensics, or suspicious account activity.
tools: Read, Grep, Glob, Bash, Write, Edit
model: sonnet
---

You respond to live AWS security incidents.

Protocol:
1. Gather evidence first: CloudTrail, GuardDuty, VPC Flow Logs, WAF logs
2. Assess blast radius before acting
3. Prefer isolation over deletion (detach policies, quarantine SG, snapshot before terminating)
4. Document every action taken with timestamp
5. Preserve forensic evidence before cleanup

Never delete evidence. When in doubt, isolate rather than destroy.
```

---

#### `cost.md` — Cloud Cost (advisory, read-only)
```markdown
---
name: cost
description: Cloud cost analysis and optimization. Use for AWS Cost Explorer queries, Kubecost reports, Spot/RI savings analysis, rightsizing recommendations, or cost anomaly investigation. Read-only — does not modify infrastructure.
tools: Read, Grep, Glob, Bash, Write
model: haiku
---

You analyze cloud costs across AWS and GCP.

Approach:
- Start with anomaly detection (sudden spikes in Cost Explorer)
- Rightsizing: compare actual CPU/memory utilization vs provisioned
- Reservation analysis: RI/Savings Plans coverage for steady-state workloads
- Spot opportunities: stateless workloads, batch jobs, CI runners
- Output ROI estimates: "switching X instances from on-demand to RI saves $Y/month"

Do not modify any infrastructure — advisory only.
```

---

#### `shopify.md` — Shopify
```markdown
---
name: shopify
description: Shopify development. Use for Shopify Functions, Admin/Storefront API, theme development, app extensions, Liquid templating, or Shopify CLI tasks.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a Shopify developer with expertise in:
- Shopify Functions (discount, payment customization, delivery customization)
- Admin API and Storefront API (GraphQL preferred)
- Theme development: Liquid, JSON templates, sections
- App extensions: checkout UI, admin UI
- Shopify CLI: scaffold, dev, deploy

Use `shopify app dev` for local development and `shopify app deploy` for production.
```

---

#### `airbyte.md` — Airbyte
```markdown
---
name: airbyte
description: Airbyte ELT pipeline operations. Use for connector configuration, sync job debugging, connection troubleshooting, or namespace mapping issues.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are an Airbyte ELT specialist.

Approach:
- Always check sync logs before modifying configs
- Namespace mapping issues: verify source/destination schema naming conventions
- Connector failures: check API rate limits, auth token expiry, schema drift
- Use Airbyte API for automation; prefer config-as-code over UI for repeatability
- Test connections with a full refresh before scheduling incremental syncs
```

---

#### `gcp.md` — GCP
```markdown
---
name: gcp
description: GCP infrastructure and operations. Use for GKE cluster management, GCP IAM, Workload Identity, Cloud SQL, Artifact Registry, Secret Manager, Cloud Run, or Terragrunt.
tools: Read, Grep, Glob, Bash, Edit, Write
model: sonnet
---

You are a GCP infrastructure engineer.

Core services: GKE, Cloud SQL, Artifact Registry, Secret Manager, Cloud Run, Workload Identity, VPC.

Standards:
- IAM: Workload Identity for GKE service accounts (never download SA keys)
- Terragrunt for multi-account GCP Terraform (DRY across environments)
- Secret Manager over env vars for secrets in Cloud Run / GKE
- Artifact Registry for container images (not Docker Hub in production)
- `gcloud` for operational tasks; Terraform/Terragrunt for provisioning
```

---

#### `doc-reviewer.md` — Documentation Reviewer (advisory)
```markdown
---
name: doc-reviewer
description: Documentation quality reviewer. Use for any documentation we create or edit (Confluence pages, READMEs, runbooks, guides, markdown). Checks that docs read clearly for technical, business, vibecoder, and non-technical audiences; verifies every technical claim against official vendor documentation (>95% confidence, no hallucinations); and catches copy/format issues including special characters and raw markup that should not render. Reviews and reports; applies fixes only when explicitly asked.
tools: Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, ToolSearch
model: sonnet
maxTurns: 20
memory: user
---

You are a documentation quality reviewer. You make sure documentation is correct, clear for every audience, and clean of copy/format defects. You review and report; you apply fixes only when explicitly asked.

The full system prompt is in `agents/doc-reviewer.md`. Review dimensions:
- Multi-audience readability — every doc must serve technical, business, vibecoder, and non-technical readers.
- Official-doc accuracy — verify every technical claim against official vendor documentation at >95% confidence; no hallucinations.
- Copy and format — catch special characters and raw markup that should not render.
```

---

### 5.5 Skills

Skills live in `~/.claude/skills/`. Each skill is a directory with a `skill.md` file (or similar, depending on the plugin format). Skills are synced from the Obsidian vault.

```bash
mkdir -p ~/.claude/skills
```

After cloning the Obsidian vault, populate skills from it:
```bash
rsync -a ~/Documents/obsidian-vault/claude-code/skills/ ~/.claude/skills/
```

| Skill | Invocation | Purpose |
|---|---|---|
| `spec-driven-development` | `/spec-driven-development` | Write spec before any non-trivial implementation |
| `fix-issue` | `/fix-issue <number>` | GitHub issue → spec → branch → fix → PR |
| `incident-response` | `/incident-response <desc>` | Incident triage with per-project evidence gathering |
| `k8s-deploy` | `/k8s-deploy <service>` | Spec → Helm/ArgoCD deploy |
| `terraform-review` | Auto (on .tf work) | Security, cost, best practices review |
| `release` | `/release <project>` | Changelog, version bump, GitHub/Bitbucket release |
| `scalr-deploy` | `/scalr-deploy <workspace>` | Terraform via Scalr remote backend |
| `sync-vault` | `/sync-vault` | Manual sync Claude config → Obsidian vault |
| `mcp-builder` | Auto (MCP server work) | Build MCP servers in TypeScript/Python |
| `webapp-testing` | Auto (frontend testing) | Playwright-based web app testing |

> **Skills are LLM-agnostic.** They contain workflow instructions and checklists. Any capable LLM following these instructions will produce equivalent results.

### 5.6 Rules

Rules live in `~/.claude/rules/`. They are injected into agent context automatically for relevant tasks.

```bash
mkdir -p ~/.claude/rules
```

#### `~/.claude/rules/terraform.md`

```markdown
# Terraform Conventions

## Naming
- Resources: `<project>-<env>-<resource>` (e.g., `project-c-prod-rds`)
- Modules: `terraform-<provider>-<resource>`
- Variables: snake_case, descriptive
- Outputs: snake_case, prefix with resource type

## Structure
- Remote state with locking (S3 + DynamoDB or Scalr)
- Data sources over hardcoded IDs
- Variables over magic values
- Modules for reuse (3+ repetitions)

## Tagging
All resources must have: Name, Environment, Team, ManagedBy=terraform

## Validation
- `terraform fmt` before commit
- `terraform validate` in CI
- `tflint` for linting

## State
- Never modify state manually
- Use `terraform import` for existing resources
- Use `terraform state mv` for refactoring
```

#### `~/.claude/rules/kubernetes.md`

```markdown
# Kubernetes Conventions

## Resource Standards
- Always set resource requests AND limits
- PodDisruptionBudgets for production workloads
- Readiness and liveness probes required
- Labels: app.kubernetes.io/name, version, component

## Helm (Preferred)
- values.yaml for defaults, values-<env>.yaml for overrides
- Chart.lock committed to repo
- `helm template` for validation before apply

## ArgoCD
- Auto-sync + self-heal for non-prod
- Manual sync for prod
- Sync waves for ordering

## Security
- NetworkPolicies: default deny, explicit allow
- No root containers
- Read-only root filesystem where possible
- ServiceAccount per workload (no default)
```

#### `~/.claude/rules/security-baseline.md`

```markdown
# Security Baseline

## Secrets
- Never in code, never in env vars if Vault is available
- Rotate on schedule; use short-lived credentials (OIDC, dynamic secrets)

## IAM
- Least privilege always
- No wildcards in production
- Service accounts: one per service, minimum permissions

## Encryption
- At rest: always (S3, RDS, EBS, GCS, Cloud SQL)
- In transit: TLS 1.2+ everywhere
- cert-manager + Let's Encrypt for K8s

## Containers
- Minimal base images (distroless preferred)
- No root user; read-only filesystem
- Scan in CI with Trivy or Grype

## Access
- SSO + MFA for all internal tools
- VPN for infrastructure access
- Audit logging enabled on all services
```

#### `~/.claude/rules/go.md`

```markdown
# Go Conventions
# Applies to: project-a Go services (Go 1.17+)

## Code Style
- `gofmt` always applied
- Errors wrapped with `%w`; messages lowercase, no trailing period
- Context as first param on every I/O function
- No global mutable state — dependency injection

## Testing
- Table-driven tests: `[]struct{ name, input, want }`
- Race detector in CI: `go test -race ./...`

## Linting
- `golangci-lint run ./...` — key linters: errcheck, govet, staticcheck, revive, gocyclo
```

### 5.7 Hook Scripts

The `~/.claude/hooks/` directory holds one script, committed in this repo under `hooks/`:

| Script | Triggered by | What it does |
|---|---|---|
| `auto-sync.sh` | Stop, PostCompact (async) | rsync Claude memory/agents/skills/rules/settings → Obsidian vault, then git commit + push |

> **Claude-only policy:** the vendored Claude Code setup is deliberately free of Engram/opencode-ecosystem dependencies so it can be shared with a team that uses Claude Code only. The `engram-sync.sh`/`engram-sync.py` hooks that mirror Claude memory into Engram are NOT vendored and their `settings.json` entries are stripped by `scripts/sync-from-live.sh`. A personal machine that also runs the opencode stack (Section 8) can add them locally.

Copy it into place and make it executable:
```bash
mkdir -p ~/.claude/hooks
cp hooks/auto-sync.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/auto-sync.sh
```

#### `auto-sync.sh` (memory → Obsidian)

File: `~/.claude/hooks/auto-sync.sh`

> **Platform note:** `rsync` is available on all three platforms. `git` must be installed (it is, from Section 2.1). The script is identical across platforms.

```bash
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

# Sync project-specific memories — discovered dynamically, so it works for any
# user and any set of projects (no hardcoded usernames or project names).
for proj_mem in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$proj_mem" ] || continue
  enc="$(basename "$(dirname "$proj_mem")")"
  [ "$enc" = "$HOME_ENC" ] && continue          # home/global memory already synced above
  name="${enc##*-Documents-}"                    # decode to a clean project name
  sync_dir "$proj_mem" "$VAULT/claude-code/memory/$name" "Memory/$name"
done

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
```

```bash
chmod +x ~/.claude/hooks/auto-sync.sh
```

> **Linux path note:** The memory path uses `-Users-user` which is derived from the macOS home directory `/Users/user`. On Linux, home is `/home/user`, so the path would be `-home-user`. The auto-sync script uses `$MEMORY_SRC` — update this variable to match your actual path: `$CLAUDE_DIR/projects/$(echo $HOME | tr '/' '-' | sed 's/^-//')/memory`

#### `engram-sync` hooks (not vendored)

Earlier revisions of this repo also vendored `engram-sync.sh`/`engram-sync.py`, which mirrored Claude memory files into Engram for the opencode stack. They were removed under the Claude-only policy (see the note at the top of this section): the shared Claude Code setup must not depend on Engram or any non-Claude tooling. A personal machine that wants that bridge can keep the scripts locally in `~/.claude/hooks/` and add the corresponding Stop/PostCompact entries to `settings.json`; `scripts/sync-from-live.sh` will keep them out of the repo automatically.

---

## 6. opencode CLI

opencode is a terminal AI coding assistant with multi-agent orchestration via the `oh-my-openagent` plugin.

### 6.1 Installation

This setup uses the `anomalyco` build of opencode, installed via Homebrew tap (not the `opencode-ai` npm package):

macOS:
```bash
brew install anomalyco/tap/opencode
```

Verify which build is on PATH:
```bash
which opencode      # → /opt/homebrew/bin/opencode
brew list opencode  # → .../Cellar/opencode/<version>/bin/opencode
```

> **Provider note:** This build runs entirely on the NaN provider (see Section 6.2). No OpenCode Zen subscription is required — only a `NAN_API_KEY` in the environment.

The oh-my-openagent plugin does **not** need a manual install. opencode installs npm plugins listed in the `plugin` array of `opencode.jsonc` (Section 6.2) **automatically at startup, using Bun**, caching them under `~/.cache/opencode/packages/<name>@<spec>/node_modules/` ([opencode plugins docs](https://opencode.ai/docs/plugins/)). So once `opencode.jsonc` is in place and Bun is installed (Section 3.5), the plugin is fetched on the next `opencode` launch — just start opencode once.

> **Always pin an exact version** (e.g. `"oh-my-openagent@4.16.1"`), never `@latest`: opencode's Bun cache resolves an `@latest` spec once and never re-resolves it, so `@latest` silently pins to whatever was current at first launch. An exact pin makes the loaded version explicit and upgrades deliberate (change the pin, restart opencode, verify with the harness checker). If `@ast-grep/cli`'s postinstall fails during plugin resolution, it is safe to ignore — AST grep degrades gracefully.

### 6.2 Main Config (`opencode.jsonc`)

File: `~/.config/opencode/opencode.jsonc` — vendored as [`config/opencode.jsonc`](config/opencode.jsonc) (the single source; this README no longer carries an inline copy). What it encodes, verified live on 2026-09-21:

- **Providers:** `enabled_providers: ["nan", "anthropic"]`. `provider.nan` points at `https://api.nan.builders/v1` with `apiKey: "{env:NAN_API_KEY}"` (an env reference, never the value). `provider.anthropic` carries a `whitelist` of exactly `claude-opus-5` and `claude-sonnet-5`, each with `limit.output: 8192`; the key lives only in `~/.local/share/opencode/auth.json` (mode 600).
- **Models:** `deepseek-v4-flash` (1M context, text+image), `glm5.3-flash` (text+image), `mimo-v2.5` (text+audio), plus catalog-only `gemma4` and `qwen3.6` (text+image). **Effort aliases** `deepseek-v4-flash-low`, `deepseek-v4-flash-none`, `glm5.3-flash-low`, `glm5.3-flash-high` share the upstream `id` and carry `options.nanReasoningEffort`; the `harness-guards.js` plugin copies that into `reasoningEffort` after oh-my-openagent's own resolver (which rewrites or deletes the field). `model` = `nan/deepseek-v4-flash-low`, `small_model` = `nan/deepseek-v4-flash-none`.
- **Permissions:** `permission.bash` allows everything except the catastrophic denylist (`rm -rf` of `/` or the home directory, force pushes, `git reset --hard`, `git clean -fd`, `terraform destroy`/`force-unlock`, `kubectl delete namespace`). Rules are evaluated last-match-wins, so agent files must never carry a flat `bash: allow` (the checker fails on it).
- **Compaction:** `compaction.reserved: 50000`. **Engram MCP** (`mcp.engram`, `engram mcp --tools=agent`) and the Playwright MCP are registered as in Section 6.7 and Section 8.

### 6.3 oh-my-openagent Config

File: `~/.config/opencode/oh-my-openagent.json`

**Model strategy (NaN first, Claude on two review seats):** every oh-my-openagent agent and category runs on `nan/deepseek-v4-flash-low` with `nan/glm5.3-flash-low` as the only fallback (both 1M context; benchmark 2026-09-21 on 73 items built from this owner's incidents: deepseek low 66.3/73, glm high 64.7, glm low 61.7, then qwen3.6 54, gemma4 53, mimo 48). Custom agents (Section 6.6): `critic` on `anthropic/claude-sonnet-5`, `plan-critic` on `anthropic/claude-opus-5`, `fact-checker` on `nan/glm5.3-flash-high`, everything else `nan/deepseek-v4-flash-low`. `providerConcurrency` is `nan: 6`, `anthropic: 1`. `reasoningEffort` must not appear in this file (the checker fails on it) — effort comes from the model aliases above.

> **`hephaestus` is disabled** via `disabled_agents: ["hephaestus"]` — it is not part of this configuration.

The full config is vendored in this repo as [`oh-my-openagent.json`](oh-my-openagent.json) — copy it to `~/.config/opencode/oh-my-openagent.json`. Key tuning applied (NaN model-card recipes):

- **Sampling (Qwen3.6-35B-A3B official card, thinking mode is NaN's default):** coding-precision tier — `sisyphus-junior` and the qwen fallbacks inside sisyphus/prometheus/metis — at `temperature: 0.6, top_p: 0.95`; general/search/writing tier — `atlas`/`explore`/`librarian` agents and `quick`/`unspecified-low`/`writing`/`artistry` categories — at `temperature: 1.0, top_p: 0.95`. The card's `presence_penalty: 1.5` for the general profile is not settable client-side in opencode (server-side chat-template item — ask the provider). gemma4 fallbacks at `temperature: 1.0` (Gemma 3 default); deepseek/mimo sampling left alone (DeepSeek thinking mode ignores `temperature`/`top_p` entirely — drive it with `reasoning_effort` instead).
- **Reasoning:** `reasoningEffort` on the deepseek agents — `prometheus: xhigh`, `sisyphus: medium` (orchestrator latency), `metis: high` (plan consultant), and category `deep: xhigh`. NaN accepts `reasoning_effort: low|medium|high|xhigh|max` on deepseek-v4-flash (live-tested); DeepSeek maps `xhigh` to `max` on OpenAI-compatible clients. Requires opencode >= 1.17.13, which forces reasoning mode for OpenAI-compatible reasoning models so these settings apply reliably on custom deployments.
- **Background-task concurrency:** `background_task: {defaultConcurrency: 4, providerConcurrency: {nan: 4}}` caps omo's async background-task path below the 5-concurrent NaN key limit. Note this does NOT throttle ultrawork's normal synchronous fan-out — 429s there are absorbed by `runtime_fallback` retries.

#### oh-my-openagent Agent Reference

| Agent | Model | Role |
|---|---|---|
| Sisyphus | nan/deepseek-v4-flash | Main orchestrator — plans, delegates, tracks todos |
| Prometheus | nan/deepseek-v4-flash | Spec-first planner — interviews before coding |
| Metis | nan/deepseek-v4-flash (temp 0.5) | Pre-planning consultant — gap analysis |
| Momus | nan/mimo-v2.5 (temp 0.1) | Critical reviewer — adversarial plan review |
| Oracle | nan/mimo-v2.5 | Architecture decisions and tradeoffs |
| Explore | nan/qwen3.6 | Fast internal codebase search |
| Librarian | nan/qwen3.6 | External docs and knowledge search |
| Atlas | nan/qwen3.6 | Todo-list management |
| Sisyphus-Junior | nan/qwen3.6 | Delegated simple execution tasks |
| Multimodal-Looker | nan/mimo-v2.5 | Image and screenshot analysis |

> Hephaestus (deep autonomous execution) ships with oh-my-openagent but is disabled here via `disabled_agents`.

#### Council (Multi-Lens Review Pattern)

The "council" is a multi-lens adversarial review run entirely on NaN models:

| Trigger | Who acts | What happens |
|---|---|---|
| `/start-work` | Prometheus (nan/deepseek-v4-flash) | Spec-first interview before any coding |
| High-stakes plan | Momus (nan/mimo-v2.5) | Adversarial review of the plan |
| Planning gap check | Metis (nan/deepseek-v4-flash) | Identifies what's missing before commitment |
| `/hyperplan` | Multiple adversarial critics | Major architectural decisions |
| `ultrawork` or `ulw` in prompt | Full agent team | Parallel orchestration across all agents |
| `/council` (custom) | `@critic` (Claude Sonnet 5, once) + `@fact-checker` (nan/glm5.3-flash-high) + `@thermo-nuclear-review` (NaN) for high-risk targets | Multi-lens critique plus citation-checked fact verification (see Section 6.6) |

### 6.4 TUI and Legacy Config

File: `~/.config/opencode/tui.json`
```json
{
  "plugin": [
    "oh-my-openagent@4.16.1"
  ]
}
```

> The `./tui` subpath is exported by oh-my-openagent since 4.16.x, so the TUI plugin entry is valid now (older guidance said to keep this list empty). Keep the pin in lockstep with the main `plugin` array — one exact version, never two entries, never `@latest`.

File: `~/.opencode/opencode.json` — **must exist and be clean**
```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": []
}
```

> **Why the legacy file matters:** opencode reads both `~/.config/opencode/` and `~/.opencode/` (old location). If you previously installed plugins to the old location, they will silently load even after removing them from the main config. Create this file explicitly with an empty plugin list on every new machine.

### 6.5 Verify Installation

```bash
opencode debug info
# Expected: plugins: - oh-my-openagent@4.16.1 (one entry only, exact pin)

opencode agent list | grep -E "^[A-Za-z].*\(primary|subagent\)"
# Expected: Sisyphus, Prometheus, Metis, Momus, Atlas, oracle, explore, librarian, ...
# (Hephaestus is disabled and should NOT appear)

opencode debug agent "Sisyphus - ultraworker" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print('model:', d.get('model'))"
# Expected: model: {'providerID': 'nan', 'modelID': 'deepseek-v4-flash-low'}
```

---

### 6.6 Shared AGENTS.md, Custom Agents, and Commands

This repo also stores the portable instruction file and the opencode custom agents/commands.

**Shared `AGENTS.md` (repo root)** — portable engineering standards that work with any model:
```bash
cp AGENTS.md ~/.config/opencode/AGENTS.md
```
Project-level instruction files override it where they conflict. `AGENTS.md` documents the model policy (NaN first; Claude only on `@critic`/`@plan-critic`, each reply ending with its closing block), the delegation rule (never send questions or research to the Claude seats), a non-negotiable **anti-hallucination policy** (tests are the terminal proof of done; verify-before-asserting against official docs; cite or abstain; never auto-install fabricated packages; gate on external signals, not self-confidence), and a **Memory (Engram)** policy: recall-first at task start (treating recalled memory as possibly-outdated prior context), save only verified learnings (`mem_save` gated on an external signal), and never save secrets.

**opencode custom agents (`opencode-agents/`)** → install to `~/.config/opencode/agents/`:
```bash
mkdir -p ~/.config/opencode/agents
cp opencode-agents/*.md ~/.config/opencode/agents/
```

| Agent | Model | Role |
|---|---|---|
| `critic` | anthropic/claude-sonnet-5 (variant low, 8192 cap) | Adversarial, read-only reviewer for `/council`, `/verify`, `/best-of` or an explicit review request. Ends with a JSON verdict block. |
| `plan-critic` | anthropic/claude-opus-5 (variant low, 8192 cap, `maxSteps: 6`) | Reviews plans that touch production, auth/IAM, data or multiple accounts. Ends with the line `Review complete.` |
| `thermo-nuclear-review` | nan/deepseek-v4-flash-low | Independent second seat: strict code-quality rubric in diff mode, all council lenses in target mode. No bash. Ends with a lone SHIP/REVISE/BLOCK line. |
| `fact-checker` | nan/glm5.3-flash-high | Extracts falsifiable claims and verifies them against primary sources; ends with a JSON block. |
| 11 domain agents + `lead`, `code-quality`, `security`, `cost`, `design`, `doc-reviewer` | nan/deepseek-v4-flash-low | Same roles as the Claude Code agents, on NaN. |

The `harness-guards.js` plugin rejects any other agent/model pair on Anthropic before a token is billed and writes `maxOutputTokens: 8192` plus `effort: low` into every Claude request (verified on the wire 2026-09-21).

**opencode commands (`opencode-commands/`)** → install to `~/.config/opencode/commands/`:
```bash
mkdir -p ~/.config/opencode/commands
cp opencode-commands/*.md ~/.config/opencode/commands/
```

| Command | What it does |
|---|---|
| `/council` | Convenes the adversarial council — fans the critic across multiple lenses plus the fact-checker, then synthesizes a verdict with recorded dissents. |
| `/verify` | Runs the project's real test/lint/build commands, then routes the diff and results through the critic for a binding SHIP / REVISE / BLOCK verdict. |
| `/smoke` | Harness self-test (3 stages): **Stage 1** runs the static harness checker (`check-harness.mjs`, Section 6.7), **Stage 2** confirms liveness on a NaN model, **Stage 3** scans the recent opencode log for errors. The verdict names the failing stage. Run after any config or plugin change. |
| `/best-of` | Opt-in test-time scaling for hard problems: spawns N (default 3) independent candidate solutions in parallel with distinct angles, has `@critic` pick the winner, applies only the winner, then runs the verify pipeline. Expensive by design — do not use for routine edits. |

---

### 6.7 Harness Checker, Browser/E2E, and Vision

**Harness checker (`opencode-scripts/check-harness.mjs`)** — a validator (no model calls) that enforces the harness invariants: the exact role map (every omo agent/category on deepseek-low with the glm-low fallback; the three custom-agent exceptions), the Anthropic whitelist and 8192 caps, `variant: low` and denied bash/edit/task on both Claude seats, no flat `bash: allow` and no inert `write:` key in any agent (it parses frontmatter with YAML and asks `opencode debug agent <name> --pure` for the resolved tools and bash ruleset), the plugin's unit tests, an exact-version plugin pin, a secret-shape scan, and the `~/.agents/skills` inventory. It also applies the agent policy to this repo's `opencode-agents/` mirror, since `install.sh` copies it back into the live config. Install and run:
```bash
mkdir -p ~/.config/opencode/scripts
cp opencode-scripts/check-harness.mjs ~/.config/opencode/scripts/
node ~/.config/opencode/scripts/check-harness.mjs         # human output, exit 0/1
node ~/.config/opencode/scripts/check-harness.mjs --json   # machine-readable
```
It is wired in as **Stage 1 of `/smoke`**, so a `/smoke` run validates config invariants before checking liveness.

**Browser / E2E (Playwright MCP)** — `opencode.jsonc` registers the official Playwright MCP (`mcp.playwright`, Section 6.2), giving the agent `browser_navigate / click / snapshot / screenshot` tools. It launches `npx @playwright/mcp@0.0.77 --headless` (auto-installed on first use) and reuses an installed Chromium. For authoring/running Playwright E2E scripts, the `webapp-testing` skill — with its `scripts/with_server.py` server-lifecycle helper (vendored under `agents-skills/webapp-testing/scripts/`) — runs via bash; that path needs the Python `playwright` package and Chromium:
```bash
pip install playwright && python -m playwright install chromium
```

**Vision routing (important):** browser screenshots are images. In `config/opencode.jsonc` the models with image input are `deepseek-v4-flash` (all effort aliases), `glm5.3-flash`, `gemma4` and `qwen3.6`; `mimo-v2.5` is wired for **audio** only and must not receive screenshots. The default `nan/deepseek-v4-flash-low` therefore handles vision (benchmark 2026-09-21: 2/2 on the vision items at effort low). `AGENTS.md` carries this as an anti-hallucination rule, and `browser_snapshot` (accessibility text) works on any model for DOM interaction.

---

## 7. pi coding agent + gentle-pi

[pi](https://pi.dev) is a small terminal coding agent; [gentle-pi](https://pi.dev/packages/gentle-pi) adds the ODD/SDD workflow, packaged subagents and a native review flow. Here it mirrors the opencode policy: NaN by default at thinking low, Claude only on gentle-pi's review lenses at effort low with an 8192-token cap. Verified live on 2026-09-21 (wire-recorded requests, guard tests, a 14-item harness slice: pi 26/28 vs opencode 26/28 over two runs).

### 7.1 Installation

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent   # pi 0.87.x, Node >= 22.19 (Section 3.3)
brew install gentleman-programming/tap/gentle-ai                    # 3.4.x, configurator for gentle-pi (Linux: release binary from its GitHub repo)
pi install npm:gentle-pi                                            # then: gentle-ai sync --agents pi
```

`gentle-ai sync` writes its SDD skills into the **shared** `~/.agents/skills`, which opencode also loads. Move them to `~/.pi/agent/skills/` afterwards: `install.sh` does this on every run from the list in [`pi/gentle-skills.txt`](pi/gentle-skills.txt), the sync script excludes those names from `agents-skills/`, and `check-pi-harness.mjs` fails if they leak back. The native review flow refuses to run until the sync was done by the gentle-ai version the package bundles (`managed_assets_outdated`).

Headless use: `pi -p --no-session --mode json "<prompt>" < /dev/null` — pi (and `codex exec`) hang on an open stdin.

### 7.2 Config

All files vendored under [`pi/`](pi/); place them with:
```bash
mkdir -p ~/.pi/agent/extensions ~/.pi/agent/scripts ~/.pi/gentle-ai
cp pi/models.json pi/settings.json pi/AGENTS.md pi/mcp.json ~/.pi/agent/
cp pi/gentle-ai-models.json ~/.pi/gentle-ai/models.json
cp pi/extensions/*.ts ~/.pi/agent/extensions/
cp pi/scripts/*.mjs ~/.pi/agent/scripts/
```

- `models.json`: provider `nan` (`api: openai-completions`, `apiKey: "$NAN_API_KEY"`, `compat.thinkingFormat: reasoning_effort`) with deepseek-v4-flash, glm5.3-flash, mimo-v2.5 (text+image only: a third modality makes pi reject the whole file), gemma4, qwen3.6. Each model maps pi thinking levels to NaN effort via `thinkingLevelMap` (`off → none`, `low → low`, …). The built-in `anthropic` provider stays, with `modelOverrides` capping `claude-sonnet-5` and `claude-opus-5` at `maxTokens: 8192`.
- `settings.json`: default `nan/deepseek-v4-flash`, `defaultThinkingLevel: low`, `modelThinkingLevels` low for both Claude ids, `enabledModels` limited to `nan/*` plus the two Claude ids, `packages: ["npm:gentle-pi", "npm:pi-mcp-adapter"]`.
- `AGENTS.md`: the opencode standards ported to pi, plus a Language rule (gentle-pi's persona prompt made deepseek answer English prompts in Spanish).
- `mcp.json`: context7 through `pi-mcp-adapter`. `gentle-ai-models.json` → `~/.pi/gentle-ai/models.json`: per-agent routing, `review-*` lenses on `anthropic/claude-sonnet-5` at thinking low, `jd-judge-b` on `nan/glm5.3-flash` high (second model family), everything else `nan/deepseek-v4-flash` low. gentle-pi materializes it into `~/.pi/agent/subagents.json` on the next launch.
- The Anthropic key goes in `~/.pi/agent/auth.json` (mode 600, `{"anthropic": {"type": "api_key", "key": "..."}}`) and is never vendored.

### 7.3 Guard extension and checker

pi has no permission system, so [`pi/extensions/harness-guards.ts`](pi/extensions/harness-guards.ts) (installed to `~/.pi/agent/extensions/`) blocks through the `tool_call` hook: the catastrophic bash denylist across ordinary spellings (global options, split flags, `env`/`sudo`/absolute paths), any read or write of secret and state files (`.env*`, `*.tfstate`, `*.pem`, `*.key`, `id_rsa*`, `auth.json`, `secrets/`) through bash or the file tools, `pi auth` (prints keys), nested `pi --no-extensions`, and gentle-pi's `gentle_review_capture_group` (runs every lens concurrently). It also fences the session model: on session start, model selection, input and before each turn, an Anthropic session model is switched back to NaN, and it fails closed (the input is swallowed) when NaN auth is missing. `pi --no-extensions` disables all of this; it is a policy guard, not a security boundary.

[`pi/scripts/check-pi-harness.mjs`](pi/scripts/check-pi-harness.mjs) (installed to `~/.pi/agent/scripts/`, run with `node ~/.pi/agent/scripts/check-pi-harness.mjs`) validates the config, the routing, the materialized profiles, forbids an Anthropic `baseUrl` override, and runs [`test-pi-guards.mjs`](pi/scripts/test-pi-guards.mjs) (`node --experimental-strip-types`), which imports the extension with a fake ExtensionAPI and asserts about 70 decisions.

### 7.4 gentle-pi

Agents shipped: `gentle-ai-explore/verify/worker`, `jd-*`, four `review-*` lenses, `sdd-*`. Subagents run as `pi --mode rpc` children with the routed model; review lenses run in-process through the review relay with their own routed model. The native review (`/gentle:review-mode enable`, then `gentle_review inspect → start → consent → capture`) needs a human consent answer per candidate and shows findings as ids and severities only. On the same unsafe Django migration, opencode's `/verify` and `/council` returned BLOCK with the real blockers while gentle-pi's review approved it with informational findings, so **opencode remains the primary harness; pi is the cheaper secondary** for exploration and implementation. Slash commands (`/gentle:status`, `/gentle:doctor`, `/gentle:usage`) work only in the interactive TUI.

---

## 8. Engram (Persistent Memory)

Engram is a local, third-party persistent-memory store for AI agents. It backs opencode in this setup, giving them a shared, recallable long-term memory via the `mem_*` MCP tools.

### 8.1 What it is

- **Local and zero-dependency.** Engram is a single Go binary (`/opt/homebrew/bin/engram`, v1.16.3 at time of writing) backed by a local SQLite database at `~/.engram/engram.db`. It has no model provider of its own — it only stores and retrieves observations.
- **Purpose.** Persistent cross-session memory: decisions, gotchas, fixes, and conventions survive across sessions and across tools, recalled via the `mem_*` tools (`mem_search`, `mem_context`, `mem_save`, etc.).

### 8.2 Install

```bash
brew install gentleman-programming/tap/engram
```

This is a third-party Homebrew tap (`gentleman-programming/tap`). The binary installs to `/opt/homebrew/bin/engram` on Apple Silicon macOS. The same tap also ships `gentle-ai` (`brew install gentleman-programming/tap/gentle-ai`).

> **Linux note:** these configs assume the macOS Homebrew prefix `/opt/homebrew`, but the engram path is resolved dynamically — opencode launches it by name (`engram mcp --tools=agent`). For a manual install on Linux, just ensure `engram` is on `PATH`.

### 8.3 What it backs

| Tool | Wiring | File |
|---|---|---|
| opencode | `mcp.engram` MCP server (`engram mcp --tools=agent`) | `~/.config/opencode/opencode.jsonc` |
| pi | none by default — gentle-pi lists `gentle-engram` as an optional companion package | — |
| Claude Code | none — the vendored Claude setup is Engram-free by design (Section 5.7 Claude-only policy) | — |

### 8.4 Shared memory policy (AGENTS.md)

The shared `AGENTS.md` (Section 6.6) defines the **"Memory (Engram)"** policy that opencode follows (pi's `AGENTS.md` carries the same wording):
- **Recall first** — at the start of a non-trivial task, search memory for prior decisions/gotchas/conventions, treating results as prior context that may be outdated and verifying before acting on them.
- **Save only verified learnings** — call `mem_save` only when a learning is backed by an external signal (tests passed, a doc confirmed it, a command/`file:line` verified it, or the user confirmed it), and record that evidence in the saved memory.
- **Never save secrets** — no keys, tokens, passwords, or `.env` contents.

---

## 9. Obsidian Vault

The Obsidian vault is the canonical source of truth for all Claude Code configuration. It is a git repository that auto-syncs after every Claude Code session.

### 9.1 Clone the Vault

```bash
cd ~/Documents
git clone git@github.com:yosoyvilla/obsidian-vault.git
```

### 9.2 Install Obsidian

macOS: `brew install --cask obsidian`

Linux: Download AppImage from https://obsidian.md — no package manager install available. Make it executable:
```bash
chmod +x Obsidian-*.AppImage
./Obsidian-*.AppImage  # first run, then add to ~/.local/share/applications if desired
```

Open the vault at `~/Documents/obsidian-vault/`.

### 9.3 Vault Structure

```
obsidian-vault/
├── architecture/        # Architecture notes and diagrams
├── decisions/           # ADR-style decision records
├── patterns/            # Reusable engineering patterns
├── projects/            # Per-project notes
├── runbooks/            # Operational runbooks
├── templates/           # Note templates
└── claude-code/
    ├── setup.md                  # @-imported in ~/.claude/CLAUDE.md every session
    ├── global-rules.md           # Human-readable copy of CLAUDE.md rules
    ├── documentation-style.md    # Documentation style guide
    ├── multi-project-workflow.md # Multi-project workflow notes
    ├── tips-and-tricks.md        # Tips and tricks
    ├── kubernetes.md             # Shared k8s rule (copy)
    ├── terraform.md              # Shared terraform rule (copy)
    ├── security-baseline.md      # Shared security rule (copy)
    ├── agents/                   # Mirrored from ~/.claude/agents/
    ├── skills/                   # Mirrored from ~/.claude/skills/
    ├── rules/                    # Mirrored from ~/.claude/rules/
    ├── agent-memory/             # Mirrored from ~/.claude/agent-memory/
    ├── settings.json             # Mirrored from ~/.claude/settings.json
    └── memory/                   # Mirrored from all project memories
```

### 9.4 How It Stays In Sync

| Mechanism | When | What |
|---|---|---|
| `auto-sync.sh` hook | Every session end (Stop + PostCompact) | rsync agents, skills, rules, memory → vault; git commit+push |
| `@` import in CLAUDE.md | Every session start | `setup.md` loaded into Claude's context |
| SessionStart hook | Every session start | Reminds Claude to update vault when modifying config |
| `/sync-vault` skill | Manual | Full sync when needed |

---

## 10. Environment Variables

Add to `~/.zshrc`. Never commit API keys to git.

```zsh
# NaN API — OpenAI-compatible proxy (qwen3.6, deepseek, mimo, gemma)
# Get key at: https://nan.builders
export NAN_API_KEY="sk-..."

# New Relic (project-a observability)
export NEW_RELIC_API_KEY="NRAK-..."

# HashiCorp Vault
export VAULT_ADDR="https://vault.example.com"

# DigitalOcean — API token + Spaces (S3-compatible) credentials
export DIGITALOCEAN_TOKEN="dop_v1_..."
export SPACES_ACCESS_KEY_ID="..."
export SPACES_SECRET_ACCESS_KEY="..."
```

> **Set on-demand, not standing exports:** `SCALR_TOKEN` (project-a Scalr deploys) and `AIRBYTE_TOKEN` (project-c Airbyte) are exported only for the session that needs them — they are not kept in `~/.zshrc`.

**Credential management by type:**

| Credential | Where |
|---|---|
| AWS | `~/.aws/credentials` via `aws configure` or awsume profiles |
| GCP | `gcloud auth login` + `gcloud auth application-default login` |
| kubectl | `~/.kube/config` via `gcloud container clusters get-credentials` or similar |
| Vault tokens | `vault login` — short-lived, not persisted |
| GitHub | `gh auth login` — stored in system keychain |

---

## 11. Projects Structure

```
~/Documents/
├── project-b/          # Real estate portals: portal-1, portal-2, portal-3, portal-4
│                      # PHP, GCP, GKE, Terragrunt, PostgreSQL
├── project-c/     # E-commerce: Shopify, warehousing, infra
│                      # Node.js, Shopify Functions, Airbyte, ArgoCD
├── project-d/          # FinTech/payments
│                      # Python/Django, Dokploy, DigitalOcean
├── project-a/           # EdTech
│                      # Go, EKS, Terraform, New Relic, Scalr
├── Personal/          # Side projects (Crewgent, etc.)
│                      # TypeScript, Next.js, Supabase
└── obsidian-vault/    # Claude Code knowledge base (git: yosoyvilla/obsidian-vault)
```

Per-project Claude context:
```
<project>/
└── .claude/
    ├── CLAUDE.md             # Project-specific stack, commands, rules
    └── agent-context/        # Written by agents during sessions
        └── lead.md           # Active lead agent plan (if any)
```

---

## 12. Quick Reference

### Claude Code

```bash
claude                                  # Start interactive session
claude --dangerously-skip-permissions   # Auto-approve all tool calls
claude --worktree <name>                # Parallel work in a git worktree

# In-session commands
/clear                   # Clear context (between unrelated tasks)
/compact                 # Compress context (long sessions)
/model                   # Switch model
/spec-driven-development # Write spec before implementation
/fix-issue <number>      # GitHub issue → fix → PR
/incident-response <desc># Incident triage
/k8s-deploy <service>    # Deploy to K8s
/release <project>       # Cut a release
```

### opencode

```bash
opencode                 # Start TUI
opencode run "task"      # Run with message
opencode debug info      # Check loaded plugins
opencode agent list      # List all agents

# In-session
/start-work              # Prometheus spec-first interview
/hyperplan               # 5 adversarial critics on a plan
ultrawork                # (in any prompt) Full parallel orchestration
/council <target>        # one Claude critic + fact-checker (+ NaN thermo seat for high-risk)
/verify                  # tests/lint/build + blind critic review -> SHIP/REVISE/BLOCK/INCONCLUSIVE
/smoke                   # harness self-test
```

### pi / Herdr

```bash
pi                                        # interactive (gentle shell)
pi -p --no-session --mode json "task" </dev/null
node ~/.pi/agent/scripts/check-pi-harness.mjs
herdr                                     # attach the persistent session
herdr agent list                          # agents running in panes and their state
```

### Model Selection Guide

| Scenario | Tool | Model |
|---|---|---|
| Architecture / planning | Claude Code | opus[1m] (Opus, 1M context) |
| Code implementation | Claude Code | sonnet / opus[1m] |
| Security/cost review | Claude Code | haiku (advisory agents) |
| Orchestration, search, execution | opencode | nan/deepseek-v4-flash-low (fallback glm5.3-flash-low) |
| Adversarial review / plan review | opencode | anthropic/claude-sonnet-5 (`@critic`) / claude-opus-5 (`@plan-critic`), effort low, 8k cap |
| Fact checking | opencode | nan/glm5.3-flash-high (`@fact-checker`) |
| Cheaper NaN sessions | pi | nan/deepseek-v4-flash at thinking low; review lenses on Claude Sonnet 5 |
| Blind second-opinion reviews | Codex CLI / Cursor CLI | gpt-5.6-sol high / auto |

---

## 13. Post-Install Checklist

Copy this list and check off each item:

**System**
- [ ] Homebrew / apt / dnf configured
- [ ] Node 22 on PATH (`node --version` → v22.x.x; pi requires >= 22.19)
- [ ] Bun installed (`~/.bun/bin/bun`)
- [ ] `gh` authenticated (`gh auth status`)
- [ ] AWS CLI configured
- [ ] gcloud authenticated
- [ ] SSH key added to GitHub (`gh ssh-key list`)

**Claude Code**
- [ ] Installed (`claude --version`)
- [ ] Authenticated (run `claude`)
- [ ] `~/.claude/CLAUDE.md` created
- [ ] `~/.claude/settings.json` created (model `opus[1m]`)
- [ ] `~/.claude/agents/` populated (18 agent files, incl. `doc-reviewer`)
- [ ] `~/.claude/skills/` populated (incl. `herdr` and `dagr-producer`)
- [ ] `~/.claude/rules/` created
- [ ] `~/.claude/hooks/auto-sync.sh` created and executable
- [ ] `~/.claude/settings.local.json` created (permission allowlist)

**Engram** (opencode only — the Claude Code setup is Engram-free)
- [ ] Installed (`engram --version` → 1.16.x)
- [ ] DB exists at `~/.engram/engram.db`

**Obsidian Vault**
- [ ] `git clone git@github.com:yosoyvilla/obsidian-vault.git ~/Documents/obsidian-vault`
- [ ] Obsidian app installed and vault opened

**opencode**
- [ ] Installed via brew tap (`brew install anomalyco/tap/opencode`)
- [ ] `NAN_API_KEY` set (no OpenCode Zen subscription needed)
- [ ] oh-my-openagent in plugin cache
- [ ] `~/.config/opencode/opencode.jsonc` created (nan + anthropic whitelist, `mcp.engram` enabled)
- [ ] `~/.config/opencode/oh-my-openagent.json` created (deepseek-low everywhere, hephaestus disabled)
- [ ] `~/.config/opencode/AGENTS.md` (identical to repo `AGENTS.md`)
- [ ] `~/.config/opencode/agents/` populated (21 agents; critic and plan-critic on Claude)
- [ ] `~/.config/opencode/commands/` populated (council, verify, best-of, smoke)
- [ ] `~/.local/share/opencode/auth.json` holds the Anthropic key (mode 600)
- [ ] `node ~/.config/opencode/scripts/check-harness.mjs` passes
- [ ] `~/.config/opencode/tui.json` created (empty plugins)
- [ ] `~/.opencode/opencode.json` created (empty plugins)
- [ ] Verification: `opencode debug info` shows only `oh-my-openagent@4.16.1` (exact pin)

**pi + gentle-pi**
- [ ] `pi --version` (0.87.x) and `gentle-ai --version` (3.4.x)
- [ ] `~/.pi/agent/{models.json,settings.json,AGENTS.md,mcp.json}` placed; `~/.pi/agent/auth.json` written (mode 600)
- [ ] `pi install npm:gentle-pi` done, `gentle-ai sync --agents pi` run, SDD skills moved to `~/.pi/agent/skills/`
- [ ] `node ~/.pi/agent/scripts/check-pi-harness.mjs` passes
- [ ] `pi -p --no-session "Reply OK" </dev/null` answers on nan/deepseek-v4-flash

**Herdr**
- [ ] `herdr --version` (0.9.x); `herdr` started once
- [ ] Plugins from `herdr/plugins.txt` installed (`herdr plugin list`)
- [ ] Integrations from `herdr/integrations.txt` installed (`herdr integration status`)
- [ ] `dagr --version` works (symlink to the herdr-dagr plugin binary)

**Codex CLI**
- [ ] `codex --version`; `codex login` done
- [ ] `~/.codex/AGENTS.md` placed; `config.toml` compared with `codex/config.toml`

**Terminal Tools**
- [ ] `fzf` installed and CTRL-R works in terminal
- [ ] `bat --version` works
- [ ] `rg --version` works
- [ ] `eza --version` works (or at least `ls` alias configured)
- [ ] `zoxide` init in `.zshrc` (`z` command works)
- [ ] `delta` in `~/.gitconfig` (`git diff` shows colored output)

**Environment**
- [ ] `NAN_API_KEY` in `~/.zshrc`
- [ ] NaN API reachable: `curl -H "Authorization: Bearer $NAN_API_KEY" https://api.nan.builders/v1/models`
- [ ] All projects cloned to `~/Documents/`
- [ ] Per-project `.claude/CLAUDE.md` files in place

---

## 14. Troubleshooting

### oh-my-openagent not loading

opencode auto-installs `plugin`-array packages with Bun at startup, caching them under `~/.cache/opencode/node_modules/`. If the plugin is not loading:

```bash
command -v bun                                    # Bun must be installed (Section 3.5)
ls ~/.cache/opencode/node_modules/oh-my-openagent # is it cached?
# Force a clean re-resolve, then relaunch opencode:
rm -rf ~/.cache/opencode/node_modules && opencode
```

### Stale/unexpected plugin appearing in `opencode debug info`

```bash
cat ~/.opencode/opencode.json
# Must be: {"$schema": "...", "plugin": []}
# opencode reads BOTH ~/.config/opencode/ AND ~/.opencode/
```

### NaN API 401 error in opencode

```bash
echo $NAN_API_KEY          # Must not be empty
source ~/.zshrc             # Or open a new terminal
# Then retry
```

### deepseek-v4-flash / mimo-v2.5 returning null content

These are thinking models — all tokens go to internal reasoning with low `max_tokens`. Use `max_tokens: 500+` for deepseek, `2000+` for mimo.

### Claude Code hooks not running

```bash
ls -la ~/.claude/hooks/auto-sync.sh  # Must be executable
chmod +x ~/.claude/hooks/auto-sync.sh
tail -f ~/.claude/sync.log           # Watch sync activity
```

### macOS Notification hook on Linux

Replace the `osascript` command in `settings.json` Notification hook with:
```bash
notify-send 'Claude Code' 'Needs your attention'
```

Install: `sudo apt install libnotify-bin` (Debian/Ubuntu) or `sudo dnf install libnotify` (Fedora).

### `jq` not found (hooks use it)

```bash
# macOS:
brew install jq
# Debian/Ubuntu:
sudo apt install -y jq
# Fedora:
sudo dnf install -y jq
```

### `rsync` not found (auto-sync hook uses it)

```bash
# macOS: included by default
# Debian/Ubuntu:
sudo apt install -y rsync
# Fedora:
sudo dnf install -y rsync
```

---

## 15. Keeping the Repo in Sync

This repo is a **sanitized mirror** of the live workstation config. To refresh it from the live machine, run:

```bash
scripts/sync-from-live.sh --dry-run   # preview incoming changes
scripts/sync-from-live.sh             # stage, sanitize, verify, mirror into the working tree
git diff                              # review EVERY change before committing
```

What it does:

1. Stages the live config (Claude Code agents/skills/hooks/rules/CLAUDE.md/settings, opencode agents/commands/plugins/scripts/configs + AGENTS.md, `~/.agents/skills` as `agents-skills/`, pi configs/extension/scripts and gentle-pi routing as `pi/`, a curated Codex `config.toml` plus AGENTS.md and hooks as `codex/`, Herdr plugin and integration manifests as `herdr/`) into a temp dir. The live side is never modified. Files that tools install themselves (Herdr hooks/plugins, gentle-ai synced skills, Claude's `skills/synced` cache) are excluded; pi, codex and herdr are staged all-or-nothing and skipped when the tool is absent.
2. Templatizes machine paths (`$HOME` → `__HOME__`) before sanitizing.
3. Applies the sanitize map, then enforces hard gates: zero sanitize-map tokens in content or file names, zero secret-shaped strings. Any failure aborts with the repo untouched and the staging dir kept for inspection.
4. Mirrors the staging tree into the repo working tree. Protected files (`agents/airbyte.md`, `skills/scalr-deploy/SKILL.md`) keep the repo version — they carry intentional `REQUIRES SECRET` annotations absent from live.
5. Leaves committing to you. Review the diff, then commit with a single-line message.

The sanitize map lives at `~/.config/setup-sync/sanitize-map.txt` and is deliberately **not** in this repo (committing it would reveal the names it scrubs). Format: `scripts/sanitize-map.example`. On a new machine, recreate the map from the private Obsidian vault notes before your first sync from that machine.

Rules that keep the repo consistent:

- Excluded from sync: memory, session data, logs, caches, backups (`*.bak*`), `node_modules`, `__pycache__`, opencode `package.json`/`package-lock.json`.
- Claude-only policy: `engram-sync.*` and Herdr hooks are excluded and their `settings.json` entries stripped — the vendored Claude Code setup must work for teammates who only use Claude Code (`install.sh` re-adds the Herdr hook through `herdr integration install claude`).
- This README summarizes configs instead of copying them inline; when `config/opencode.jsonc`, `oh-my-openagent.json`, `pi/` or `codex/` change, re-read the matching section summary (the script prints a reminder).
- Never hand-copy live files into the repo — always go through the script so sanitization and gates run.

---

## 16. Herdr

[Herdr](https://herdr.dev) is a terminal workspace manager for coding agents: a background server owns the panes, clients attach like tmux, and agents running inside panes show `working` / `blocked` / `done` in a sidebar. Installed 0.9.1 on the live machine (`curl -fsSL https://herdr.dev/install.sh | sh`; update with `herdr update --handoff`, which migrates live panes).

- **Integrations** ([`herdr/integrations.txt`](herdr/integrations.txt), one name per line): `pi` and `opencode` report lifecycle state and session ids through a bundled extension/plugin; `claude`, `codex` and `cursor` report session identity through one `SessionStart` hook each (state still comes from screen detection). Each install adds exactly one hook entry to the respective config (verified by semantic diff). Those files are not vendored; `install.sh` re-runs `herdr integration install <name>` per line.
- **Plugins** ([`herdr/plugins.txt`](herdr/plugins.txt), tab-separated `owner/repo[/subdir]`, pinned commit, plugin id, enabled state; `install.sh` installs each with `herdr plugin install --ref <commit> <source> --yes` and re-applies the disabled state): herdr-dagr (live DAG of an agent run; the `dagr` binary is symlinked to `~/.local/bin`, the `dagr-producer` skill writes `.dagr/run.json`), hunk (review agent diffs), herdr-nvim, and two tab-naming plugins. `herdr plugin action invoke` acts on the **focused** workspace; focus it first.
- **Skill**: `skills/herdr/` (from `herdrdev/herdr`) teaches Claude Code and pi to drive panes from inside a Herdr pane (`HERDR_ENV=1`). The rule in `rules/agent-workflows.md` says when to use `herdr agent start/prompt/wait` and `pane run/wait-output` instead of detached shells.
- Not adopted (2026-09-21): usage/quota plugins. For NaN allowance use `/gentle:usage` in pi or `nan-cli`.

## 17. Codex CLI

Codex CLI (`npm install -g @openai/codex`, `codex login`) is used as a blind adversarial reviewer alongside Cursor CLI (`codex exec --skip-git-repo-check --sandbox read-only -m gpt-5.6-sol -o <file> "<prompt>" </dev/null`). Vendored under [`codex/`](codex/):

- `config.toml` is a **curated** subset generated by the sync script: model `gpt-5.6-sol`, reasoning effort `high`, the plugin enable/disable list (`explanatory-output-style` and `github` disabled as duplicates of the Claude Code plugins), `[features] hooks = true`, memories, and an allowlisted shell environment policy. Marketplace caches, MCP servers bound to the ChatGPT desktop app, per-machine project trust entries and desktop UI state are not vendored; `install.sh` places the curated file only when no `config.toml` exists yet (a known non-converging step, stated in its log line).
- `AGENTS.md`: the routing section for Claude-only subagents was replaced on 2026-09-21 by a "working alone" section, since Codex has none of those agents.
- `hooks.json`: Codex hooks, re-placed on every install run (the Herdr `SessionStart` entry is re-created by the integration installer).

Cursor CLI is configured separately (`cursor-agent --model auto`); its `mcp.json` holds plaintext tokens and is deliberately not vendored.
