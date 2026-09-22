#!/usr/bin/env node
// Static invariants for the pi harness (mirror of ~/.config/opencode/scripts/check-harness.mjs for opencode).
// Policy: NaN for everything, Claude only on the four gentle-pi review lenses at thinking low with an 8192-token cap.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const HOME = os.homedir();
const P = {
  models: path.join(HOME, ".pi/agent/models.json"),
  settings: path.join(HOME, ".pi/agent/settings.json"),
  auth: path.join(HOME, ".pi/agent/auth.json"),
  routing: path.join(HOME, ".pi/gentle-ai/models.json"),
  agents: path.join(HOME, ".pi/agent/AGENTS.md"),
  guard: path.join(HOME, ".pi/agent/extensions/harness-guards.ts"),
  gentleAgents: path.join(HOME, ".pi/agent/npm/node_modules/gentle-pi/assets/agents"),
  materialized: path.join(HOME, ".pi/agent/subagents.json"),
  materializedAgents: path.join(HOME, ".pi/agent/agents"),
};
const NAN_BASE = "https://api.nan.builders/v1";
const NAN_MODELS = { "deepseek-v4-flash": 1048575, "glm5.3-flash": 1048576, "mimo-v2.5": 1048576, "gemma4": 262144, "qwen3.6": 262144 };
const CLAUDE_IDS = ["claude-sonnet-5", "claude-opus-5"];
const CLAUDE_CAP = 8192;
const REVIEW_SEATS = ["review-risk", "review-reliability", "review-resilience", "review-readability"];
const REVIEW_MODEL = "anthropic/claude-sonnet-5";
const DEFAULT_MODEL = "nan/deepseek-v4-flash";
const SECOND_FAMILY = { "jd-judge-b": "nan/glm5.3-flash" };

const errors = [];
const fail = (m) => errors.push(m);
const rel = (p) => p.replace(HOME, "~");
const readJson = (p) => { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) { fail(`${rel(p)}: unreadable or invalid JSON (${e.message})`); return null; } };

// ---- models.json
const models = readJson(P.models);
if (models) {
  const nan = models.providers?.nan ?? {};
  if (nan.baseUrl !== NAN_BASE) fail(`${rel(P.models)}: providers.nan.baseUrl must be ${NAN_BASE}`);
  if (nan.api !== "openai-completions") fail(`${rel(P.models)}: providers.nan.api must be openai-completions`);
  if (nan.apiKey !== "$NAN_API_KEY") fail(`${rel(P.models)}: providers.nan.apiKey must be the env reference "$NAN_API_KEY" (got ${JSON.stringify(nan.apiKey)})`);
  if (nan.compat?.thinkingFormat !== "reasoning_effort" || nan.compat?.supportsReasoningEffort !== true) fail(`${rel(P.models)}: providers.nan.compat must set thinkingFormat reasoning_effort + supportsReasoningEffort`);
  const ids = (nan.models ?? []).map((m) => m.id).sort();
  if (JSON.stringify(ids) !== JSON.stringify(Object.keys(NAN_MODELS).sort())) fail(`${rel(P.models)}: nan models must be exactly ${Object.keys(NAN_MODELS).join(", ")} (got ${ids.join(", ")})`);
  for (const m of nan.models ?? []) {
    if (m.contextWindow !== NAN_MODELS[m.id]) fail(`${rel(P.models)}: ${m.id}.contextWindow must be ${NAN_MODELS[m.id]}`);
    if (m.reasoning !== true) fail(`${rel(P.models)}: ${m.id}.reasoning must be true`);
    if ((m.input ?? []).some((x) => !["text", "image"].includes(x))) fail(`${rel(P.models)}: ${m.id}.input may only contain text/image (pi rejects the whole file otherwise)`);
    const map = m.thinkingLevelMap ?? {};
    if (map.low !== "low" || map.off !== "none") fail(`${rel(P.models)}: ${m.id}.thinkingLevelMap must map low->low and off->none`);
  }
  const anth = models.providers?.anthropic ?? {};
  if (anth.apiKey) fail(`${rel(P.models)}: providers.anthropic.apiKey must not be set (key lives in auth.json)`);
  if (anth.baseUrl) fail(`${rel(P.models)}: providers.anthropic.baseUrl must not be overridden (a leftover proxy URL sends the key and every review to that endpoint)`);
  if (anth.models) fail(`${rel(P.models)}: providers.anthropic.models must not redefine built-in models; use modelOverrides`);
  for (const id of CLAUDE_IDS) if (anth.modelOverrides?.[id]?.maxTokens !== CLAUDE_CAP) fail(`${rel(P.models)}: anthropic.modelOverrides.${id}.maxTokens must be ${CLAUDE_CAP}`);
  const extra = Object.keys(anth.modelOverrides ?? {}).filter((k) => !CLAUDE_IDS.includes(k));
  if (extra.length) fail(`${rel(P.models)}: unexpected anthropic overrides ${extra.join(", ")}`);
  const provs = Object.keys(models.providers ?? {}).sort();
  if (JSON.stringify(provs) !== JSON.stringify(["anthropic", "nan"])) fail(`${rel(P.models)}: providers must be exactly anthropic + nan (got ${provs.join(", ")})`);
}

