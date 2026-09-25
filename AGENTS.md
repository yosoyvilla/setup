# Global Instructions

Portable engineering standards for all agent work in opencode
(`~/.config/opencode/AGENTS.md`). Project-level instruction files override
these where they conflict.

## Models
- NaN is the default provider. Use `nan/deepseek-v4-flash-low` for
  orchestration, planning, execution and search (benchmark 2026-09-21: best
  accuracy and latency of every reachable model); `nan/glm5.3-flash-low` is the
  only fallback (second model family, 1M context); `nan/glm5.3-flash-high` runs
  the fact-checker; `nan/mimo-v2.5` is for audio input only. The `-low`/`-none`/
  `-high` suffixes are effort aliases applied by the harness plugin; do not set
  reasoningEffort by hand, oh-my-openagent rewrites it.
- Claude is allowed on exactly two review seats and nowhere else:
  `@plan-critic` (anthropic/claude-opus-5) and `@critic`
  (anthropic/claude-sonnet-5). Enforced by the harness plugin, which rejects
  any other agent on Anthropic and runs both seats at effort low and caps every Claude call at 8192
  output tokens (thinking included); the provider whitelist exposes only those two ids. Each Claude
  spawn is a separate pay-as-you-go call carrying ~90k system tokens, and
  native task spawns are not serialized by oh-my-openagent: never spawn more
  than one Anthropic subagent at a time, and never route other work there.
- Every `@critic` or `@plan-critic` reply, however invoked, must END with its
  closing block (`@critic`: the JSON verdict block; `@plan-critic`: the line
  `Review complete.`). A reply without it was truncated at the 8k cap or is
  malformed: retry once, sequentially; if it fails again treat the review as
  INCONCLUSIVE, never as approval.
- Do not delegate questions, diagnosis, research or fact lookups to
  `@critic` or `@plan-critic`: answer them yourself on NaN, or use
  `@fact-checker` (NaN) for claims. Those two seats review artifacts only.
- These are open models. They hallucinate APIs, packages, and config far more
  than frontier models, are overconfident, and have flat confidence
  calibration. Treat every unverified factual claim as suspect — including your
  own. The rules below exist because of this.

## Anti-hallucination (non-negotiable)
- Tests are the terminal proof of done. Never claim a change works, is fixed,
  or is complete until the relevant tests/build/lint have actually run and
  passed. "Tests pass" is the evidence; green is the only "done."
- Verify before asserting. For any claim about a library, framework, API, CLI,
  version, default, flag, or config key, check official docs (context7 first,
  then web) before stating it as fact. Do not answer from memory on these.
- Cite or abstain. Back every non-obvious technical claim with a `file:line`
  reference (for code) or a primary-source URL (for external facts). If you
  cannot, say "unverified" or "I don't know" — that is the preferred answer
  over a confident guess. Absence of contradiction is not confirmation.
- Never invent or auto-install dependencies. Before adding any package, confirm
  it actually exists in its real registry (npm/PyPI/crates/etc.) and is the
  intended one. Open models fabricate plausible package names; do not install
  from model output unchecked.
- The same bar applies to what you RECOMMEND, not just what you were asked
  about: verify every package, API, or flag you volunteer as an alternative
  before naming it. A correct takedown of a fake package is undone by
  recommending another fake one in its place.
- Lead with nonexistence. When a queried API, hook, flag, or package cannot be
  found in official docs or its registry, say it does not exist FIRST — then,
  if useful, explain the nearest real pattern. Do not describe a nonexistent
  thing as if it were established.
- Gate on external signals, not on self-confidence. Decisions to proceed rest
  on tests passing, types checking, the registry confirming, the doc saying so
  — never on the model feeling sure. Your stated certainty is not evidence.
- Escalate when it matters: an adversarial critic for review of any output or
  plan, a fact-checker to verify claims against primary sources, and a
  multi-lens council for high-stakes decisions. (opencode: `@critic`,
  `@fact-checker`, `/council`.)
