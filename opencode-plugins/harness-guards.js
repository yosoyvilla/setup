/**
 * harness-guards — automatic verification enforcement for the NaN opencode harness.
 * All logic lives in ../scripts/harness-guards-lib.mjs (unit-tested there).
 * This file must contain EXACTLY ONE export: opencode calls every export of a
 * plugin module as a function, so a non-function export breaks loading.
 */
import {
  DISABLED, SECRET_RE, DOC_FILE_RE, BROWSER_TOOL_RE, BASH_PROTECTED_RE,
  LOG_DIR, AUDIT_LOG, state, sessionParent,
  classifyEdit, classifyBash, checkGit, obligations, obligationBlock,
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
        await $`osascript -e ${"display notification \"Unverified: " + summary + "\" with title \"harness-guards\""}`
      } catch {
        /* non-macOS or osascript unavailable — notification is best-effort */
      }
    },
  }
}