// ---- settings.json
const settings = readJson(P.settings);
if (settings) {
  if (settings.defaultProvider !== "nan" || settings.defaultModel !== "deepseek-v4-flash") fail(`${rel(P.settings)}: default must be nan/deepseek-v4-flash`);
  if (settings.defaultThinkingLevel !== "low") fail(`${rel(P.settings)}: defaultThinkingLevel must be low`);
  for (const id of CLAUDE_IDS) if (settings.modelThinkingLevels?.[`anthropic/${id}`] !== "low") fail(`${rel(P.settings)}: modelThinkingLevels.anthropic/${id} must be low`);
  const enabled = settings.enabledModels ?? [];
  const wantEnabled = ["nan/*", ...CLAUDE_IDS.map((id) => `anthropic/${id}`)];
  if (JSON.stringify([...enabled].sort()) !== JSON.stringify([...wantEnabled].sort())) fail(`${rel(P.settings)}: enabledModels must be exactly ${wantEnabled.join(", ")}`);
  if (!(settings.packages ?? []).some((p) => /^npm:gentle-pi(@|$)/.test(p))) fail(`${rel(P.settings)}: packages must include npm:gentle-pi`);
  if (settings.enableAnalytics !== false) fail(`${rel(P.settings)}: enableAnalytics must be false`);
}

// ---- auth.json: present, private, only anthropic
try {
  const st = fs.statSync(P.auth);
  if ((st.mode & 0o077) !== 0) fail(`${rel(P.auth)}: mode must be 600 (got ${(st.mode & 0o777).toString(8)})`);
  const auth = readJson(P.auth);
  if (auth && (Object.keys(auth).join() !== "anthropic" || auth.anthropic?.type !== "api_key")) fail(`${rel(P.auth)}: must hold exactly one anthropic api_key entry`);
} catch { fail(`${rel(P.auth)}: missing`); }

// ---- gentle-pi per-agent routing
const routing = readJson(P.routing);
if (routing) {
  let shipped = [];
  try { shipped = fs.readdirSync(P.gentleAgents).filter((f) => f.endsWith(".md")).map((f) => f.replace(/\.md$/, "")); } catch { fail(`${rel(P.gentleAgents)}: gentle-pi agents dir missing (is gentle-pi installed?)`); }
  for (const a of shipped) if (!(a in routing)) fail(`${rel(P.routing)}: shipped agent ${a} has no routing entry (would inherit the session model, which may be Claude)`);
  for (const [a, r] of Object.entries(routing)) {
    const ref = typeof r === "string" ? r : r?.model;
    const thinking = typeof r === "string" ? undefined : r?.thinking;
    if (REVIEW_SEATS.includes(a)) {
      if (ref !== REVIEW_MODEL || thinking !== "low") fail(`${rel(P.routing)}: ${a} must be ${REVIEW_MODEL} at thinking low (got ${ref}:${thinking})`);
    } else if (a in SECOND_FAMILY) {
      if (ref !== SECOND_FAMILY[a]) fail(`${rel(P.routing)}: ${a} must be ${SECOND_FAMILY[a]} (got ${ref})`);
    } else if (ref !== DEFAULT_MODEL || thinking !== "low") fail(`${rel(P.routing)}: ${a} must be ${DEFAULT_MODEL} at thinking low (got ${ref}:${thinking}); Claude is for the review lenses only`);
    if (a === "orchestrator" && String(ref).startsWith("anthropic/")) fail(`${rel(P.routing)}: the orchestrator must never run on Anthropic`);
  }
}