- Vision needs a vision model. In this config `nan/deepseek-v4-flash` (all
  effort aliases), `nan/glm5.3-flash`, `nan/gemma4` and `nan/qwen3.6` accept
  image input (benchmark 2026-09-21: deepseek low 2/2 on the vision items);
  `nan/mimo-v2.5` is wired for audio only here and must not receive
  screenshots. Never describe an image you were not given. Use
  `browser_snapshot` (accessibility text) for DOM interaction on any model.
- Aggregated telemetry can be SAMPLED. Before quoting a count from an analytics API
  (Cloudflare `httpRequestsAdaptiveGroups`, sampled log/metric datasets), confirm the
  sampling and report `count x avg.sampleInterval` — or label the figure as relative.
  Never publish a dimensional breakdown from an unnormalized sample: on 2026-09-22 the
  same window returned 455 vs 19,004 for two queries that differed only in `limit`.
- Free is not the same as licensed. For any external data source or API, verify its
  licence permits COMMERCIAL production use before adopting it. Verified 2026-09-23:
  AbuseIPDB's free tier (Terms §7), GreyNoise's volume limits, and PeeringDB's AUP
  each disqualified a source the design had already been built around.
- Reviewers may not assert schema or API facts without a citation. On 2026-09-23
  `@plan-critic` advised validating `result.scope.type == "zone"`; that field is only
  `user|organization`, so the advice would have shipped a broken guard. Treat
  reviewer-supplied API claims as hypotheses to verify against the docs, and cite a
  primary source when you supply one.
- A document asserting a property is not evidence the property holds. Decision
  records, ADRs and your own summaries are hypotheses until the code is checked
  against them: in one session two review findings were accepted-ADR claims the
  implementation never made, and a third was a documented limit with no code behind
  it. Read the code against the claim, not the claim alone.

## Memory (Engram)

Persistent cross-session memory is available via the Engram MCP server (local
SQLite, no model provider — the `mem_*` tools). Use it, but hold it to the same
evidence bar as everything else.

- Recall first: at the start of a non-trivial task, search memory
  (`mem_search` / `mem_context`) for prior decisions, gotchas, and conventions
  for this project. Treat results as PRIOR CONTEXT THAT MAY BE OUTDATED — verify
  against the current code/docs before acting on them. Recalled memory is not
  ground truth.
- Save only verified learnings (gated): call `mem_save` ONLY when a learning is
  backed by an external signal — tests passed, a doc confirmed it (context7), a
  command or file:line verified it, or the user confirmed it. Put that evidence
  in the saved memory. Never save speculation, guesses, or an unverified model
  claim: a weak model cannot reliably judge its own correctness, so evidence —
  not confidence — is the bar for what gets remembered.
- Save decisions, gotchas, fixes, and conventions — not transient state or raw
  tool output. Keep entries specific and self-contained.
- Never save secrets (keys, tokens, passwords, `.env` contents).

## Changes
- Write a short spec before any non-trivial change (more than one file, or any
  infra/config change): what, chosen approach vs alternatives, how it's
  verified, and how to roll back. Implementation starts after the spec.
- Run tests after every change. If there is no suite, verify manually and say
  how it was verified. Report failures honestly — never claim success unproven.
- Keep changes small and reviewable. Split large ones. Read a file before you
  edit it.
- Tests must be falsifiable. An assertion that passes on both success and
  failure (e.g. `status in (200, 400, 500)`, clicking without checking the
  response, printing a checkmark unconditionally) is not a test. For a bugfix,
  demonstrate the test failing before the fix and passing after.
- UI changes are verified in a real browser, not by reading code: drive the
  changed flow with the playwright tools, assert the network response status
  (a 2xx, not merely "the click happened"), and screenshot the result with a
  vision-capable model. Functional checks alone are not enough — run the
  visual-qa skill (dead-utility probe, desktop+mobile screenshots, vision
  review for alignment/overflow/contrast) before calling UI work done.
