# Managing Gmail from WhatsApp: An Agent-Driven Approach

*February 8, 2026*

<p align="center">
  <img src="docs/images/open-claw-gmail-banner.jpg" width="600" alt="Email Universe: Organized - Taming the Data Stream" />
</p>

---
My Gmail storage was getting out of hand. Not solely because I get too much spam, but also because I don't have time to keep up with manual deletion. Cleaning up trash and spam folders in Gmail in an automated way is not easy to do — it requires setting up and managing a custom workflow to run daily cleanups. And when there are many messages to purge, Gmail executes them in batches that can take tens of minutes to complete. 

I also wanted the ability to move messages to a folder (a.k.a. label) with a simple command — without having to navigate the Gmail app's clunky label UI on mobile. I have a deeply nested folder structure, and the Gmail app doesn't handle it well. I wanted to be able to type characters into the app to find a target folder to move a message to. The Gmail app sadly doesn't do this, so I'm left to my own devices, usually waiting until I have a laptop in front of me.

In the bulk deletion case, rather than hand-holding the process, what I needed was something that could run unattended on a daily cron, handle the batching automatically, and report results back to me on WhatsApp — all orchestrated by an agent I was already using. For the folder navigation problem, I wanted a simple "search for label by keyword and move this message there" workflow that I could trigger from WhatsApp without opening the Gmail app at all.