// ---- effective routing: gentle-pi resolves subagents.json first, then agent frontmatter; both must match the policy
const mat = fs.existsSync(P.materialized) ? readJson(P.materialized) : null;
if (mat) {
  for (const [a, prof] of Object.entries(mat.model_profiles ?? {})) {
    const want = REVIEW_SEATS.includes(a) ? [REVIEW_MODEL, "low"] : a in SECOND_FAMILY ? [SECOND_FAMILY[a], "high"] : [DEFAULT_MODEL, "low"];
    if (prof?.model !== want[0] || prof?.effort !== want[1]) fail(`${rel(P.materialized)}: ${a} resolves to ${prof?.model}:${prof?.effort}, policy is ${want[0]}:${want[1]}`);
  }
}
try {
  for (const f of fs.readdirSync(P.materializedAgents).filter((x) => x.endsWith(".md"))) {
    const text = fs.readFileSync(path.join(P.materializedAgents, f), "utf8"); const end = text.indexOf("\n---", 4);
    const fm = text.slice(0, end); const name = f.replace(/\.md$/, "");
    const model = (fm.match(/^model:\s*(\S+)/m) ?? [])[1]; const thinking = (fm.match(/^thinking:\s*(\S+)/m) ?? [])[1];
    const want = REVIEW_SEATS.includes(name) ? [REVIEW_MODEL, "low"] : name in SECOND_FAMILY ? [SECOND_FAMILY[name], "high"] : [DEFAULT_MODEL, "low"];
    if (model && (model !== want[0] || thinking !== want[1])) fail(`~/.pi/agent/agents/${f}: frontmatter routes to ${model}:${thinking}, policy is ${want[0]}:${want[1]}`);
    if (!model && REVIEW_SEATS.includes(name)) fail(`~/.pi/agent/agents/${f}: review seat has no pinned model (would inherit the session model)`);
  }
} catch { /* no materialized agents yet */ }

// ---- guard extension, AGENTS.md, secret shapes
if (!fs.existsSync(P.guard)) fail(`${rel(P.guard)}: harness-guards extension missing (pi has no permission layer)`);
else {
  const g = fs.readFileSync(P.guard, "utf8");
  // Structure only; behavior is asserted by test-pi-guards.mjs below.
  for (const must of ['pi.on("tool_call"', 'pi.on("before_agent_start"', 'pi.on("session_start"', 'pi.on("model_select"', 'pi.on("input"', "setModel(", "gentle_review_capture_group"]) if (!g.includes(must)) fail(`${rel(P.guard)}: missing ${must}`);
}
// Behavioral tests: import the extension with a fake ExtensionAPI and assert decisions (source strings alone prove nothing).
{
  const { spawnSync } = await import("node:child_process");
  const t = spawnSync(process.execPath, ["--experimental-strip-types", path.join(HOME, ".pi/agent/scripts/test-pi-guards.mjs")], { encoding: "utf8" });
  if (t.status !== 0 || !/behavioral tests passed/.test(t.stdout)) fail(`test-pi-guards.mjs failed:\n${(t.stderr || t.stdout).split("\n").filter(Boolean).slice(-6).join("\n")}`);
}
if (!fs.existsSync(P.agents)) fail(`${rel(P.agents)}: global AGENTS.md missing`);
else if (!/review-risk/.test(fs.readFileSync(P.agents, "utf8"))) fail(`${rel(P.agents)}: must name the Claude review seats`);
for (const f of [P.models, P.settings, P.routing, P.agents, P.guard])
  if (fs.existsSync(f) && /sk-(ant-)?[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}/.test(fs.readFileSync(f, "utf8"))) fail(`${rel(f)}: contains a literal secret-shaped value`);
// gentle-ai sync writes skills into the SHARED ~/.agents/skills; they must live in ~/.pi/agent/skills so opencode's inventory stays untouched.
for (const s of ["sdd-apply", "sdd-verify", "work-unit-commits", "_shared"]) if (fs.existsSync(path.join(HOME, ".agents/skills", s))) fail(`~/.agents/skills/${s}: gentle skill leaked into the shared skills dir; move it to ~/.pi/agent/skills`);

if (errors.length) { console.error("pi harness check FAILED:"); for (const e of errors) console.error(`  - ${e}`); process.exit(1); }
console.log("pi harness check passed.");
