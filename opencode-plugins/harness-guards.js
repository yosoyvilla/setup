/**
 * harness-guards — automatic verification enforcement for the NaN opencode harness.
 * All logic lives in ../scripts/harness-guards-lib.mjs (unit-tested there).
 * This file must contain EXACTLY ONE export: opencode calls every export of a
 * plugin module as a function, so a non-function export breaks loading.
 */
import {
  DISABLED, SECRET_RE, DOC_FILE_RE, BROWSER_TOOL_RE, BASH_PROTECTED_RE,
  LOG_DIR, AUDIT_LOG, ABORT_LOG, state, sessionParent,
  classifyEdit, classifyBash, checkGit, obligations, obligationBlock,
  CLAUDE_SEATS, ANTHROPIC_MAX_OUTPUT, CLAUDE_EFFORT, NAN_EFFORTS, prefillRepairMessage,
} from "../scripts/harness-guards-lib.mjs"
import fs from "node:fs"


// --- plugin -----------------------------------------------------------------

export const HarnessGuards = async ({ client, directory, $ }) => {
  if (DISABLED) return {}

  async function isSubagentSession(sessionID) {
    if (!sessionID) return false
    if (sessionParent.has(sessionID)) return !!sessionParent.get(sessionID)
    try {
      const res = await client.session.get({ path: { id: sessionID } })
      const parentID = res?.data?.parentID
      sessionParent.set(sessionID, parentID)
      return !!parentID
    } catch {
      sessionParent.set(sessionID, undefined)
      return false
    }
  }

  return {
    // Restore the per-model reasoning effort that oh-my-openagent's chat.params resolver deletes
    // (unknown model family) or rewrites (deepseek: low/medium -> high). Models declare
    // `options.nanReasoningEffort` in opencode.jsonc; this runs after omo and re-applies it.
    // Verified 2026-09-21: without this, effort none/low on nan/deepseek produced 1-4k reasoning
    // tokens per turn under omo; in --pure mode the same option yielded 0.
    "chat.params": async (input, output) => {
      const providerID = input?.provider?.id ?? input?.model?.providerID
      const modelID = input?.model?.id ?? input?.model?.modelID
      const agentName = String((typeof input?.agent === "string" ? input.agent : input?.agent?.name) ?? "").toLowerCase()
      const eff = output?.options?.nanReasoningEffort
      if (eff !== undefined) {
        delete output.options.nanReasoningEffort // never forward the carrier key itself
        if (providerID === "nan" && NAN_EFFORTS.has(eff)) output.options.reasoningEffort = eff
        else if (providerID === "nan") throw new Error(`[harness-guards] invalid nanReasoningEffort "${eff}" (allowed: ${[...NAN_EFFORTS].join(", ")})`)
      }
      // Anthropic (pay-as-you-go): only the two review seats, each pinned to its model, and a hard
      // per-call cap written into the request (limit.output in opencode.jsonc is catalog/compaction
      // math only). No thinking budget: Claude 5-family rejects budget_tokens (400).
      if (providerID === "anthropic") {
        const allowed = CLAUDE_SEATS.get(agentName)
        if (!allowed || modelID !== allowed) {
          throw new Error(
            `[harness-guards] BLOCKED: Anthropic (pay-as-you-go) is allowed only as ${JSON.stringify(Object.fromEntries(CLAUDE_SEATS))}; ` +
              `got agent "${agentName}" on "${modelID}". Use a nan/* model.`,
          )
        }
        output.maxOutputTokens = ANTHROPIC_MAX_OUTPUT
        // The agent's `variant: low` normally supplies this; write it anyway so a rewritten or missing
        // variant cannot silently raise effort (verified on the wire 2026-09-21 as output_config.effort).
        output.options.effort = CLAUDE_EFFORT
      }
    },

    "tool.execute.before": async (input, output) => {
      const tool = input.tool
      if (tool === "write" || tool === "edit") {
        const filePath = output.args?.filePath || ""
        const content = String(output.args?.content ?? output.args?.newString ?? "")
        if (DOC_FILE_RE.test(filePath) && SECRET_RE.test(content)) {
          throw new Error(
            `[harness-guards] BLOCKED: the content being written to ${filePath} contains a secret-shaped value (API key/token/private key). ` +
              `Docs and markdown must never contain secret values — reference the environment variable name instead, then retry.`,
          )
        }
      }
      if (tool === "bash") {
        const command = String(output.args?.command ?? "")
        if (BASH_PROTECTED_RE.test(command)) {
          throw new Error(
            `[harness-guards] BLOCKED: this bash command writes to, copies, moves, or deletes a protected file ` +
              `(.env, *.tfstate, *.tfvars, *.pem, *.key, id_rsa, secrets/). Protected files must be edited by the user, not the agent.`,
          )
        }
      }
    },

    "tool.execute.after": async (input) => {
      const tool = input.tool
      try {
        if (tool === "bash") {
          const command = String(input.args?.command ?? "")
          fs.mkdirSync(LOG_DIR, { recursive: true })
          fs.appendFileSync(
            AUDIT_LOG,
            `${new Date().toISOString()} [${input.sessionID}] ${directory} $ ${command.replace(/\n/g, " ")}\n`,
          )
          classifyBash(command)
        } else if (tool === "write" || tool === "edit") {
          classifyEdit(input.args?.filePath || "")
          checkGit(directory)
        } else if (BROWSER_TOOL_RE.test(tool)) {
          state.uiEdited.clear() // browser verification observed
        }
      } catch (err) {
        client.app
          .log({ body: { service: "harness-guards", level: "warn", message: String(err) } })
          .catch(() => {})
      }
    },

    // Repair a conversation that ends on an assistant turn for our Claude seats.
    // omo's own guard hardcodes the Claude-4 prefixes, so claude-*-5 slips past
    // it and Anthropic rejects the request with "does not support assistant
    // message prefill" (see prefillRepairMessage in harness-guards-lib).
    "experimental.chat.messages.transform": async (_input, output) => {
      const messages = output?.messages
      if (!Array.isArray(messages) || messages.length === 0) return
      const repair = prefillRepairMessage(messages[messages.length - 1]?.info)
      if (repair) messages.push(repair)
    },

    "experimental.chat.system.transform": async (input, output) => {
      const block = obligationBlock()
      if (!block) return
      if (input?.sessionID && (await isSubagentSession(input.sessionID))) return
      // NaN's openai-compatible endpoint requires a SINGLE system message at
      // index 0 — a pushed second element becomes a second system message and
      // the API rejects the request. Append to the existing prompt instead
      // (same DCP-safe pattern oh-my-openagent uses).
      if (output.system.length > 0) {
        output.system[output.system.length - 1] += `\n\n${block}`
      } else {
        output.system.push(block)
      }
    },

    "experimental.session.compacting": async (_input, output) => {
      const block = obligationBlock()
      if (block) output.context.push(block)
    },

    event: async ({ event }) => {
      // Abort/error forensics: log any error/abort-shaped plugin event to a dedicated
      // file. Background-task aborts report only "Session error" with nothing persisted,
      // which left a recurring failure (4 aborts on 2026-09-23, every one after partial
      // application) undiagnosable. Best-effort by design: if no such event ever fires
      // the log simply stays empty, and a failure here must never break the run.
      const eType = String(event?.type ?? "")
      if (/error|abort|fail|interrupt/i.test(eType)) {
        try {
          fs.mkdirSync(LOG_DIR, { recursive: true })
          let detail = ""
          try {
            detail = JSON.stringify(event?.properties ?? {}).slice(0, 4000)
          } catch {
            detail = "<unserializable properties>"
          }
          fs.appendFileSync(
            ABORT_LOG,
            `${new Date().toISOString()} type=${eType} session=${event?.properties?.sessionID ?? "-"} ${detail}\n`,
          )
        } catch {
          /* forensics must never break a run */
        }
      }
      if (event?.type !== "session.idle") return
      const block = obligationBlock()
      if (!block) return
      const sessionID = event?.properties?.sessionID
      if (sessionID && (await isSubagentSession(sessionID))) return
      const now = Date.now()
      if (now - state.lastNotify < 60_000) return
      state.lastNotify = now
      const summary = obligations()
        .map((o) => o.split(":")[0])
        .join(", ")
      try {
        if (process.platform === "darwin") {
          await $`osascript -e ${"display notification \"Unverified: " + summary + "\" with title \"harness-guards\""}`
        } else {
          await $`notify-send ${"harness-guards"} ${"Unverified: " + summary}`
        }
      } catch {
        /* notifier unavailable — notification is best-effort */
      }
    },
  }
}