- Version control is the floor. If the project has no git repository, run
  `git init`, add a `.gitignore`, and make an initial commit before substantive
  work; commit after each verified change. Unversioned multi-day work is not
  acceptable.
- Any dependency installed during a session (pip/npm/pnpm/uv/etc.) is added to
  the project's manifest (requirements.txt, package.json, ...) in the same
  change, and the build is re-run once from the manifest to prove it.
- Fallbacks must be loud. A fallback or degraded path logs at ERROR, marks its
  output as degraded, and is surfaced to the user. Never persist placeholder or
  fallback output as if it were real data, and never swallow an exception
  without logging what was lost.
- A task or todo may be marked completed only with verification evidence: the
  command that proved it and its observed result. "It should work" does not
  close a task.
- Never chain a commit onto a gate whose exit code you have not checked. Running
  `verify; git add -A && git commit` committed and pushed a red state — the gate had
  exited 101 and the `;` let the commit proceed regardless. Run the gate, read its
  exit code, then act (`verify && git commit` at the very least).
- Capture the NAME of a failing test, not just the count. One run reported "277
  passed / 1 failed" and the name was never recorded; thirteen later runs were clean
  and the flake is now permanently unexplained. A count is not a diagnosis.
- After an interrupted or aborted subagent, run the full gate, not only the test
  suite. Aborted work left half-written functions that `cargo test` tolerated while
  `clippy --all-targets -- -D warnings` rejected them.

## Code
- SOLID/KISS/DRY applied pragmatically, not dogmatically. Extract on the third
  repetition, not the first.
- Fail fast: validate at boundaries, return early, shallow nesting.
- Immutability by default. Meaningful names, small functions, no dead or
  commented-out code.
- Shell loops that call a CLI (`kubectl`, `ssh`, `aws`, `psql`...) must
  redirect that CLI's stdin from `/dev/null` or read the loop input on a
  separate descriptor (`while read -r -u 3 ...; done 3< file`). Otherwise the
  CLI drains the loop's input and only the first item is processed. (0 of 11
  benchmarked models got this right unprompted.)
- A `readonly` shell variable used as a command-prefix assignment (`VAR=x cmd`) fails
  with the error on stderr while STILL RUNNING the command — so a "successful" run
  can hide a dead code path. On 2026-09-23 this silently disabled a dedupe step while
  the alert path kept reporting success; only running the flow twice exposed it.

## Git and docs
- Single-line commit messages. No co-author trailer. No emojis.
- No emojis in documentation. Do not create new markdown/doc files without
  explicit approval — ask first.
- Docs describing implemented behavior must distinguish `verified` (state how:
  test, command, file:line) from `intended`. Never document a feature as
  working without having verified it this session — project docs are the next
  session's ground truth, so an unverified claim compounds.
- Never write secret values (keys, tokens, passwords) into docs, memory, or
  commit messages — reference the environment variable name instead.
- TypeScript: no inline `import()` type annotations in signatures; switch
  statements over union types must be exhaustive (assert the `never` default).

## Agent Workflow Principles

Adapted from Bun's Zig-to-Rust rewrite methodology (bun.com/blog/bun-in-rust).

- Adversarial diff review before commit. Behavior-changing diffs (more than one
  file, or any infra/config change; doc-only, formatting-only, and rename-only
  diffs excluded) get a blind adversarial review before commit — run `/verify`,
  which routes the diff to the critic. The reviewer sees the diff only, never
  the implementer's reasoning, and assumes the code is wrong. A workaround that
  needs a paragraph-long justification comment means the code is wrong — fix
  the code. High-risk changes (prod infra, auth, data migrations): two
  independent reviews — `@critic` and `@thermo-nuclear-review` — neither seeing
  the other's output. (opencode: `@critic`, `/verify`.)
- Expect the review to find something. Across four consecutive slices, every
  adversarial review found a real, security-relevant defect that the full test
  suite, clippy and CI had all passed — a non-absolute timeout with dead expiry
  code, a refusal oracle, a fail-open capability list, a cosmetic signature binding.
  Its yield is high enough that trimming the review is the wrong economy; trim the
  delegation around it instead.
