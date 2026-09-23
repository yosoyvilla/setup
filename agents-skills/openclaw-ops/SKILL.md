---
name: openclaw-ops
description: Operate an OpenClaw gateway (the Slack agent runtime) on a remote box — inspect and safely change its config, read conversation sessions, control Slack reachability, and restart the gateway service. Use when a bot built on OpenClaw misbehaves, when you need to change how it is reachable in Slack (DMs vs channels), when a config key must be verified rather than assumed, or when you need to know which Slack scopes a bot actually holds.
license: MIT
metadata:
  audience: infra-ops
  verified: "2026-09-23"
---

# OpenClaw gateway operations

OpenClaw runs the Slack agent on a box as a **systemd USER unit**, with its
config at `~/.openclaw/openclaw.json` (owned by the service user, mode 600).
Secrets come from SSM at start and are never on disk.

## 1. Read and change config — never guess a key

```bash
# read the active file path
openclaw config file
# read one value
openclaw config get channels.slack
# the FULL schema with defaults and enums — use this instead of assuming
openclaw config schema
# validate a change BEFORE applying it
openclaw config patch --file /tmp/p.patch.json5 --dry-run
# apply (hot-applies; no restart needed)
openclaw config patch --file /tmp/p.patch.json5
```

- Always `--dry-run` first. The patch writer validates against the schema.
- OpenClaw keeps its own rotating backups (`openclaw.json.bak*`,
  `.last-good`) — but still take and **verify your own** backup before a change
  (see the `ssm-remote-ops` mutation protocol).
- **Read the schema; do not assume a key name.** Plausible names are often wrong:
  in 2026.9.5 `channels.slack.groupAllowFrom`, `replyInThread` and
  `threadReplies` are **not valid Slack paths** (they exist for
  buzz/discord/feishu). One `config schema` call disproved all three.
- A change applied by hand on a box is lost on rebuild unless it is folded back
  into provisioning. Record it in the repo the same day.

## 2. Slack reachability: who can talk to the bot

Two keys govern it, and they are independent:

| Key | Meaning |
|---|---|
| `channels.slack.dmPolicy` + `allowFrom` | who may DM the bot (`allowlist` + user ids) |
| `channels.slack.groupPolicy` | `open` (any channel it is added to), `disabled`, or `allowlist` (needs per-channel entries) |

- The default is `allowlist`, so a bot with no per-channel entries is **silent in
  every channel** while still answering DMs. That is a common "it works in DM but
  not in the channel" cause.
- `open` means *any* channel it is added to can instruct it — check what the bot
  is allowed to DO (e.g. can it mutate Cloudflare/prod?) before widening it.
  Narrower alternative: `channels.slack.groups.<channelId>` entries.

```bash
printf '{ channels: { slack: { groupPolicy: "open" } } }\n' > /tmp/gp.patch.json5
openclaw config patch --file /tmp/gp.patch.json5 --dry-run
openclaw config patch --file /tmp/gp.patch.json5
openclaw config get channels.slack.groupPolicy       # read it back
diff <(python3 -m json.tool "$BK") <(python3 -m json.tool "$CFG")   # only that key moved
```

## 3. Conversation sessions (context continuity)

```bash
openclaw sessions      # stored sessions, with age, model, ctx %, flags
openclaw status        # gateway/channel health + recent session recipients
```

- A **DM session is keyed per Slack user**:
  `policy:agent:main:slack:default:direct:user:<id>`. All messages from that user
  (threaded or not) share one session, so a reply continues the conversation with
  its history. That is why DM replies "remember".
- Channel sessions are keyed per channel/thread — which is why `groupPolicy`
  decides whether channel conversation happens at all.

## 4. Which Slack scopes does the bot really have?

No app-config token is needed — the bot token reports its own scopes in the
**response headers** of `auth.test`:

```bash
curl -sS -D - -o /dev/null -H "Authorization: Bearer $BOT_TOKEN" \
  https://slack.com/api/auth.test | grep -i '^x-oauth-scopes'
```

Compare against the required set for reading history/replies: `im:history`,
`channels:history`, `groups:history`, `mpim:history`, `im:read`, `im:write`,
`chat:write`, `app_mentions:read`. Identical scopes between two bots means the
difference is elsewhere (usually `groupPolicy`).

## 5. Restart the gateway

The gateway is a **user** unit, so a root/SSM session must supply the user's
runtime dir:

```bash
runuser -u ec2-user -- env XDG_RUNTIME_DIR=/run/user/$(id -u ec2-user) \
  systemctl --user restart openclaw-gateway.service
runuser -u ec2-user -- env XDG_RUNTIME_DIR=/run/user/$(id -u ec2-user) \
  systemctl --user is-active openclaw-gateway.service
```

`openclaw status` reports the gateway service state, node version and app
version — confirm it stays `running` after a restart. Note that a config patched
with the official writer usually applies **without** a restart.

## 6. Verify a Slack change end to end

1. `openclaw config get <key>` returns the intended value.
2. The JSON diff against your verified backup shows **only** that key changed.
3. `openclaw status` shows the channel `OK` and the gateway `active`.
4. Exercise it for real (mention the bot in the channel), and confirm the reply —
   a "configured" status is not proof the behaviour changed.
