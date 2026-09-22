#!/usr/bin/env node
// Harness invariant checker for the NaN-first opencode setup (Claude on two review seats since 2026-09-21; Zed removed the same day).
//
// Static, offline, zero model calls (NaN-safe, no token cost, no concurrency
// impact). Enforces the invariants that are otherwise protected only by
// discipline: NaN-only models, AGENTS.md byte-parity, the bash catastrophic
// denylist, Engram wiring, and config validity.
//
// Run:  node ~/.config/opencode/scripts/check-harness.mjs
// Exit: 0 + "Harness check passed." on success; 1 + a bullet list otherwise.
// Flag: --json  emit a machine-readable {ok, errors[]} object instead.
//
// Design notes (from plan-critic review):
// - JSONC comments are stripped with a string-aware scanner (not a regex), so
//   "https://" inside a value is never corrupted.
// - The NaN-only check walks only model-bearing value paths, never raw file
//   text, so structural keys like "openai_compatible" / "@ai-sdk/openai-
//   compatible" never false-positive.
// - .bak* files in agents/ and commands/ are excluded.
// - Context-window values check INTERNAL CONSISTENCY against the values NaN
//   documented as of 2026-06-26; they do not validate NaN's live API.

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import { CLAUDE_EFFORT } from "./harness-guards-lib.mjs";
import YAML from "yaml"; // resolved from ~/.config/opencode/node_modules (opencode dependency)

const HOME = os.homedir();
const P = {
  oc: path.join(HOME, ".config/opencode/opencode.jsonc"),
  omo: path.join(HOME, ".config/opencode/oh-my-openagent.json"),
  oc2: path.join(HOME, ".opencode/opencode.json"),
  agentsOc: path.join(HOME, ".config/opencode/AGENTS.md"),
  agentsDir: path.join(HOME, ".config/opencode/agents"),
  commandsDir: path.join(HOME, ".config/opencode/commands"),
  // Sanitized mirror that install.sh copies BACK into the live config: it must satisfy the same agent policy or a reinstall reverts it.
  mirrorAgentsDir: path.join(HOME, "Documents/setup/opencode-agents"),
};

const KNOWN_MODELS = new Set([
  "qwen3.6", "deepseek-v4-flash", "mimo-v2.5", "gemma4", "glm5.3-flash",
  // Effort aliases (same upstream id + options.nanReasoningEffort, applied by plugins/harness-guards.js).
  "deepseek-v4-flash-low", "deepseek-v4-flash-none", "glm5.3-flash-low", "glm5.3-flash-high",
  "whisper", "kokoro", "qwen3-embedding", "rerank", "flux-2-klein",
]);
// opencode.jsonc context values (NaN opencode doc, 2026-09-21).
const CTX = { "qwen3.6": 262144, "gemma4": 262144, "deepseek-v4-flash": 1048575, "deepseek-v4-flash-low": 1048575, "deepseek-v4-flash-none": 1048575,
  "mimo-v2.5": 1048576, "glm5.3-flash": 1048576, "glm5.3-flash-low": 1048576, "glm5.3-flash-high": 1048576 };
const ALIAS_BASE = { "deepseek-v4-flash-low": ["deepseek-v4-flash", "low"], "deepseek-v4-flash-none": ["deepseek-v4-flash", "none"],
  "glm5.3-flash-low": ["glm5.3-flash", "low"], "glm5.3-flash-high": ["glm5.3-flash", "high"] };