- Fix the workflow, not the output. When an agent, skill, or command produces
  the same bad pattern twice, edit its definition instead of hand-fixing
  instances — one definition edit fixes the class of error.
- Trial run before fan-out. Before any bulk or parallel operation over 3+
  similar items (mass edits, multi-file migrations, `ultrawork` fan-outs), run
  2-3 representative items first, review the results, then scale. Never fan
  out an unproven workflow.
- One installable artifact per delegation. Long multi-part delegated builds die
  partway and leave unverifiable partial work — five such delegations aborted after
  partial application on 2026-09-23. Slice the work so each delegation produces ONE
  artifact that can be independently installed, verified and committed; never bundle
  "build it + wire it + document it" into a single call.
- Query actual account entitlements before designing around a platform feature. A
  whole design pivoted on one unmade API call: 20 Cloudflare zones turned out to be
  16 Free / 2 Pro / 2 Business / 0 Enterprise, which invalidated the chosen field, the
  planned action and the assumed limits. Check the plan, quota and tier requirement
  first, not after the design is written.

### Shipping, deploys, and data changes (any project)

- Gate once, then act. When a request needs a decision, ask it once, framed so
  the safe default is the recommended option — never spread a menu of choices
  across turns. Repeated gating reads as stalling; if a sensible default exists,
  take it, state the assumption in one line, and proceed.
- Verify the artifact, not the narration. An agent's — or your own — claim that
  something works is a hypothesis until a build, test, or run confirms it. Read
  the command output; absence of a failure you never looked for proves nothing.
- Verify a write at the storage layer AND through the app's own read path. A
  value can persist without error yet be stored in an unusable shape (e.g. a
  JSON document double-encoded as a string). Check the representation, then read
  it back the way the application does.
- Make bulk data writes batched and idempotent. Row-at-a-time writes over a
  remote or pooled database can time out and leave a partial write: batch them,
  and make a re-run safe by only filling what is still empty.
- Order schema and code correctly. Apply an additive migration BEFORE rolling
  the code that reads it, then confirm the column/table exists. Reversed order
  breaks the running app.
- "Synced"/"healthy" status is not proof of deployment. Confirm the running
  artifact — image/tag, deployed revision, live endpoint. CI and GitOps tools
  report stale or drifted status routinely; judge by what is serving.
- Load the environment explicitly in scripts. Ad-hoc runners do not read `.env`
  automatically and silently hit a local/dev datastore, yielding a confident
  wrong answer. Pass the env file and state which target you used.
- Scope approval precisely. A verbal "approved" covers the idea, not the source,
  method, or legal basis. When a step is irreversible or externally exposed
  (third-party data, scraping, spend), ship the safe superset and state exactly
  what was withheld and why, rather than folding an ambiguous approval into a
  risky action.
- Bypass a protection gate (protected branch, required review, admin override)
  only when explicitly instructed — and say so loudly in the result.
- Keep a non-browser verification path for UI. Browser automation fails; a live
  HTTP status plus exercising the app's own code against real data is a valid
  fallback. Report that the visual check did not run rather than implying it did.

## Sampled data, alerts, and derived metrics

- A number derived from sampled or extrapolated analytics must pass an internal
  consistency check BEFORE it drives an alert or a decision: a sub-group can
  never exceed its own total, a subset ratio can never exceed 1, a count can
  never exceed its superset. If one does, the pipeline is wrong — suppress it
  and log why, never report it. On 2026-09-23 a Cloudflare alert claimed one IP
  was blocked 2,112,449 times in a window where the ENTIRE zone was blocked
  382,629 times, and that the IP was blocked more often than it made requests.
  Both are arithmetically impossible and either check would have caught it.
