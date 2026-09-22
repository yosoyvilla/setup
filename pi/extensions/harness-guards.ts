// harness-guards: pi has no permission layer, so the policy that opencode enforces through permissions
// and its plugin lives here. Mirrors ~/.config/opencode/opencode.jsonc (bash denylist) and
// ~/.config/opencode/scripts/harness-guards-lib.mjs (protected paths, Claude seats).
// Same-process guard, not a security boundary: `pi --no-extensions` disables it (and is itself denied below
// for nested launches). Behavioral tests: ~/.pi/agent/scripts/test-pi-guards.mjs (run by check-pi-harness.mjs).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const NAN_DEFAULT = { provider: "nan", id: "deepseek-v4-flash" };
// gentle-pi's review lenses run IN-PROCESS through their own routed model (lib/review-host-relay.ts
// runInProcessReviewer), independent of the session model. The session model itself must therefore
// never be Anthropic: only the routed review lenses may reach Claude.
// gentle_review_capture_group runs every selected lens concurrently (Promise.allSettled), which breaks
// "one Claude call at a time"; single-slot gentle_review_capture is the allowed path.
export const BLOCKED_TOOLS = new Set(["gentle_review_capture_group"]);

// Global option tokens a command may carry before its subcommand (git -C x, terraform -chdir=y, kubectl --context z ...).
const OPTS = String.raw`(?:\s+-{1,2}[\w-]+(?:=\S+|\s+(?!-)\S+)?)*`;
// Never-legitimate commands, matched per shell segment after normalization (see segments()).
export const BASH_DENY: RegExp[] = [
	// rm with both r and f flags (any order, split or bundled, optional --) on / or the home directory
	new RegExp(String.raw`^rm(?=\s)(?=.*\s-\S*r)(?=.*\s-\S*f)\s+(?:-\S+\s+|--\s+)*(?:/|/\*|~|~/\*|\$HOME|"\$HOME"|\$\{HOME\})(?:/\*)?(?:\s|$)`),
	new RegExp(String.raw`^git${OPTS}\s+push\b(?![^]*--force-with-lease)[^]*(?:\s--force\b|\s-f\b)`),
	new RegExp(String.raw`^git${OPTS}\s+reset\s+(?:\S+\s+)*--hard\b`),
	new RegExp(String.raw`^git${OPTS}\s+clean\b(?=.*(?:^|\s)-\S*f)(?=.*(?:^|\s)-\S*d)`),
	new RegExp(String.raw`^terraform${OPTS}\s+(?:destroy|force-unlock)(?:\s|$)`),
	new RegExp(String.raw`^(?:kubectl|oc)${OPTS}\s+delete${OPTS}\s+(?:namespace|namespaces|ns)(?:\s|$)`),
	new RegExp(String.raw`^pi\b[^]*--no-extensions\b`), // a nested pi without extensions has no guard at all
	new RegExp(String.raw`^pi\s+auth\b`), // pi auth print-api-key / print-bearer-token / check --credentials print secrets
];
// Secrets and state files: never written, edited or read by an agent through any tool, including bash
// (a cat/cp/wc of auth.json into a repo file is how a key ends up synced). Glob characters in place of the
// dot (auth?json, auth*json) are treated as the same name.
const D = String.raw`[.?*]`;
export const PROTECTED_PATH = new RegExp(
	String.raw`(^|[\s/"'=])(?:${D}env(?:${D}[\w-]*)?|[\w.-]*${D}tfstate(?:${D}backup)?|[\w.-]*${D}pem|[\w.-]*${D}key|id_rsa[\w.-]*|auth${D}json)(?=$|[\s"'/])|(^|[\s/"'=])secrets/`,
);

export function segments(command: string): string[] {
	return command
		.split(/\n|;|&&|\|\||\|/)
		.map((s) => s.trim())
		.filter(Boolean)
		.map((s) => {
			let out = s;
			for (let i = 0; i < 6; i++) {
				const next = out.replace(/^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+|(?:env|sudo|command|nohup|time|exec|builtin)\s+(?:-\S+\s+)*)/, "");
				if (next === out) break;
				out = next;
			}
			return out.replace(/^(?:\/[\w.-]+)+\/(?=\w)/, ""); // /usr/bin/git -> git
		});
}

export function checkBash(command: string): string | undefined {
	for (const seg of segments(command)) {
		const hit = BASH_DENY.find((re) => re.test(seg));
		if (hit) return `harness-guards: blocked catastrophic command "${seg.slice(0, 60)}". Ask the user to run it.`;
		if (PROTECTED_PATH.test(seg)) return `harness-guards: "${seg.slice(0, 60)}" touches a protected secret/state file; agents never read or copy those.`;
	}
	return undefined;
}

const PATH_TOOLS = new Set(["read", "write", "edit", "grep", "find", "ls"]);

export default function (pi: ExtensionAPI) {
	// Anthropic fence. Applied at session start (covers --model and settings), on every model selection
	// (covers /model, Ctrl+P cycling and session restore), on every user input and again before a turn.
	// When the NaN fallback cannot be selected (no NAN_API_KEY), the input is swallowed instead of
	// letting the turn run on Claude: fail closed.
	const fence = async (ctx: any, when: string): Promise<{ note: string; switched: boolean } | undefined> => {
		const current = ctx.model;
		if (current?.provider !== "anthropic") return undefined;
		const fallback = ctx.modelRegistry?.find?.(NAN_DEFAULT.provider, NAN_DEFAULT.id);
		const switched = fallback ? Boolean(await pi.setModel(fallback)) : false;
		const note = switched
			? `harness-guards (${when}): Anthropic is allowed only for gentle-pi review lenses; switched this session from anthropic/${current.id} back to ${NAN_DEFAULT.provider}/${NAN_DEFAULT.id}.`
			: `harness-guards (${when}): Anthropic is allowed only for gentle-pi review lenses and the NaN fallback could not be selected (is NAN_API_KEY set?). The turn was not sent.`;
		if (ctx.hasUI) ctx.ui.notify(note, switched ? "warning" : "error");
		return { note, switched };
	};
	pi.on("session_start", async (_event, ctx) => { await fence(ctx, "session_start"); });
	pi.on("model_select", async (event, ctx) => { if (event.model?.provider === "anthropic") await fence(ctx, "model_select"); });
	pi.on("input", async (_event, ctx) => {
		const r = await fence(ctx, "input");
		return r && !r.switched ? { action: "handled" } : { action: "continue" };
	});
	pi.on("before_agent_start", async (_event, ctx) => {
		const r = await fence(ctx, "before_agent_start");
		return r ? { message: { customType: "harness-guards", content: r.note, display: true } } : undefined;
	});

	pi.on("tool_call", async (event) => {
		if (BLOCKED_TOOLS.has(event.toolName)) {
			return { block: true, reason: `harness-guards: ${event.toolName} runs every lens concurrently; capture one lens at a time with gentle_review_capture (one Claude call at a time).` };
		}
		if (event.toolName === "bash") {
			const reason = checkBash(String((event.input as { command?: unknown }).command ?? ""));
			if (reason) return { block: true, reason };
		}
		if (PATH_TOOLS.has(event.toolName)) {
			const path = String((event.input as { path?: unknown }).path ?? "");
			if (PROTECTED_PATH.test(path)) return { block: true, reason: `harness-guards: ${path} is a protected secret/state file; agents never read or write it.` };
		}
		return undefined;
	});
}
