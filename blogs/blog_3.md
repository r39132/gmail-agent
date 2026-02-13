# OpenClaw Has Rough Edges — Here's How to Avoid Them

*February 12, 2026*

---

After two weeks of running [OpenClaw](https://openclaw.ai) as my daily Gmail management layer, I've learned that the platform is genuinely useful — and genuinely full of sharp edges. The onboarding wizard gets you to "it works" fast, but the defaults it sets aren't always safe, and the gotchas don't announce themselves until something breaks.

This isn't a takedown. I still use OpenClaw every day. But I've collected enough bruises that I think it's worth writing down what I wish I'd known on day one. I've also distilled the practical fixes into a standalone [Configuration Guide](../docs/openclaw-config-guide.md) you can use as a checklist.

## The DM Isolation Problem

This was the scariest one. By default, OpenClaw shares a single agent session across all DM contacts on the same channel. That means if you're chatting with Contact A about your email cleanup results, and Contact B messages the agent, Contact B's conversation can see context from Contact A's — tool outputs, message summaries, even content from your inbox.

I discovered this when I noticed the agent referencing a prior conversation I hadn't had on that device. The context was from a different contact's session.

The fix is a single config line, but it's not set by the onboarding wizard:

```jsonc
"whatsapp": {
  "session": {
    "dmScope": "per-channel-peer"
  }
}
```

This gives each contact their own isolated session. Without it, you're one curious friend away from leaking your email summaries.

## Your Agent Is Open to the World (By Default, It Shouldn't Be)

When I first set up WhatsApp, I configured an allowlist for DMs — only two phone numbers can interact with the agent. But I almost didn't. The config wizard asks about DM policy, and it's easy to leave it as `"open"` during testing and forget to lock it down.

An open DM policy means *anyone who messages your WhatsApp number* can interact with your agent. That includes triggering skills that execute shell commands on your machine. Think about that for a second.

The same applies to group policy. If you add the agent to a WhatsApp group with `"groupPolicy": "open"`, every group member can trigger your skills.

The checklist version:

```jsonc
"dmPolicy": "allowlist",
"allowFrom": ["+15551234567"],
"groupPolicy": "allowlist"
```

Set this before you do anything else.

## macOS Ships With Ancient bash

This one bit me during skill development, not OpenClaw configuration per se, but it's an OpenClaw ecosystem issue because many skills use bash scripts.

macOS ships with bash 3.2 — released in 2007. If any skill uses associative arrays (`declare -A`), which are a bash 4+ feature, the script fails with a cryptic syntax error that doesn't mention bash versions at all. You just get something like `declare: -A: invalid option`.

My gmail-agent scripts use associative arrays to map label names to label IDs. They worked fine on my Linux server and failed mysteriously on macOS until I realized the system bash was 17 years behind.

```bash
brew install bash    # Installs bash 5.x to /usr/local/bin/bash
```

Then either update your script shebangs to point at the Homebrew bash, or add `/usr/local/bin` to your PATH ahead of `/bin`.

## Long-Running Tasks Get Killed

OpenClaw agents have a per-turn timeout. If a skill runs a command that takes more than a couple of minutes — and Gmail batch operations absolutely can — the agent times out, kills the process, and reports a generic failure.

I discovered this when trying to delete 10,000+ old messages from a label hierarchy. The script would start, process a few hundred messages, and then just... stop. No error, no partial result, nothing in the WhatsApp chat.

The solution is to not run long tasks inside the agent turn at all. Instead, daemonize the work:

```bash
nohup bash -c 'your-long-command' </dev/null >/tmp/task.log 2>&1 &
disown
```

The parent process (your script) returns immediately, the agent turn completes, and the actual work continues in the background. I built a wrapper (`gmail-background-task.sh`) that does this plus sends WhatsApp progress updates every 30 seconds via `openclaw message send`.

This pattern — daemonize, poll, notify — is worth understanding for any skill that might run longer than a minute. The first version had a race condition where the monitor process would outlive the task but not detect it had finished. The fix: poll `kill -0 $PID` every 5 seconds (fast detection) but only send WhatsApp updates every 30 seconds (not spammy).

## Cron Jobs Need Isolation Too

I set up a daily cron job to summarize my inbox and purge spam at noon. It worked — but I noticed the agent's interactive session getting cluttered with cron output. The noon digest would inject its context into my active chat, and subsequent interactive messages would reference the digest.

The fix is `"sessionTarget": "isolated"`:

```json
{
  "sessionTarget": "isolated",
  "isolation": {
    "postToMainPrefix": "Cron",
    "postToMainMode": "summary",
    "postToMainMaxChars": 8000
  }
}
```

This runs the cron job in its own session and posts a summary back to the main thread when it's done. Clean separation. Without it, your cron jobs and interactive conversations share a single context window — which is confusing for both you and the agent.

## The Gateway Must Stay Running

This should be obvious but wasn't to me at first: OpenClaw's cron jobs are executed by the gateway process, not by the system crontab. If the gateway crashes, gets OOM-killed, or doesn't start after a reboot, your cron jobs silently stop firing.

I noticed my daily digest hadn't run for three days. The gateway had died after a macOS update and the LaunchAgent hadn't restarted it. No error, no notification — just silence.

```bash
openclaw gateway install    # Set up LaunchAgent (macOS)
openclaw gateway status     # Check health
```

After installing the LaunchAgent, it auto-restarts on crash and reboot. But verify it survived your next OS update — macOS sometimes clears LaunchAgents.

## WhatsApp Sessions Expire Quietly

The WhatsApp Web session that OpenClaw uses can disconnect without warning. If your phone loses internet for too long, or WhatsApp pushes a protocol update, the session drops. The gateway keeps running, your cron jobs keep firing, but message delivery silently fails.

I only noticed because my daily digest stopped arriving on WhatsApp even though `openclaw cron runs` showed successful executions. The cron job ran fine — it just couldn't deliver the result.

```bash
openclaw channels whatsapp status    # Check connection
openclaw channels whatsapp link      # Re-link if needed
```

There's no built-in alert for this. It would be nice if the gateway detected a dead WhatsApp session and logged a warning, but as of now it doesn't. I check manually every few days.

## Tailscale: Serve, Don't Funnel

OpenClaw supports Tailscale for remote access to the gateway dashboard. There are two modes:

- **Serve**: Exposes the gateway only on your Tailnet (your devices only)
- **Funnel**: Exposes the gateway to the public internet

I initially set up Funnel because I thought I might want to access the dashboard from a device not on my Tailnet. I quickly realized this was unnecessary — all my devices are on my Tailnet — and Funnel was exposing my agent's gateway to anyone who could guess the URL.

```jsonc
"tailscale": {
  "mode": "serve"
}
```

Unless you have a specific, well-understood reason for Funnel, use Serve.

## The Configuration Guide

I've distilled all of this — plus a few more minor gotchas — into a standalone [OpenClaw Configuration Guide](../docs/openclaw-config-guide.md). It's structured as a checklist you can walk through when setting up a new OpenClaw installation or auditing an existing one:

- Security hardening (DM isolation, allowlists, gateway auth, Tailscale)
- WhatsApp setup (self-chat, debounce, media limits)
- Agent configuration (workspace files, context budget, multi-agent)
- Scheduling (timezone, isolation, gateway dependency)
- Skills (precedence, symlinks, frontmatter)
- Maintenance (updates, cleanup, health checks)
- Common gotchas (bash version, agent timeout, session expiry, credential paths)

There's also a quick-reference checklist at the bottom for the minimum safe configuration.

## Is It Worth It?

Despite the rough edges — yes. OpenClaw turns WhatsApp into a surprisingly capable interface for running automation. I manage my entire Gmail workflow from it: daily digests, on-demand inbox summaries, label management, bulk deletion, all from the same app I use for regular messaging. The cron scheduling means the routine stuff happens without me thinking about it.

But it's the kind of tool where the defaults aren't safe enough, the failure modes are silent, and the documentation assumes you'll figure out the sharp edges on your own. Hopefully this post and the configuration guide help you skip that discovery process.

---

The configuration guide and all the gmail-agent scripts are on GitHub: [github.com/r39132/gmail-agent](https://github.com/r39132/gmail-agent). If you're using OpenClaw, the agent is also on [ClawHub](https://clawhub.ai/r39132/gmail-agent).