This sounded like a perfect use case for an agent loop. With growing buzz around Agentic and the recent release of [OpenClaw](https://openclaw.ai), I looked for an agent that could solve this problem within [ClawHub](https://clawhub.ai). I first came across the [gogcli agent](https://clawbot.ai/ecosystem/gogcli.html). While useful, its primitives were too low-level to serve my needs. OpenClaw, while it has rough edges, provides a good "onboarding" experience and the ability to use your favorite chat app as the frontend UI. I chose WhatsApp — which means I can manage my Gmail inbox from WhatsApp.

## Gmail Agent To the Rescue

**Gmail Agent** is complementary to the gogcli agent, but provides higher-level skills for your agent loop. It's a set of bash scripts that wrap the [`gog` CLI](https://github.com/nicholasgasior/gog) to summarize unread mail, audit label hierarchies, and purge spam and trash. While I've tested it with OpenClaw and Claude Desktop, it should work with CrewAI, LangChain, and any other framework that can execute shell commands.

## How It Works

The architecture is deliberately simple:

```
User (WhatsApp / CLI)
  → OpenClaw Gateway
    → gmail-agent skill
      → bins/ shell scripts
        → gog CLI
          → Gmail API
```

At the bottom of the stack is Google's Gmail API. The `gog` CLI (from the [gogcli agent](https://clawbot.ai/ecosystem/gogcli.html)) handles OAuth and provides a clean command-line interface to it. My shell scripts compose those low-level `gog` commands into the higher-level workflows I actually need — things like "purge all spam and trash in batches, handle pagination, and report what was deleted." OpenClaw sits on top, routing WhatsApp messages and cron triggers to those scripts so everything runs hands-free.

The key design decision: **every layer is optional except the scripts and `gog`**. Strip away OpenClaw and you still have CLI tools I can run manually or from cron. Strip away the scripts and I still have the documented `gog` commands if I want to go low-level.

## What It Can Do

### 1. Inbox Summary

Before I can clean up, I need to know what's there. One command gives me a formatted summary of unread messages with sender, subject, and date — delivered right to WhatsApp if I'm using OpenClaw:

```bash
gog gmail messages search "is:unread in:inbox" \
  --account "$GMAIL_ACCOUNT" --max 50 --plain
```

When there are more than 20 unread messages, the agent groups them by sender with counts instead of listing each one — so I get a useful overview, not a wall of text. I can trigger this from WhatsApp with a simple "Summarize my inbox" message.

### 2. Folder Structure

As I mentioned, I have a deeply nested label hierarchy — and the Gmail app makes it nearly impossible to navigate. The `gmail-labels.sh` script fetches every label with its total and unread counts and presents them as a tree:

```
INBOX                          16 total, 1 unread
SENT                        4521 total

Personal/                     203 total
  Family/                     112 total
  Home/                       844 total, 6 unread

Professional/                1205 total
  Apache/Airflow            18302 total, 13200 unread
```

This was eye-opening. I had no idea I had 13,000 unread Apache Airflow messages sitting in a label I never checked — that's the kind of silent storage bloat that creeps up on you.

### 3. Label Audit & Cleanup

This is the feature that started paying back storage space immediately. The `gmail-label-audit.sh` script inspects a label hierarchy and classifies every message as either:

- **SINGLE** — the message only lives under this label (safe to remove)
- **MULTI** — the message also has other user labels (leave it alone)

This distinction is critical. If I want to clean out `Personal/Receipts/2023`, I don't want to accidentally remove labels from messages that are also filed under `Taxes/2023`. The audit script handles this automatically, and it only proceeds with cleanup after explicit confirmation. This is exactly the kind of multi-step workflow that would be tedious to build from raw `gog` commands every time — and exactly why I built Gmail Agent on top of gogcli.

### 4. Spam & Trash Purge

This is the feature that solved my original problem. The `gmail-cleanup.sh` script batch-deletes everything in SPAM and TRASH — handling pagination, chunking, and retries automatically so I don't have to sit there clicking through Gmail's batch UI:

```bash
bash skills/gmail-agent/bins/gmail-cleanup.sh "$GMAIL_ACCOUNT"
```

What used to take tens of minutes of manual babysitting now runs unattended and reports back how many messages were purged from each folder.

### 5. Daily Digest (Cron)

This is where the agent loop ties everything together. I registered a daily cron job through OpenClaw that fires at noon Pacific. It summarizes all unread mail, purges spam and trash, and delivers the combined report to me on WhatsApp. I don't have to think about storage pressure anymore — the agent handles it every day, and I get a brief summary to glance at over lunch.

## Where to Get It

The full source code, documentation, and setup guide live on GitHub: [github.com/r39132/gmail-agent](https://github.com/r39132/gmail-agent).

The agent is also published on [ClawHub](https://clawhub.ai/r39132/gmail-agent), so if you're already using OpenClaw you can install it in one command:

```bash
clawhub install gmail-agent
```

That pulls down the skill definition, shell scripts, and cron job configs — ready to use immediately.

## Framework Agnostic by Design

I built Gmail Agent for OpenClaw and WhatsApp, but I deliberately kept it portable. The `SKILL.md` file serves double duty — for OpenClaw it's a structured skill definition with frontmatter metadata; for everything else it's a plain-English instruction document that any LLM agent can follow.

This means you can use Gmail Agent with:

- **OpenClaw** — install as a skill, get WhatsApp chat and cron integration out of the box
- **Claude Code / Claude Desktop** — use the `gog` commands from SKILL.md as tool calls
- **LangChain / LangGraph** — wrap the shell commands as Python tools
- **CrewAI** — use the built-in shell tool executor
- **Plain cron** — no agent framework at all, just `crontab -e`

I've tested it with OpenClaw and Claude Desktop myself. The core logic is just bash + `gog` + `jq`, so any framework that can execute shell commands should work.

## Compatibility with gogcli

As I mentioned in the intro, I found the [gogcli agent](https://clawbot.ai/ecosystem/gogcli.html) on ClawHub first. It's a solid general-purpose Google API assistant — you can search messages, fetch labels, modify threads, and call any Gmail endpoint with a single `gog` command. But for my daily cleanup workflow, the primitives were too low-level. I didn't want to string together dozens of API calls by hand every time I needed to purge spam.

Gmail Agent is built *on top of* gogcli and adds the higher-order workflows I was missing:

- **Batch spam/trash purging** — Paginates through all messages in SPAM and TRASH, chunks them into batches, issues bulk deletes with progress reporting. No more hand-holding Gmail's batch UI.
- **Label auditing** — traverses an entire label hierarchy, classifies each message as single-label or multi-label, and selectively cleans up only the safe ones.
- **Folder structure snapshots** — iterates over every label, fetches counts individually, and renders a tree view — essential for understanding where storage is going.
- **Scheduled digests** — combines summary + purge into a single cron-triggered workflow that delivers results to WhatsApp.

The two agents coexist cleanly. Think of gogcli as `curl` and Gmail Agent as the shell scripts you'd write around it. Both use the same OAuth credentials and the same `gog` binary, so there's zero conflict. I still use gogcli for ad-hoc queries and one-off API calls — Gmail Agent handles the repeatable, daily operations I'd otherwise forget to do.

## Getting Started

Setup takes about five minutes:

1. **Install the CLI tools:**
   ```bash
   brew install jq bash
   npm install -g gogcli
   ```

2. **Create a GCP project**, enable the Gmail API, and set up OAuth credentials (full walkthrough in the [Setup Guide](docs/SETUP.md)).

3. **Authenticate:**
   ```bash
   gog auth login
   ```

4. **Configure your account:**
   ```bash
   echo 'GMAIL_ACCOUNT="you@gmail.com"' > .env && source .env
   ```

5. **Try it out:**
   ```bash
   gog gmail messages search "is:unread in:inbox" \
     --account "$GMAIL_ACCOUNT" --max 5 --plain
   ```

The project is open source under the MIT license: [github.com/r39132/gmail-agent](https://github.com/r39132/gmail-agent).

## What's Next?

The label navigation feature is now implemented! You can move messages to folders by typing keywords into WhatsApp. The agent searches your label hierarchy, shows matches, lets you select messages from your inbox, and moves them to the target label — all without opening the Gmail app.

Future enhancements on the roadmap:

- **Smart categorization** — use an LLM to classify messages by urgency and topic automatically
- **Auto-archival rules** — define rules in a config file for messages that should be auto-archived after N days
- **Bulk label operations** — apply or remove labels from multiple messages based on search criteria

---

If you're tired of babysitting Gmail's batch deletion UI, or you want to manage your inbox from WhatsApp instead of wrestling with the Gmail app's label navigation, give [Gmail Agent](https://github.com/r39132/gmail-agent) a try. It's a few bash scripts on top of gogcli, five minutes of setup, and a daily cron job that keeps your storage in check without you lifting a finger.