// Claude is allowed ONLY on these custom review seats (2026-09-21 owner decision; pay-as-you-go key).
const CLAUDE_SEATS = { "critic.md": "anthropic/claude-sonnet-5", "plan-critic.md": "anthropic/claude-opus-5" };
// Both seats run at effort low (opencode variant -> Anthropic output_config.effort) so thinking fits the 8k cap.
const CLAUDE_VARIANT = CLAUDE_EFFORT; // same constant the runtime hook writes
// opencode gates the write tool under the `edit` permission (a `write:` key is inert) and evaluates rules
// last-match-wins (permission/index.ts findLast), so a flat `bash: allow` in an agent overrides the global denylist.
const SEAT_DENY = { "critic.md": ["bash", "edit", "task"], "plan-critic.md": ["bash", "edit", "task"], "thermo-nuclear-review.md": ["bash", "edit", "task"] };
// Commands that must resolve to deny for EVERY agent (the global denylist must not be shadowed by agent rules).
const BASH_CANARIES = ["terraform destroy -auto-approve", "git reset --hard HEAD~1", "rm -rf " + "~", "kubectl delete namespace prod"];
const ANTHROPIC_MODELS = new Set(Object.values(CLAUDE_SEATS).map((m) => m.slice("anthropic/".length)));
const ANTHROPIC_OUTPUT_CAP = 8192;
const BASE_URL = "https://api.nan.builders/v1";
const DENYLIST = [
  "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf ~/*",
  "git push --force*", "git push -f*", "git reset --hard*", "git clean -fd*",
  "terraform destroy*", "terraform force-unlock*", "kubectl delete namespace*",
];
const SKILL_DENY = ["terraform-devops", "incident-triage", "spec-first"];
// Skills inventory for ~/.agents/skills (opencode; Zed removed 2026-09-21). A new or
// removed skill silently changes the model-facing tool surface of BOTH tools,
// so additions must be deliberate: update this list when you intend the change.
const EXPECTED_SKILLS = new Set([
  // Inventory acknowledged 2026-09-21 (every entry present in ~/.agents/skills at that date).
  "algorithmic-art",
  "canvas-design",
  "computer-use",
  "dagr-producer",
  "deslop",
  "find-skills",
  "fix-issue",
  "frontend-design",
  "impeccable",
  "incident-response",
  "incident-triage",
  "k8s-debug",
  "k8s-deploy",
  "karpathy-guidelines",
  "mcp-builder",
  "memex-search",
  "orca-cli",
  "release",
  "scalr-deploy",
  "skill-creator",
  "spec-driven-development",
  "spec-first",
  "sync-vault",
  "terminal-browser",
  "terraform-devops",
  "terraform-review",
  "thermo-nuclear-code-quality-review",
  "validating-packages",
  "verify-this",
  "verifying-changes",
  "visual-qa",
  "webapp-testing",
]);

// Protected-file globs that must be denied in permission.edit (path-glob layer
// of file protection; content-aware guards live in plugins/harness-guards.js).
const PROTECTED_EDIT_DENY = [
  "**/.env", "**/.env.*", "**/*.tfstate", "**/*.tfvars",
  "**/*.pem", "**/*.key", "**/id_rsa*", "**/secrets/**",
];

const errors = [];
const fail = (m) => errors.push(m);

function readText(p) {
  try { return fs.readFileSync(p, "utf8"); }
  catch { fail(`${rel(p)}: file missing or unreadable`); return null; }
}
const rel = (p) => p.replace(HOME, "~");

// String-aware JSONC comment stripper: skips // and /* */ ONLY outside strings.
function stripJsonc(src) {
  let out = "", i = 0, inStr = false, q = "";
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    if (inStr) {
      out += c;
      if (c === "\\") { out += src[i + 1] ?? ""; i += 2; continue; }
      if (c === q) inStr = false;
      i++; continue;
    }
    if (c === '"' || c === "'") { inStr = true; q = c; out += c; i++; continue; }
    if (c === "/" && n === "/") { while (i < src.length && src[i] !== "\n") i++; continue; }
    if (c === "/" && n === "*") { i += 2; while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++; i += 2; continue; }
    out += c; i++;
  }
  return out;
}

function parseJson(p, { jsonc = false } = {}) {
  const t = readText(p);
  if (t == null) return null;
  try { return JSON.parse(jsonc ? stripJsonc(t) : t); }
  catch (e) { fail(`${rel(p)}: invalid JSON (${e.message})`); return null; }
}

// A model reference is valid if it is "nan/<id>" with <id> in KNOWN_MODELS, or — only where
// allowAnthropic names the permitted value — exactly that anthropic/* model.
const CATALOG_ONLY = new Set(["gemma4", "qwen3.6", "mimo-v2.5"]); // present for resume/audio, never a chat role
function checkModelRef(value, where, allowAnthropic) {
  if (typeof value !== "string") return;
  if (value.startsWith("nan/") && CATALOG_ONLY.has(value.slice(4)) && !/provider\.nan\.models/.test(where))
    fail(`${where}: "${value}" is catalog-only (benchmark 2026-09-21) and must not be assigned to a role`);
  if (value.startsWith("anthropic/")) {
    if (allowAnthropic !== value) fail(`${where}: Claude model "${value}" is not allowed here (only ${JSON.stringify(CLAUDE_SEATS)})`);
    return;
  }
  if (!value.startsWith("nan/")) { fail(`${where}: non-NaN model "${value}" (must be nan/*)`); return; }
  const id = value.slice(4);
  if (!KNOWN_MODELS.has(id)) fail(`${where}: unknown NaN model id "${id}"`);
}

