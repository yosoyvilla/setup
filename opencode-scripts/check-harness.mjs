#!/usr/bin/env node
// Harness invariant checker for the NaN-only opencode + Zed setup.
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

const HOME = os.homedir();
const P = {
  oc: path.join(HOME, ".config/opencode/opencode.jsonc"),
  omo: path.join(HOME, ".config/opencode/oh-my-openagent.json"),
  oc2: path.join(HOME, ".opencode/opencode.json"),
  zed: path.join(HOME, ".config/zed/settings.json"),
  agentsOc: path.join(HOME, ".config/opencode/AGENTS.md"),
  agentsZed: path.join(HOME, ".config/zed/AGENTS.md"),
  agentsDir: path.join(HOME, ".config/opencode/agents"),
  commandsDir: path.join(HOME, ".config/opencode/commands"),
};

const KNOWN_MODELS = new Set([
  "qwen3.6", "deepseek-v4-flash", "mimo-v2.5", "gemma4",
  "whisper", "kokoro", "qwen3-embedding", "rerank", "flux-2-klein",
]);
const CTX = { "qwen3.6": 262144, "gemma4": 262144, "deepseek-v4-flash": 1000000, "mimo-v2.5": 1000000 };
const BASE_URL = "https://api.nan.builders/v1";
const FIM_URL = "https://api.nan.builders/v1/completions";
const DENYLIST = [
  "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf ~/*",
  "git push --force*", "git push -f*", "git reset --hard*", "git clean -fd*",
  "terraform destroy*", "terraform force-unlock*", "kubectl delete namespace*",
];
const SKILL_DENY = ["terraform-devops", "incident-triage", "spec-first"];
// Skills inventory for ~/.agents/skills (shared by opencode + Zed). A new or
// removed skill silently changes the model-facing tool surface of BOTH tools,
// so additions must be deliberate: update this list when you intend the change.
const EXPECTED_SKILLS = new Set([
  "algorithmic-art", "canvas-design", "computer-use", "find-skills",
  "frontend-design", "incident-triage", "k8s-debug", "karpathy-guidelines",
  "orca-cli", "skill-creator", "spec-first", "terraform-devops",
  "validating-packages", "verifying-changes", "webapp-testing",
  // Imported 2026-07-07 from cursor/plugins cursor-team-kit (MIT). Anthropic
  // proprietary skills (docx/xlsx/pptx/pdf) were deliberately NOT imported:
  // their LICENSE.txt forbids copies outside Anthropic services.
  "deslop", "thermo-nuclear-code-quality-review", "verify-this",
  // Built 2026-07-07 from the Swipe visual audit (dead-utilities root cause):
  "visual-qa",
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

// A model reference is valid if it is "nan/<id>" with <id> in KNOWN_MODELS.
function checkModelRef(value, where) {
  if (typeof value !== "string") return;
  if (!value.startsWith("nan/")) { fail(`${where}: non-NaN model "${value}" (must be nan/*)`); return; }
  const id = value.slice(4);
  if (!KNOWN_MODELS.has(id)) fail(`${where}: unknown NaN model id "${id}"`);
}

function checkOpencode(oc) {
  if (!oc) return;
  checkModelRef(oc.model, `${rel(P.oc)} .model`);
  checkModelRef(oc.small_model, `${rel(P.oc)} .small_model`);

  if (JSON.stringify(oc.enabled_providers) !== JSON.stringify(["nan"]))
    fail(`${rel(P.oc)}: enabled_providers must be ["nan"] (got ${JSON.stringify(oc.enabled_providers)})`);

  const provKeys = Object.keys(oc.provider ?? {});
  if (JSON.stringify(provKeys) !== JSON.stringify(["nan"]))
    fail(`${rel(P.oc)}: provider keys must be exactly ["nan"] (got ${JSON.stringify(provKeys)})`);

  const nan = oc.provider?.nan ?? {};
  if (nan.options?.baseURL !== BASE_URL)
    fail(`${rel(P.oc)}: provider.nan.options.baseURL must be ${BASE_URL} (got ${nan.options?.baseURL})`);

  for (const [id, m] of Object.entries(nan.models ?? {})) {
    if (!KNOWN_MODELS.has(id)) fail(`${rel(P.oc)}: provider.nan.models has unknown model "${id}"`);
    if (id in CTX && m?.limit?.context !== CTX[id])
      fail(`${rel(P.oc)}: ${id}.limit.context must be ${CTX[id]} (got ${m?.limit?.context})`);
  }

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
}

function checkOmo(omo) {
  if (!omo) return;
  const walkModels = (group, label) => {
    for (const [name, cfg] of Object.entries(group ?? {})) {
      checkModelRef(cfg.model, `${rel(P.omo)} ${label}.${name}.model`);
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
}

function checkOc2(oc2) {
  if (!oc2) return;
  // This secondary config has no enabled_providers; only its model matters.
  checkModelRef(oc2.model, `${rel(P.oc2)} .model`);
}

function checkZed(zed) {
  if (!zed) return;
  const a = zed.agent ?? {};
  const provFields = ["default_model", "commit_message_model", "thread_summary_model", "subagent_model"];
  for (const f of provFields)
    if (a[f] && a[f].provider !== "nan")
      fail(`${rel(P.zed)}: agent.${f}.provider must be "nan" (got ${a[f].provider})`);

  for (const [i, m] of (a.favorite_models ?? []).entries())
    if (m.provider !== "nan") fail(`${rel(P.zed)}: agent.favorite_models[${i}].provider must be "nan"`);
  for (const [i, m] of (a.model_parameters ?? []).entries())
    if (m.provider !== "nan") fail(`${rel(P.zed)}: agent.model_parameters[${i}].provider must be "nan"`);

  const oc = zed.language_models?.openai_compatible ?? {};
  if (!("nan" in oc)) fail(`${rel(P.zed)}: language_models.openai_compatible must define "nan"`);
  if (Object.keys(oc).some((k) => k !== "nan"))
    fail(`${rel(P.zed)}: language_models.openai_compatible has non-nan provider(s): ${Object.keys(oc).filter((k) => k !== "nan")}`);

  const nan = oc.nan ?? {};
  if (nan.api_url !== BASE_URL)
    fail(`${rel(P.zed)}: openai_compatible.nan.api_url must be ${BASE_URL} (got ${nan.api_url})`);
  for (const [i, m] of (nan.available_models ?? []).entries()) {
    if (!KNOWN_MODELS.has(m.name)) fail(`${rel(P.zed)}: available_models[${i}].name unknown "${m.name}"`);
    if (m.name in CTX && m.max_tokens !== CTX[m.name])
      fail(`${rel(P.zed)}: available_models "${m.name}".max_tokens must be ${CTX[m.name]} (got ${m.max_tokens})`);
  }

  const fim = zed.edit_predictions?.open_ai_compatible_api ?? {};
  if (fim.api_url !== FIM_URL)
    fail(`${rel(P.zed)}: edit_predictions api_url must be ${FIM_URL} (got ${fim.api_url})`);
  checkModelRef(`nan/${fim.model}`, `${rel(P.zed)} edit_predictions.model`);

  if (!zed.context_servers?.engram)
    fail(`${rel(P.zed)}: context_servers.engram must be defined`);
}

function checkAgentsParity() {
  const a = readText(P.agentsOc), b = readText(P.agentsZed);
  if (a == null || b == null) return;
  const ha = crypto.createHash("sha256").update(a).digest("hex");
  const hb = crypto.createHash("sha256").update(b).digest("hex");
  if (ha !== hb) fail(`AGENTS.md drift: sha256 mismatch between ${rel(P.agentsOc)} and ${rel(P.agentsZed)}`);
}

function parseFrontmatter(text) {
  if (!text.startsWith("---\n")) return null;
  const end = text.indexOf("\n---", 4);
  if (end === -1) return null;
  const data = {};
  for (const line of text.slice(4, end).split("\n")) {
    const m = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/);
    if (m) data[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  return data;
}

function checkMarkdownDir(dir, required) {
  let files;
  try { files = fs.readdirSync(dir); }
  catch { return; } // dir may not exist; not a hard failure
  for (const f of files) {
    if (!f.endsWith(".md") || f.includes(".bak")) continue; // exclude backups
    const full = path.join(dir, f);
    const text = readText(full);
    if (text == null) continue;
    const fm = parseFrontmatter(text);
    if (!fm) { fail(`${rel(full)}: missing or malformed frontmatter`); continue; }
    for (const key of required)
      if (!fm[key]) fail(`${rel(full)}: frontmatter missing "${key}"`);
    if (fm.model) checkModelRef(fm.model, `${rel(full)} frontmatter.model`);
  }
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
checkZed(parseJson(P.zed));
checkAgentsParity();
checkSkillsInventory();
checkHarnessGuards();
checkMarkdownDir(P.agentsDir, ["description", "mode"]);
checkMarkdownDir(P.commandsDir, ["description"]);

if (process.argv.includes("--json")) {
  console.log(JSON.stringify({ ok: errors.length === 0, errors }, null, 2));
} else if (errors.length) {
  console.error("Harness check FAILED:");
  for (const e of errors) console.error(`  - ${e}`);
} else {
  console.log("Harness check passed.");
}
process.exit(errors.length ? 1 : 0);
