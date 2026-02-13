# OpenClaw Configuration Guide

A checklist of safe defaults and lessons learned from running OpenClaw with WhatsApp as the primary channel. Written for personal Gmail accounts on macOS, but most advice applies broadly.

> **Context:** This guide was written alongside the [gmail-agent](https://github.com/r39132/gmail-agent) project. The pitfalls are general OpenClaw issues, not specific to Gmail.

---

## 1. Security Hardening

### DM session isolation (critical)

By default, OpenClaw shares a single agent session across all DM contacts on the same channel. This means context from a conversation with Contact A can leak into a conversation with Contact B.

**Fix:** Set per-peer session isolation in `openclaw.json`:

```jsonc
// openclaw.json → channels → whatsapp
"whatsapp": {
  "dmPolicy": "allowlist",
  "session": {
    "dmScope": "per-channel-peer"  // ← ADD THIS
  }
}
```

Without this, the agent's context window is shared — meaning one contact could see summaries, tool outputs, or references from another contact's conversation.

### DM allowlist (critical)

Never leave DM policy as `"open"`. Explicitly list the phone numbers that are allowed to interact with your agent:

```jsonc
"whatsapp": {
  "dmPolicy": "allowlist",
  "allowFrom": [
    "+15551234567",
    "+15559876543"
  ]
}
```

If you skip this, anyone who messages your WhatsApp number can interact with your agent — including triggering skills that execute shell commands.

### Group allowlist

Same principle for groups. Set `"groupPolicy": "allowlist"` and only add groups you control:

```jsonc
"groupPolicy": "allowlist",
"allowGroups": ["group-id-here"]
```

### Gateway auth token

OpenClaw generates a gateway auth token during onboarding. Verify it's set and not disabled:

```jsonc
"gateway": {
  "auth": {
    "mode": "token",
    "token": "<your-token>"
  }
}
```

If you reset or regenerate your config, double-check this is present. Without it, any local process can send commands to your agent.

### Tailscale: serve vs. funnel

OpenClaw supports Tailscale for remote access. Know the difference:

| Mode | What it does | Who can reach it |
|------|-------------|-----------------|
| `serve` | Exposes gateway on your Tailnet only | Your devices only |
| `funnel` | Exposes gateway to the public internet | Anyone with the URL |

**Use `serve` unless you have a specific reason for `funnel`.** If you're only accessing the dashboard from your own devices, `serve` is sufficient and doesn't expose anything publicly:

```jsonc
"tailscale": {
  "mode": "serve",      // ← not "funnel"
  "resetOnExit": false
}
```

### Gateway bind

Keep the gateway bound to loopback unless you need LAN access:

```jsonc
"gateway": {
  "bind": "loopback"    // 127.0.0.1 only
}
```

---

## 2. WhatsApp Setup

### Self-chat for testing

Enable self-chat mode so you can test skill execution by messaging yourself, without bothering other contacts:

```jsonc
"whatsapp": {
  "selfChatMode": true
}
```

This is invaluable during skill development. Send yourself commands, verify the agent responds correctly, iterate — all without anyone else seeing your test messages.

### Debounce

If you send multi-line messages or paste content, the agent may process each line as a separate turn. Set a debounce to batch them:

```jsonc
"whatsapp": {
  "debounceMs": 1000    // Wait 1s for additional lines before processing
}
```

A value of 0 (the default) means every message is processed immediately. For chat-style use this is fine, but if you paste multi-line content, bumping this to 500-1000ms helps.

### Media limits

Set a reasonable media size limit to prevent accidental large file processing:

```jsonc
"mediaMaxMb": 50
```

---

## 3. Agent Configuration

### Workspace files

OpenClaw expects several markdown files in the workspace directory. Here's what each does and what to put in them:

| File | Purpose | Tip |
|------|---------|-----|
| `IDENTITY.md` | Agent name, persona, emoji | Keep it short — this is injected into every prompt |
| `USER.md` | Your name, timezone, preferences | Set timezone so cron and timestamps make sense |
| `SOUL.md` | Tone, boundaries, behavioral rules | Add "Never send streaming/partial replies to external messaging surfaces" |
| `TOOLS.md` | Environment-specific notes (SSH hosts, device names) | Keep secrets out — this file is readable by the agent |
| `AGENTS.md` | Workspace meta-instructions, safety defaults | Good place for "don't run destructive commands" guardrails |
| `HEARTBEAT.md` | Periodic triggers | Leave empty to disable heartbeat API calls |

### Context token budget

The default context budget is 16,000 tokens. This is fine for most interactions but can be tight if your agent processes large outputs (e.g., a label audit with hundreds of labels):

```jsonc
"agents": {
  "defaults": {
    "contextTokens": 16000
  }
}
```

If you see the agent truncating or losing context mid-task, increase this — but know that higher values cost more per turn.

### Multi-agent: don't overcomplicate early on

OpenClaw supports multiple agents with separate workspaces. Resist the urge to set this up immediately. Start with one agent (`main`), get comfortable, then add a second agent only when you have a clear reason (e.g., isolating automation tasks from interactive chat).

A second agent means a second workspace, separate skill resolution, and another set of identity files to maintain. If your main agent handles everything fine, you don't need it.

---

## 4. Scheduling (Cron)

### Always set timezone

Cron expressions are evaluated in the timezone you specify. If you don't set one, you may get surprising run times:

```json
"schedule": {
  "kind": "cron",
  "expr": "0 12 * * *",
  "tz": "America/Los_Angeles"
}
```

### Use isolated sessions for cron jobs

Cron jobs should run in isolated sessions to prevent their context from bleeding into your interactive conversations:

```json
"sessionTarget": "isolated",
"isolation": {
  "postToMainPrefix": "Cron",
  "postToMainMode": "summary",
  "postToMainMaxChars": 8000
}
```

Without `"sessionTarget": "isolated"`, the cron job runs inside your active session — meaning it can see your prior conversation and its output gets mixed into your chat history.

### Gateway must be running

Cron jobs are executed by the OpenClaw gateway process, not by the system crontab. If the gateway isn't running, cron jobs silently don't fire. Verify:

```bash
openclaw gateway status
```

If you're on macOS, install the LaunchAgent so the gateway survives reboots:

```bash
openclaw gateway install    # Installs LaunchAgent
openclaw gateway start      # Starts it
```

### Test before you trust

After creating a cron job, verify it's registered and check its next run time:

```bash
openclaw cron list
openclaw cron runs          # See execution history
```

Don't assume a cron job is working just because you created it. Check the run history after the first expected execution.

---

## 5. Skills

### Precedence matters

Skills are resolved in this order (highest priority first):

1. **Workspace** (`~/.openclaw/workspace/skills/`)
2. **Managed** (`~/.openclaw/skills/`)
3. **Bundled** (ships with OpenClaw)
4. **extraDirs** (custom directories in config)

A workspace skill with the same name as a bundled skill **completely replaces** the bundled one — it doesn't merge. This is useful (you can override built-in behavior) but can be surprising if you accidentally name a custom skill the same as a built-in.

### Symlink for development

During development, symlink your skill into the workspace rather than copying:

```bash
ln -s ~/Projects/my-skill/skills/my-skill ~/.openclaw/workspace/skills/my-skill
```

This way, edits to your source files are immediately picked up by the agent. No need to re-copy after every change.

### SKILL.md frontmatter

The `requires` block in your SKILL.md frontmatter tells OpenClaw what the skill needs. If a binary or env var is missing, the skill shows as "unavailable" rather than failing at runtime with a cryptic error:

```yaml
---
name: my-skill
requires:
  binaries: ["gog", "jq"]
  env: ["GMAIL_ACCOUNT"]
---
```

Always declare your dependencies here. It's the difference between a clear "skill unavailable: missing gog" message and a confusing "command not found" buried in a shell script.

---

## 6. Maintenance

### Check for updates

OpenClaw doesn't auto-update. Check periodically:

```bash
openclaw version             # Current version
openclaw update check        # Check for updates
openclaw update apply        # Apply update
```

### Clean up background jobs

If you use background task scripts (like gmail-agent does), old job records accumulate. Clean them periodically:

```bash
openclaw jobs clean          # Or your skill's equivalent
```

### Monitor gateway health

```bash
openclaw gateway status      # Quick health check
openclaw gateway logs        # Recent logs
```

If the gateway crashes or gets stuck, your cron jobs, WhatsApp connection, and all channel integrations stop working. On macOS, the LaunchAgent should auto-restart it, but verify after system updates or reboots.

### Security audit

Run the built-in audit periodically to catch misconfigurations:

```bash
openclaw security audit
```

This flags issues like missing DM isolation, open DM policies, and exposed endpoints.

---

## 7. Common Gotchas

### bash version on macOS

macOS ships with bash 3.2 (from 2007). If any skill uses associative arrays (`declare -A`), it will fail with a cryptic syntax error. Install bash 4+ via Homebrew:

```bash
brew install bash
```

Then either use `/usr/local/bin/bash` in your script shebangs or add it to your PATH ahead of the system bash.

### Agent timeout on long-running tasks

The OpenClaw agent has a per-turn timeout. If your skill runs a command that takes more than a few minutes (batch deletion, large API pagination), the agent will time out and the command gets killed.

**Solution:** Daemonize long-running tasks. Fork the process with `nohup` + `disown` so it survives independently of the agent:

```bash
nohup bash -c 'your-long-command' </dev/null >/tmp/task.log 2>&1 &
disown
```

Then use a separate monitoring loop to send progress updates via `openclaw message send`. This is the pattern gmail-agent's `gmail-background-task.sh` uses.

### WhatsApp session expiry

The WhatsApp Web session can expire or disconnect if your phone loses internet, the WhatsApp app is force-closed, or WhatsApp pushes a protocol update. When this happens, the gateway keeps running but messages silently fail.

Check connection status:

```bash
openclaw channels whatsapp status
```

If disconnected, re-link:

```bash
openclaw channels whatsapp link
```

### Credential paths differ by platform

OpenClaw and its tools store credentials in platform-specific locations:

| Platform | Path |
|----------|------|
| macOS | `~/Library/Application Support/gogcli/` |
| Linux | `~/.config/gogcli/` |

If your skill scripts hardcode one path, they'll break on the other platform. Check both:

```bash
GOG_CREDS_DIR="${HOME}/Library/Application Support/gogcli"
if [[ ! -f "$GOG_CREDS_DIR/credentials.json" ]]; then
    GOG_CREDS_DIR="${HOME}/.config/gogcli"
fi
```

### Ack reactions in groups

By default, the agent may react to every message in a group with an acknowledgement emoji. This is noisy. Limit it to mentions only:

```jsonc
"messages": {
  "ackReactionScope": "group-mentions"  // Only react when @mentioned
}
```

---

## Quick Reference

### Minimum safe config checklist

- [ ] `dmPolicy: "allowlist"` with explicit phone numbers
- [ ] `groupPolicy: "allowlist"`
- [ ] `session.dmScope: "per-channel-peer"` for DM isolation
- [ ] Gateway auth token present and not disabled
- [ ] `tailscale.mode: "serve"` (not `"funnel"`) unless you need public access
- [ ] `gateway.bind: "loopback"`
- [ ] Timezone set in `USER.md` and cron jobs
- [ ] Cron jobs use `"sessionTarget": "isolated"`
- [ ] `SOUL.md` has "no streaming to external surfaces" rule
- [ ] Gateway installed as LaunchAgent (macOS) or systemd service (Linux)
- [ ] bash 4+ installed (macOS)

### Verify your setup

```bash
openclaw security audit          # Security scan
openclaw gateway status          # Gateway health
openclaw channels whatsapp status # WhatsApp connection
openclaw cron list               # Scheduled jobs
openclaw skills list             # Installed skills
```