let GLOBAL_BASH_RULES = [];
function checkOpencode(oc) {
  GLOBAL_BASH_RULES = Object.entries(oc?.permission?.bash ?? {});
  if (!oc) return;
  checkModelRef(oc.model, `${rel(P.oc)} .model`);
  checkModelRef(oc.small_model, `${rel(P.oc)} .small_model`);
  if (oc.model !== ROLE_DEFAULT) fail(`${rel(P.oc)}: .model must be ${ROLE_DEFAULT} (got ${oc.model})`);
  if (!["nan/deepseek-v4-flash-none", ROLE_DEFAULT].includes(oc.small_model)) fail(`${rel(P.oc)}: .small_model must be deepseek -none or -low (got ${oc.small_model})`);

  if (JSON.stringify([...(oc.enabled_providers ?? [])].sort()) !== JSON.stringify(["anthropic", "nan"]))
    fail(`${rel(P.oc)}: enabled_providers must be ["nan","anthropic"] (got ${JSON.stringify(oc.enabled_providers)})`);

  const provKeys = Object.keys(oc.provider ?? {}).sort();
  if (JSON.stringify(provKeys) !== JSON.stringify(["anthropic", "nan"]))
    fail(`${rel(P.oc)}: provider keys must be exactly ["anthropic","nan"] (got ${JSON.stringify(provKeys)})`);

  // Anthropic: exactly the two allowed models, each with the hard output cap; the key must NOT be in the config.
  const anth = oc.provider?.anthropic ?? {};
  if (anth.options?.apiKey) fail(`${rel(P.oc)}: provider.anthropic.options.apiKey must not be set (key lives in auth.json)`);
  if (JSON.stringify([...(anth.whitelist ?? [])].sort()) !== JSON.stringify([...ANTHROPIC_MODELS].sort()))
    fail(`${rel(P.oc)}: provider.anthropic.whitelist must be exactly ${JSON.stringify([...ANTHROPIC_MODELS])} (got ${JSON.stringify(anth.whitelist)})`);
  const anthIds = Object.keys(anth.models ?? {}).sort();
  if (JSON.stringify(anthIds) !== JSON.stringify([...ANTHROPIC_MODELS].sort()))
    fail(`${rel(P.oc)}: provider.anthropic.models must be exactly ${JSON.stringify([...ANTHROPIC_MODELS])} (got ${JSON.stringify(anthIds)})`);
  for (const [id, mm] of Object.entries(anth.models ?? {}))
    if (mm?.limit?.output !== ANTHROPIC_OUTPUT_CAP) fail(`${rel(P.oc)}: anthropic ${id}.limit.output must be ${ANTHROPIC_OUTPUT_CAP} (got ${mm?.limit?.output})`);

  const nan = oc.provider?.nan ?? {};
  if (nan.options?.baseURL !== BASE_URL)
    fail(`${rel(P.oc)}: provider.nan.options.baseURL must be ${BASE_URL} (got ${nan.options?.baseURL})`);
  // The NaN credential is an env REFERENCE (not a secret); dropping it silently makes every nan/* call 401
  // unless the shell happens to export NAN_API_KEY (regression caught in review 2026-09-21).
  if (nan.options?.apiKey !== "{env:NAN_API_KEY}")
    fail(`${rel(P.oc)}: provider.nan.options.apiKey must be "{env:NAN_API_KEY}" (got ${JSON.stringify(nan.options?.apiKey)})`);
  const scanDirs = [P.agentsDir, P.commandsDir, path.join(HOME, ".config/opencode/plugins"), path.join(HOME, ".config/opencode/scripts")];
  const listFiles = (d) => { try { return fs.readdirSync(d).filter((n) => !n.includes(".bak")).map((n) => path.join(d, n)).filter((f) => { try { return fs.statSync(f).isFile(); } catch { return false; } }); } catch { fail(`${rel(d)}: directory missing or unreadable`); return []; } }; // statSync follows symlinks
  const scanFiles = [P.oc, P.omo, P.oc2, P.agentsOc, ...scanDirs.flatMap(listFiles)];
  for (const f of scanFiles)
    if (/sk-(ant-)?[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|Bearer\s+[A-Za-z0-9._~+\/=-]{20,}/.test(readText(f) ?? "")) fail(`${rel(f)}: contains a literal secret-shaped value`);

  for (const [id, m] of Object.entries(nan.models ?? {})) {
    if (!KNOWN_MODELS.has(id)) fail(`${rel(P.oc)}: provider.nan.models has unknown model "${id}"`);
    if (id in CTX && m?.limit?.context !== CTX[id])
      fail(`${rel(P.oc)}: ${id}.limit.context must be ${CTX[id]} (got ${m?.limit?.context})`);
    if (id in ALIAS_BASE) {
      const [base, eff] = ALIAS_BASE[id];
      if (m?.id !== base) fail(`${rel(P.oc)}: alias ${id}.id must be "${base}" (got ${m?.id})`);
      if (m?.options?.nanReasoningEffort !== eff) fail(`${rel(P.oc)}: alias ${id}.options.nanReasoningEffort must be "${eff}" (got ${m?.options?.nanReasoningEffort})`);
    } else if (m?.options?.nanReasoningEffort !== undefined || m?.id !== undefined) {
      fail(`${rel(P.oc)}: ${id} is a base model and must not set id/nanReasoningEffort`);
    }
  }
  for (const id of Object.keys(ALIAS_BASE))
    if (!(id in (nan.models ?? {}))) fail(`${rel(P.oc)}: effort alias "${id}" missing from provider.nan.models`);
  if (oc.compaction?.reserved !== 50000) fail(`${rel(P.oc)}: compaction.reserved must be 50000 (got ${oc.compaction?.reserved})`);

  // Plugin pinned to an EXACT version. "@latest" is forbidden: opencode's Bun
  // cache never re-resolves it (stale-forever), so it silently pins anyway —
  // an exact pin makes the version explicit and upgrades deliberate.
  const omoPins = (oc.plugin ?? []).filter((p) => String(p).startsWith("oh-my-openagent@"));
  if (omoPins.length !== 1 || !/^oh-my-openagent@\d+\.\d+\.\d+$/.test(omoPins[0]))
    fail(`${rel(P.oc)}: plugin must include exactly one exact-version pin "oh-my-openagent@X.Y.Z" (got ${JSON.stringify(omoPins)})`);

  // Bash catastrophic denylist.
  const bash = oc.permission?.bash ?? {};
  for (const k of DENYLIST)
    if (bash[k] !== "deny") fail(`${rel(P.oc)}: permission.bash["${k}"] must be "deny" (got ${bash[k]})`);

  // Skill denylist.
  const skill = oc.permission?.skill ?? {};
  for (const k of SKILL_DENY)
    if (skill[k] !== "deny") fail(`${rel(P.oc)}: permission.skill["${k}"] must be "deny" (got ${skill[k]})`);

  // Engram MCP wired + enabled.
  if (oc.mcp?.engram?.enabled !== true)
    fail(`${rel(P.oc)}: mcp.engram.enabled must be true`);
  if (!(oc.mcp?.engram?.command ?? []).some((s) => String(s).includes("engram")))
    fail(`${rel(P.oc)}: mcp.engram.command must invoke engram`);

  // Protected-file globs (v3): path layer of file protection.
  const edit = oc.permission?.edit ?? {};
  for (const k of PROTECTED_EDIT_DENY)
    if (edit[k] !== "deny") fail(`${rel(P.oc)}: permission.edit["${k}"] must be "deny" (got ${edit[k]})`);
  if (edit["**/.env.example"] !== "allow")
    fail(`${rel(P.oc)}: permission.edit["**/.env.example"] must be "allow" (last-match override)`);

  // Claude rules mirrored via instructions glob (v3): single source of truth.
  const rulesGlob = path.join(HOME, ".claude/rules/*.md");
  if (!(oc.instructions ?? []).includes(rulesGlob))
    fail(`${rel(P.oc)}: instructions must include ${rel(rulesGlob)}`);
}

// harness-guards plugin (v3): file must exist and parse. Enforcement that is
// otherwise invisible until it silently stops loading.
function checkHarnessGuards() {
  const plugin = path.join(HOME, ".config/opencode/plugins/harness-guards.js");
  if (!fs.existsSync(plugin)) { fail(`${rel(plugin)}: missing (auto-enforcement plugin)`); return; }
  const res = spawnSync(process.execPath, ["--check", plugin], { encoding: "utf8" });
  if (res.status !== 0)
    fail(`${rel(plugin)}: does not parse (node --check: ${String(res.stderr).split("\n")[0]})`);
  // The post-omo effort hook is what makes the effort aliases real; without it every NaN seat
  // silently runs at omo's rewritten effort (verified 2026-09-21).
  const src = readText(plugin) ?? "";
  if (!src.includes('"chat.params"') || !src.includes("nanReasoningEffort"))
    fail(`${rel(plugin)}: must define a "chat.params" hook that applies options.nanReasoningEffort`);
  // Behavioural test of the hook (substring checks can be satisfied by comments).
  const t = spawnSync(process.execPath, [path.join(HOME, ".config/opencode/scripts/test-harness-guards-hook.mjs")], { encoding: "utf8", cwd: path.join(HOME, ".config/opencode") });
  if (t.status !== 0) fail(`${rel(plugin)}: hook tests failed: ${String(t.stderr || t.stdout).split("\n").filter(Boolean).slice(-2).join(" | ").slice(0, 300)}`);
}

const ROLE_DEFAULT = "nan/deepseek-v4-flash-low", ROLE_FALLBACK = "nan/glm5.3-flash-low";
const AGENT_MODEL = { "critic.md": "anthropic/claude-sonnet-5", "plan-critic.md": "anthropic/claude-opus-5", "fact-checker.md": "nan/glm5.3-flash-high" };
function checkOmo(omo) {
  if (!omo) return;
  for (const [label, group] of [["agents", omo.agents], ["categories", omo.categories]])
    for (const [name, cfg] of Object.entries(group ?? {})) {
      if (cfg.model !== ROLE_DEFAULT) fail(`${rel(P.omo)} ${label}.${name}.model must be ${ROLE_DEFAULT} (got ${cfg.model})`);
      const fbs = (cfg.fallback_models ?? []).map((f) => (typeof f === "string" ? f : f?.model));
      if (JSON.stringify(fbs) !== JSON.stringify([ROLE_FALLBACK])) fail(`${rel(P.omo)} ${label}.${name}.fallback_models must be [${ROLE_FALLBACK}] (got ${JSON.stringify(fbs)})`);
    }
  const walkModels = (group, label) => {
    for (const [name, cfg] of Object.entries(group ?? {})) {
      checkModelRef(cfg.model, `${rel(P.omo)} ${label}.${name}.model`);
      // omo's resolver rewrites reasoningEffort for these families (deepseek low->high); effort
      // must come from the model alias, never from this field.
      if (cfg.reasoningEffort !== undefined) fail(`${rel(P.omo)} ${label}.${name}: use an effort alias model instead of reasoningEffort`);
      for (const [i, fb] of (cfg.fallback_models ?? []).entries()) {
        const m = typeof fb === "string" ? fb : fb?.model;
        checkModelRef(m, `${rel(P.omo)} ${label}.${name}.fallback_models[${i}]`);
      }
    }
  };
  walkModels(omo.agents, "agents");
  walkModels(omo.categories, "categories");

  if (!(omo.disabled_agents ?? []).includes("hephaestus"))
    fail(`${rel(P.omo)}: disabled_agents must include "hephaestus"`);
  const pc = omo.background_task?.providerConcurrency ?? {};
  if (!(pc.nan >= 1 && pc.nan <= 6)) fail(`${rel(P.omo)}: providerConcurrency.nan must be 1..6 (key allows 7 concurrent; got ${pc.nan})`);
  if (pc.anthropic !== 1) fail(`${rel(P.omo)}: providerConcurrency.anthropic must be 1 (got ${pc.anthropic})`);
}

function checkOc2(oc2) {
  if (!oc2) return;
  // This secondary config has no enabled_providers; only its model matters.
  checkModelRef(oc2.model, `${rel(P.oc2)} .model`);
  if (oc2.model !== ROLE_DEFAULT) fail(`${rel(P.oc2)}: .model must be ${ROLE_DEFAULT} (got ${oc2.model})`);
}



function parseFrontmatter(text) {
  if (!text.startsWith("---\n")) return null;
  const end = text.indexOf("\n---", 4);
  if (end === -1) return null;
  try {
    const data = YAML.parse(text.slice(4, end));
    return data && typeof data === "object" ? data : null;
  } catch { return null; }
}

// Glob match as opencode's Wildcard.match: `*` any run, `?` one char (permission/index.ts evaluates with findLast).
function globMatch(pattern, value) {
  const re = new RegExp("^" + String(pattern).split("*").map((s) => s.split("?").map((x) => x.replace(/[.+^${}()|[\]\\]/g, "\\$&")).join(".")).join(".*") + "$");
  return re.test(value);
}

// Ground truth from opencode's own resolver: tools map + full ruleset after global and agent rules are merged.
function resolvedAgent(name) {
  const r = spawnSync("opencode", ["debug", "agent", name, "--pure"], { encoding: "utf8", env: process.env, timeout: 30000 });
  const out = r.stdout ?? ""; const i = out.indexOf("{");
  try { return i >= 0 ? JSON.parse(out.slice(i)) : null; } catch { return null; }
}

function checkAgentResolution(f, name) {
  const j = resolvedAgent(name);
  if (!j) { fail(`agents/${f}: opencode debug agent ${name} failed (is opencode on PATH?)`); return; }
  const rules = (j.permission ?? []).filter((p) => p.permission === "bash");
  for (const cmd of BASH_CANARIES) {
    const last = rules.slice().reverse().find((p) => globMatch(p.pattern, cmd));
    if (!last || last.action !== "deny") fail(`agents/${f}: resolved bash ruleset lets "${cmd}" through (last match: ${last ? `${last.pattern} -> ${last.action}` : "none"})`);
  }
  if (f in SEAT_DENY) {
    for (const tool of ["bash", "edit", "write", "task"]) if (j.tools?.[tool] !== false) fail(`agents/${f}: resolved tools.${tool} must be false (got ${j.tools?.[tool]})`);
  }
  if (f in CLAUDE_SEATS) {
    if (j.variant !== CLAUDE_VARIANT) fail(`agents/${f}: resolved variant must be ${CLAUDE_VARIANT} (got ${j.variant})`);
    if (`${j.model?.providerID}/${j.model?.modelID}` !== CLAUDE_SEATS[f]) fail(`agents/${f}: resolved model must be ${CLAUDE_SEATS[f]} (got ${j.model?.providerID}/${j.model?.modelID})`);
  }
  if (f === "plan-critic.md" && j.steps !== 6) fail(`agents/${f}: resolved steps must be 6 (got ${j.steps})`);
}

// Static emulation of opencode's merged bash ruleset (global map in order, then the agent's rules), evaluated last-match-wins.
// Covers mirror agents, which the live resolver cannot see, and pattern maps such as `bash: { "*": allow }`.
function bashRulesFor(agentBash) {
  const own = agentBash == null ? [] : typeof agentBash === "string" ? [["*", agentBash]] : Object.entries(agentBash);
  return [...GLOBAL_BASH_RULES, ...own];
}
function checkStaticBash(label, agentBash) {
  const rules = bashRulesFor(agentBash);
  for (const cmd of BASH_CANARIES) {
    const last = rules.slice().reverse().find(([pat]) => globMatch(pat, cmd));
    if (!last || last[1] !== "deny") fail(`${label}: merged bash rules let "${cmd}" through (last match: ${last ? `${last[0]} -> ${last[1]}` : "none"})`);
  }
}

function checkMarkdownDir(dir, required, kind) {
  let files;
  try { files = fs.readdirSync(dir); }
  catch { return; } // dir may not exist; not a hard failure
  for (const f of files) {
    if (!f.endsWith(".md")) continue; // every *.md is a loadable agent/command, backups included
    const full = path.join(dir, f);
    const text = readText(full);
    if (text == null) continue;
    const fm = parseFrontmatter(text);
    if (!fm) { fail(`${rel(full)}: missing or malformed frontmatter`); continue; }
    const perm = fm.permission && typeof fm.permission === "object" ? fm.permission : {};
    for (const key of required)
      if (!fm[key]) fail(`${rel(full)}: frontmatter missing "${key}"`);
    if (fm.model) checkModelRef(fm.model, `${rel(full)} frontmatter.model`, CLAUDE_SEATS[f]);
    if (kind === "agents") {
      const want = AGENT_MODEL[f] ?? ROLE_DEFAULT;
      if (fm.model !== want) fail(`${rel(full)}: model must be ${want} (got ${fm.model})`);
      // Structural checks on the parsed `permission` mapping (decoys in description/body cannot satisfy them).
      if (perm.bash === "allow") fail(`${rel(full)}: flat 'bash: allow' overrides the global bash denylist (last match wins); remove it or use a pattern map`);
      checkStaticBash(rel(full), perm.bash);
      if ("write" in perm) fail(`${rel(full)}: 'write:' is not an opencode permission key (the write tool is gated by 'edit'); use edit`);
      for (const tool of SEAT_DENY[f] ?? []) if (perm[tool] !== "deny") fail(`${rel(full)}: permission.${tool} must be deny (got ${JSON.stringify(perm[tool])})`);
      if (f in CLAUDE_SEATS) {
        if (fm.temperature !== undefined || fm.top_p !== undefined) fail(`${rel(full)}: Claude 5-family models reject non-default temperature/top_p; remove them`);
        if (fm.variant !== CLAUDE_VARIANT) fail(`${rel(full)}: frontmatter variant must be ${CLAUDE_VARIANT} (got ${fm.variant})`);
        if (f === "plan-critic.md" && Number(fm.maxSteps) !== 6) fail(`${rel(full)}: maxSteps must be 6 (got ${fm.maxSteps})`);
      }
      if (dir === P.agentsDir) checkAgentResolution(f, f.replace(/\.md$/, ""));
    }
    if (kind === "commands" && fm.model) fail(`${rel(full)}: commands must not override the model (roles live in agents/)`);
  }
  if (kind === "agents") for (const f of Object.keys(CLAUDE_SEATS)) if (!files.includes(f)) fail(`${rel(path.join(dir, f))}: required Claude seat file is missing`);
}

function checkSkillsInventory() {
  const dir = path.join(HOME, ".agents/skills");
  let entries;
  try { entries = fs.readdirSync(dir).filter((e) => !e.startsWith(".")); }
  catch { fail(`${rel(dir)}: directory missing or unreadable`); return; }
  for (const e of entries)
    if (!EXPECTED_SKILLS.has(e)) fail(`${rel(dir)}: unexpected skill "${e}" (add deliberately to EXPECTED_SKILLS or remove it)`);
  for (const s of EXPECTED_SKILLS)
    if (!entries.includes(s)) fail(`${rel(dir)}: expected skill "${s}" is missing`);
  // webapp-testing must stay a symlink to the canonical ~/.claude/skills copy
  // (single emoji-free source; both discovery paths must resolve identically).
  const link = path.join(dir, "webapp-testing/SKILL.md");
  const target = path.join(HOME, ".claude/skills/webapp-testing/SKILL.md");
  try {
    if (!fs.lstatSync(link).isSymbolicLink())
      fail(`${rel(link)}: must be a symlink to ${rel(target)}`);
    else if (path.resolve(path.dirname(link), fs.readlinkSync(link)) !== target)
      fail(`${rel(link)}: symlink must resolve to ${rel(target)}`);
  } catch { fail(`${rel(link)}: missing (expected symlink to ${rel(target)})`); }
}

// ---- run ----
checkOpencode(parseJson(P.oc, { jsonc: true }));
checkOmo(parseJson(P.omo));
checkOc2(parseJson(P.oc2));
// Zed removed 2026-09-21 (owner decision): no Zed config checks, no AGENTS.md parity target.
if (/\bZed\b/.test(readText(P.agentsOc) ?? "")) fail(`${rel(P.agentsOc)}: mentions Zed, which was uninstalled 2026-09-21`);
checkSkillsInventory();
checkHarnessGuards();
checkMarkdownDir(P.agentsDir, ["description", "mode"], "agents");
checkMarkdownDir(P.commandsDir, ["description"], "commands");
checkMarkdownDir(P.mirrorAgentsDir, ["description", "mode"], "agents"); // stale mirror = one install.sh away from reverting the live policy

if (process.argv.includes("--json")) {
  console.log(JSON.stringify({ ok: errors.length === 0, errors }, null, 2));
} else if (errors.length) {
  console.error("Harness check FAILED:");
  for (const e of errors) console.error(`  - ${e}`);
} else {
  console.log("Harness check passed.");
}
process.exit(errors.length ? 1 : 0);
