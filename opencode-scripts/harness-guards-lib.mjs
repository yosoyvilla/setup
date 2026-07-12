/**
 * harness-guards — automatic verification enforcement for the NaN opencode harness.
 *
 * Enforcement that prose rules cannot guarantee on open models:
 *  - Per-LLM-call obligation injection (experimental.chat.system.transform):
 *    outstanding verification duties are appended to the system prompt on every
 *    model call until the corresponding action is observed. Race-free by design:
 *    no session.idle prompt injection (oh-my-openagent owns idle dispatch and
 *    two idle-prompters can corrupt session state).
 *  - Content-aware secret blocking (tool.execute.before): secret-shaped values
 *    cannot be written into docs/markdown; bash cannot redirect into or delete
 *    protected files. Pure path-glob protection lives in opencode.jsonc
 *    permission.edit — this plugin only covers what globs cannot express.
 *  - Bash audit log (~/.config/opencode/logs/bash-audit.log).
 *  - session.idle: macOS notification (no prompt injection) when obligations
 *    remain; obligations also survive compaction via session.compacting.
 *
 * Kill switch: HARNESS_GUARDS_DISABLE=1
 */
import fs from "node:fs"
import path from "node:path"
import os from "node:os"

export const DISABLED = process.env.HARNESS_GUARDS_DISABLE === "1"
export const LOG_DIR = path.join(os.homedir(), ".config", "opencode", "logs")
export const AUDIT_LOG = path.join(LOG_DIR, "bash-audit.log")

// --- classification ---------------------------------------------------------

export const SECRET_RE = new RegExp(
  [
    "ghp_[0-9A-Za-z]{20,}",
    "github_pat_[0-9A-Za-z_]{20,}",
    "AKIA[0-9A-Z]{16}",
    "-----BEGIN [A-Z ]*PRIVATE KEY",
    "xox[baprs]-[0-9A-Za-z-]{10,}",
    "sk-ant-[A-Za-z0-9_-]{20,}",
    "sk-[A-Za-z0-9]{40,}",
    "AIza[0-9A-Za-z_-]{35}",
    "eyJ[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{20,}\\.[A-Za-z0-9_-]{10,}",
  ].join("|"),
)

export const DOC_FILE_RE = /\.(md|mdx|markdown|txt|rst|adoc)$/i
export const UI_FILE_RE = /\.(jsx|tsx|vue|svelte|html|css|scss)$|(^|\/)(frontend|components|pages|views)\//i
export const CODE_FILE_RE = /\.(js|jsx|ts|tsx|mjs|cjs|py|go|rb|php|java|rs|vue|svelte)$/i
export const MANIFEST_RE = /(^|\/)(requirements[^/]*\.txt|package\.json|pyproject\.toml|go\.mod|Gemfile|Cargo\.toml|composer\.json|Pipfile)$/
export const INSTALL_CMD_RE = /\b(pip3?|uv)\s+(install|add)\b|\b(npm|pnpm|yarn|bun)\s+(install|add|i)\s+\S|\bpoetry\s+add\b|\bgem\s+install\b|\bgo\s+get\b/
export const TEST_CMD_RE = /\b(pytest|vitest|jest|playwright\s+test|go\s+test|cargo\s+test|rspec|phpunit)\b|\bnpm\s+(run\s+)?test\b|\bpnpm\s+(run\s+)?test\b|manage\.py\s+test\b|\be2e[_-]?test/
export const BROWSER_TOOL_RE = /playwright|browser_/i
// Bash writing into / deleting protected files (compound-command aware; globs can't see this).
export const BASH_PROTECTED_RE = /(?:>>?|\btee\b[^|;&]*|\bcp\b[^|;&]*|\bmv\b[^|;&]*|\brm\b[^|;&]*)\s*(?:"[^"]*"|'[^']*'|\S*)?(\.env\b(?!\.example)|\.tfstate\b|\.tfvars\b|\.pem\b|\.key\b|id_rsa\S*|(^|[\s/'"])secrets\/)/

// --- state ------------------------------------------------------------------

// One opencode process serves one project directory, so project-wide state is a
// module singleton. Subagent edits count toward the same obligation set.
export const state = {
  codeEdited: new Set(),
  uiEdited: new Set(),
  installs: [],
  gitMissing: false,
  gitChecked: false,
  lastNotify: 0,
}
export const sessionParent = new Map() // sessionID -> parentID | undefined (cached)

export function classifyEdit(filePath) {
  if (!filePath) return
  if (MANIFEST_RE.test(filePath)) {
    state.installs = [] // manifest touched: dependency obligation cleared
    return
  }
  if (UI_FILE_RE.test(filePath)) state.uiEdited.add(filePath)
  if (CODE_FILE_RE.test(filePath)) state.codeEdited.add(filePath)
}

export function classifyBash(command) {
  if (INSTALL_CMD_RE.test(command)) state.installs.push(command.slice(0, 120))
  if (TEST_CMD_RE.test(command)) state.codeEdited.clear() // tests ran: clears test obligation
  if (/\bgit\s+init\b/.test(command)) {
    state.gitMissing = false
    state.gitChecked = false // re-verify on next edit
  }
}

export function checkGit(directory) {
  if (state.gitChecked) return
  state.gitChecked = true
  let dir = directory
  for (let i = 0; i < 20; i++) {
    if (fs.existsSync(path.join(dir, ".git"))) {
      state.gitMissing = false
      return
    }
    const parent = path.dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  state.gitMissing = true
}

export function obligations() {
  const out = []
  if (state.codeEdited.size > 0)
    out.push(
      `TESTS: ${state.codeEdited.size} code file(s) edited but the project's test suite has not run since (${[...state.codeEdited].slice(0, 5).join(", ")}). Determine and run the real test command now; report actual output.`,
    )
  if (state.uiEdited.size > 0)
    out.push(
      `UI VERIFICATION: frontend file(s) changed (${[...state.uiEdited].slice(0, 5).join(", ")}) but no browser verification ran. Use the playwright tools: open the app, drive the changed flow, confirm the network response is 2xx (not just that the click happened), then run the visual-qa skill: probe that spacing utilities compute non-zero, screenshot desktop+mobile, and review the screenshots with a vision-capable model for alignment/overflow/contrast defects.`,
    )
  if (state.installs.length > 0)
    out.push(
      `DEPENDENCY MANIFEST: install command(s) ran (${state.installs.slice(0, 3).join(" | ")}) but no dependency manifest was updated. Add the package(s) to requirements.txt/package.json/etc. in this change.`,
    )
  if (state.gitMissing)
    out.push(
      `VERSION CONTROL: this project has no git repository. Run git init, add a sensible .gitignore, make an initial commit, and commit after each verified change.`,
    )
  return out
}

export function obligationBlock() {
  const items = obligations()
  if (items.length === 0) return null
  return (
    `[harness-guards] OUTSTANDING VERIFICATION OBLIGATIONS — these clear automatically when the action is observed. ` +
    `Do NOT describe any work as done, complete, fixed, or working while any remain:\n` +
    items.map((i) => `- ${i}`).join("\n")
  )
}

