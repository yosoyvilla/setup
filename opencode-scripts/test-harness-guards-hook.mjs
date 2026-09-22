#!/usr/bin/env node
// Exercises plugins/harness-guards.js "chat.params" with synthetic inputs. Run: node scripts/test-harness-guards-hook.mjs
import assert from "node:assert/strict"
import { HarnessGuards } from "../plugins/harness-guards.js"
const hooks = await HarnessGuards({ client: { session: { get: async () => ({ data: {} }) } }, directory: process.cwd(), $: async () => ({}) })
const hook = hooks["chat.params"]; assert.equal(typeof hook, "function", "chat.params hook missing")
const call = (input, options = {}) => { const output = { options: { ...options } }; return hook(input, output).then(() => output) }
// 1. NaN alias carrier -> reasoningEffort, carrier removed
let o = await call({ provider: { id: "nan" }, model: { id: "deepseek-v4-flash" }, agent: "sisyphus" }, { nanReasoningEffort: "none" })
assert.equal(o.options.reasoningEffort, "none"); assert.equal("nanReasoningEffort" in o.options, false)
// 2. invalid effort value -> throws
await assert.rejects(call({ provider: { id: "nan" }, model: { id: "deepseek-v4-flash" }, agent: "x" }, { nanReasoningEffort: "turbo" }))
// 3. carrier on a non-NaN provider is dropped, not forwarded
o = await call({ provider: { id: "anthropic" }, model: { id: "claude-sonnet-5" }, agent: "critic" }, { nanReasoningEffort: "low" })
assert.equal(o.options.reasoningEffort, undefined); assert.equal("nanReasoningEffort" in o.options, false)
// 4. allowed seats get the cap; wrong pairing and other agents are blocked
o = await call({ provider: { id: "anthropic" }, model: { id: "claude-sonnet-5" }, agent: "critic" }); assert.equal(o.maxOutputTokens, 8192)
o = await call({ provider: { id: "anthropic" }, model: { id: "claude-opus-5" }, agent: { name: "plan-critic" } }); assert.equal(o.maxOutputTokens, 8192)
await assert.rejects(call({ provider: { id: "anthropic" }, model: { id: "claude-opus-5" }, agent: "critic" }), /BLOCKED/)
await assert.rejects(call({ provider: { id: "anthropic" }, model: { id: "claude-sonnet-5" }, agent: "Sisyphus - ultraworker" }), /BLOCKED/)
await assert.rejects(call({ provider: { id: "anthropic" }, model: { id: "claude-sonnet-5" } }), /BLOCKED/)
// 5. NaN requests without a carrier are untouched
o = await call({ provider: { id: "nan" }, model: { id: "glm5.3-flash" }, agent: "x" }, { reasoningEffort: "high" }); assert.equal(o.options.reasoningEffort, "high"); assert.equal(o.maxOutputTokens, undefined)
await assert.rejects(call({ provider: { id: "anthropic" }, model: {}, agent: "critic" }), /BLOCKED/) // allowed seat, no model id: fail closed
o = await call({ provider: { id: "anthropic" }, model: { id: "claude-sonnet-5" }, agent: "critic" }, { effort: "high", thinking: { type: "adaptive" } }); assert.equal(o.options.effort, "low") // effort forced back to low
o = await call({ provider: { id: "anthropic" }, model: { id: "claude-opus-5" }, agent: "plan-critic" }); assert.equal(o.options.effort, "low") // missing variant: effort still written
console.log("hook tests passed")