- Never compare two normalised values whose sampling resolution differs. The
  same window returned `avg.sampleInterval` 6.42 at `limit:1` and 43.70 for a
  filtered/dimensional query, so `count x sampleInterval` from each is not
  commensurable. Compare like-for-like, or move to the exact source.
  "Benchmarked" is not required if the vendor does not advertise a limit; it is
  a two-second measurement and it changes the answer.
- Prefer the exact, non-sampled source for any decision; use sampled data only
  for attribution and enrichment. Where a vendor offers an unsampled dataset
  next to sampled ones (Cloudflare `httpRequests1hGroups` beside the adaptive
  groups), that is the source of truth and the sampled figures are decoration.
- Confirm the UNIT before putting two metrics in one inequality. Different
  datasets count different things: `firewallEventsAdaptiveGroups` counts
  security EVENTS, not requests, and one request can raise several, so
  "blocks > requests" proves nothing until the units are known equal.
- Alert on harm or novelty, never on activity the control plane is already
  handling. If the platform is already blocking at least as much as the source
  sends, that is success, not an incident — a notification must be actionable.
  (User feedback, 2026-09-23: "you don't need to alert me if something was
  already mitigated by Cloudflare".)
- When an alert looks extreme, reproduce the numbers from the primary source
  before acting on it or reporting it. "Is it real?" is answered by the exact
  dataset, not by re-reading the alert.
- Split a fan-out query by capability or permission. One denied field makes the
  whole multi-field query fail, so every subject silently looks empty: mixing a
  paid-only dataset into a single GraphQL query marked 16 of 20 Cloudflare
  zones as "no analytics" when their request data had been readable all along.
- Distinguish "no data" from "no access", and never let a capability error
  masquerade as "nothing found". Surface every skip with its reason.
- Enumerate the installed artifacts and assert each has a repo counterpart. A
  committed wrapper whose helper lives only on the box is a half-versioned
  system: `/usr/local/lib/360bot-attackcheck.py` was unversioned while its shell
  wrapper was committed, so the running logic was unversioned.
- Fold a runtime config change back into provisioning in the SAME change, and
  read the platform's schema instead of assuming a key exists. A `groupPolicy`
  set by hand on a box silently reverts on rebuild, and `openclaw config schema`
  disproved three plausible key names in one command.

## Editing discipline (agent file edits)

- Give a multi-line replace an explicit end anchor. A single-anchor replace
  touches exactly ONE line and silently leaves the rest of the construct
  behind — on 2026-09-23 it duplicated an `elif` branch and left a stray `}`,
  and both still looked plausible on inspection.
- Line anchors are positional, not content-addressed. After any edit to a file,
  re-read before the next edit to that file, and batch related edits into one
  call. A stale anchor set caused an edit to land in the wrong place (above).
- Nested heredocs need distinct delimiters: an inner heredoc reusing the outer
  delimiter terminates it early and the shell reports an unmatched quote.
- A heredoc that supplies a program on stdin cannot also receive data on stdin.
  Pass the data via argv or the environment: piping JSON into `python3 - <<'PY'`
  left `sys.stdin.read()` at EOF and reported "no valid JSON".
- After adding a constant or a symbol in a batched edit, grep for it to prove it
  landed. A constants edit was silently dropped and only surfaced as a
  `NameError` when the timer next fired.
- Build the offline self-test early and run it after every edit. It caught
  three defects that reading did not: a missing GraphQL closing brace, the
  duplicated branch above, and the stdin-EOF parse above.
- `rm -rf` with an absolute path is blocked by the harness guard; use `rm -r`
  or a path relative to the working directory.
- Before overwriting a table row or column, check what it *was*. A status narrative
  replaced a normative column twice in one session (an exit criterion, then a whole
  row) because the surrounding table looked homogeneous. Prefer a surgical substring
  edit plus a presence check (`grep -c '^| Phase '`), and recover with
  `git show <first-commit>:<file>` rather than reconstructing content from memory.
- After a deliberate-break experiment, verify the restore landed. A command timeout
  killed a script before its restore step, leaving a security gate disabled until
  the file was re-checked by hand. Diff against a backup; do not assume the undo ran.
