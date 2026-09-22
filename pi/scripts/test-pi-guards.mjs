// Behavioral tests for ~/.pi/agent/extensions/harness-guards.ts, run with:
//   node --experimental-strip-types ~/.pi/agent/scripts/test-pi-guards.mjs
// A fake ExtensionAPI collects the handlers; each case asserts the observable decision, not source strings.
import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const modPath = path.join(os.homedir(), ".pi/agent/extensions/harness-guards.ts");
const mod = await import(pathToFileURL(modPath).href);
const handlers = {};
let setModelCalls = [];
const pi = {
	on: (name, fn) => { (handlers[name] ??= []).push(fn); },
	setModel: async (m) => { setModelCalls.push(m); return pi.__setModelOk; },
	__setModelOk: true,
};
mod.default(pi);
const call = (name, event, ctx) => Promise.all((handlers[name] ?? []).map((h) => h(event, ctx))).then((r) => r.find((x) => x !== undefined));

// --- bash denylist: ordinary spellings must be blocked, normal work must pass
const blocked = [
	"git reset --hard HEAD~1", "env /usr/bin/git reset --hard HEAD~1", "git -C . reset --hard HEAD~1", "cd repo && git reset --hard",
	"git push --force origin main", "git push origin main -f", "git clean -fd", "git clean -f -d", "git clean -xdf",
	"rm -rf /", "rm -rf ~", "rm -rf ~/*", "rm -rf -- /", "rm -r -f $HOME", "sudo rm -rf /*",
	"terraform destroy -auto-approve", "terraform -chdir=infra destroy", "terraform force-unlock abc",
	"kubectl delete namespace prod", "kubectl --context prod delete namespace x", "kubectl delete ns x",
	"pi -p --no-extensions 'x'", "pi auth print-api-key --provider anthropic > config.json", "pi auth check --provider anthropic --credentials",
	"cat ~/.pi/agent/auth.json", "cat ~/.pi/agent/auth?json", "cp ~/.pi/agent/auth.json ./config.json", "wc -c < ~/.pi/agent/auth.json",
	"cat .env", "cat .env.production", "cp terraform.tfstate /tmp/x", "cat ~/.ssh/id_rsa", "cat secrets/prod.yaml", "openssl x509 -in server.pem",
];
const allowed = [
	"git status", "git push --force-with-lease origin main", "git reset --soft HEAD~1", "git clean -n", "rm -rf ./build", "rm -rf node_modules",
	"terraform plan", "terraform destroy-preview", "kubectl delete pod x", "kubectl get ns", "pi --version", "cat README.md", "cat .envrc.example",
	"echo harness-ok", "ls -la", "grep -r TODO src", "cat environment.yaml", "python3 -c 'print(1)'",
];
for (const c of blocked) { const r = await call("tool_call", { toolName: "bash", input: { command: c } }); assert.ok(r?.block, `should block: ${c}`); }
for (const c of allowed) { const r = await call("tool_call", { toolName: "bash", input: { command: c } }); assert.equal(r, undefined, `should allow: ${c}`); }

// --- protected paths through file tools (read included: reading auth.json is how a key gets copied into a repo file)
for (const tool of ["read", "write", "edit", "grep", "find", "ls"]) {
	assert.ok((await call("tool_call", { toolName: tool, input: { path: `${os.homedir()}/.pi/agent/auth.json` } }))?.block, `${tool} auth.json`);
	assert.ok((await call("tool_call", { toolName: tool, input: { path: "infra/terraform.tfstate" } }))?.block, `${tool} tfstate`);
	assert.equal(await call("tool_call", { toolName: tool, input: { path: "src/index.ts" } }), undefined, `${tool} ordinary file`);
}
// --- concurrent lens capture blocked, single capture allowed
assert.ok((await call("tool_call", { toolName: "gentle_review_capture_group", input: {} }))?.block);
assert.equal(await call("tool_call", { toolName: "gentle_review_capture", input: {} }), undefined);

// --- Anthropic fence: switches back to NaN; fails closed when the fallback is unavailable
const nan = { provider: "nan", id: "deepseek-v4-flash" };
const mkCtx = (model, findOk = true) => ({ model, hasUI: false, modelRegistry: { find: (p, i) => (findOk && p === "nan" && i === "deepseek-v4-flash" ? nan : undefined) } });
setModelCalls = [];
await call("session_start", { reason: "startup" }, mkCtx({ provider: "anthropic", id: "claude-sonnet-5" }));
assert.deepEqual(setModelCalls, [nan], "session_start must switch an Anthropic session model back to NaN");
setModelCalls = [];
await call("model_select", { model: { provider: "anthropic", id: "claude-opus-5" }, source: "set" }, mkCtx({ provider: "anthropic", id: "claude-opus-5" }));
assert.deepEqual(setModelCalls, [nan], "model_select to Anthropic must switch back");
setModelCalls = [];
assert.deepEqual(await call("input", { text: "hi", source: "interactive" }, mkCtx({ provider: "anthropic", id: "claude-sonnet-5" })), { action: "continue" });
assert.deepEqual(setModelCalls, [nan]);
pi.__setModelOk = false;
assert.deepEqual(await call("input", { text: "hi", source: "interactive" }, mkCtx({ provider: "anthropic", id: "claude-sonnet-5" })), { action: "handled" }, "no NaN fallback -> input swallowed, nothing sent to Claude");
assert.deepEqual(await call("input", { text: "hi", source: "interactive" }, mkCtx({ provider: "anthropic", id: "claude-sonnet-5" }, false)), { action: "handled" });
pi.__setModelOk = true;
setModelCalls = [];
assert.deepEqual(await call("input", { text: "hi", source: "interactive" }, mkCtx(nan)), { action: "continue" });
assert.deepEqual(setModelCalls, [], "NaN session model is left alone");
const msg = await call("before_agent_start", { prompt: "x" }, mkCtx({ provider: "anthropic", id: "claude-sonnet-5" }));
assert.ok(msg?.message?.content.includes("switched"), "before_agent_start injects the switch note");

console.log("pi guard behavioral tests passed");
