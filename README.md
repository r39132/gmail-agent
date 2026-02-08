# Gmail Agent

A CLI-driven Gmail agent that summarizes unread messages and purges spam/trash folders. Ships with an [OpenClaw](https://openclaw.ai) skill for chat-based and scheduled use, but the core scripts work standalone with **any agent framework** or directly from the command line.

## What It Does

| Capability | How | Delivery |
|---|---|---|
| **Summarize unread emails** | On-demand (chat or CLI) | Terminal, WhatsApp, or any channel |
| **Purge spam & trash** | On-demand or scheduled | Terminal, WhatsApp, or any channel |
| **Daily digest + cleanup** | Cron job (noon, configurable) | WhatsApp (via OpenClaw) |

## Platform Support

| Platform | Status | Notes |
|---|---|---|
| **macOS** | Fully supported | Tested on Apple Silicon and Intel |
| **Linux** | Fully supported | Any distro with bash 4+ |
| **Windows (WSL)** | Fully supported | Use WSL2 with Ubuntu or similar |
| **Windows (native)** | Partial | Scripts require bash; use Git Bash or WSL |

## Prerequisites

- **bash** 4.0+ (ships with Linux; macOS users may need `brew install bash`)
- **[gog CLI](https://github.com/nicholasgasior/gog)** — Google API CLI tool
- **[jq](https://jqlang.github.io/jq/)** — JSON processor
- A **Google Cloud project** with the Gmail API enabled

### Installing Prerequisites

<details>
<summary>macOS (Homebrew)</summary>

```bash
brew install jq bash
npm install -g gogcli
```
</details>

<details>
<summary>Ubuntu / Debian</summary>

```bash
sudo apt-get update && sudo apt-get install -y jq
npm install -g gogcli
```
</details>

<details>
<summary>Fedora / RHEL</summary>

```bash
sudo dnf install -y jq
npm install -g gogcli
```
</details>

<details>
<summary>Windows (WSL)</summary>

```bash
# Inside WSL (Ubuntu)
sudo apt-get update && sudo apt-get install -y jq
npm install -g gogcli
```
</details>

## Setup

### 1. Create a GCP Project and Enable Gmail API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select an existing one)
3. Navigate to **APIs & Services > Library**
4. Search for **Gmail API** and click **Enable**

### 2. Create OAuth 2.0 Credentials

1. Go to **APIs & Services > Credentials**
2. Click **Create Credentials > OAuth client ID**
3. Select **Desktop app** as the application type
4. Give it a name (e.g., "Gmail Agent")
5. Click **Create** and download the credentials JSON file

> **Security note:** Store the credentials file outside this repository (e.g., `~/.config/gog/credentials.json`). Never commit credentials to version control.

### 3. Configure OAuth Consent Screen

1. Go to **APIs & Services > OAuth consent screen**
2. Choose **External** (or **Internal** for Google Workspace orgs)
3. Fill in required fields (app name, support email)
4. Add these scopes:
   - `https://www.googleapis.com/auth/gmail.readonly` — read messages
   - `https://www.googleapis.com/auth/gmail.modify` — delete spam/trash
5. Under **Test users**, add the Gmail address you'll use

### 4. Authorize the gog CLI

```bash
gog auth login
```

This opens a browser for OAuth consent. After authorizing, verify it works:

```bash
gog gmail messages search "is:unread" --account YOUR_EMAIL --max 5
```

### 5. Configure Environment Variables

```bash
cp .env.example .env
```

Edit `.env` and set your Gmail address:

```bash
GMAIL_ACCOUNT="your-email@gmail.com"
```

Then source it:

```bash
source .env
```

For persistence, add `export GMAIL_ACCOUNT="your-email@gmail.com"` to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.).

## Usage

### Standalone (no agent framework needed)

The core scripts work directly from the command line:

```bash
# Summarize unread emails (using gog directly)
gog gmail messages search "is:unread" --account "$GMAIL_ACCOUNT" --max 50 --plain

# Clean spam and trash
source .env
bash skills/gmail-agent/bins/gmail-cleanup.sh
```

### With OpenClaw

OpenClaw is an AI agent gateway that adds chat-based interaction and scheduling. If you use OpenClaw:

#### Install the skill

```bash
bash setup/install-skill.sh
```

This symlinks the skill into `~/.openclaw/workspace/skills/gmail-agent` so OpenClaw discovers it automatically.

#### Register the daily cron job

```bash
bash setup/register-cron-jobs.sh
```

#### Chat with it

Message OpenClaw through any connected channel:

- *"Summarize my unread emails"*
- *"Check my inbox"*
- *"Clean my spam and trash"*
- *"What emails do I have?"*

#### Scheduled runs

The cron job fires daily at noon Pacific (configurable in `.env`). It:
1. Summarizes all unread emails
2. Purges spam and trash
3. Delivers the report to WhatsApp

If a scheduled run is missed (machine asleep, gateway down), OpenClaw's retry backoff (30s, 1m, 5m, 15m, 60m) runs it at the next opportunity.

#### Verify setup

```bash
openclaw skills list | grep gmail       # Skill discovered?
openclaw cron list                       # Cron registered?
openclaw cron run gmail-daily-noon       # Manual test run
```

### With Other Agent Frameworks

The core logic is plain shell commands using the `gog` CLI. You can integrate it with any framework that can execute shell commands.

<details>
<summary>Claude Code / Claude Desktop (MCP)</summary>

Use the `gog` commands from `SKILL.md` as tool calls. The SKILL.md file itself serves as a prompt/instruction document that any LLM agent can follow.

```bash
# Example: have Claude Code run the cleanup
bash skills/gmail-agent/bins/gmail-cleanup.sh "$GMAIL_ACCOUNT"
```
</details>

<details>
<summary>LangChain / LangGraph</summary>

Wrap the shell commands as LangChain tools:

```python
from langchain_core.tools import tool
import subprocess, os

@tool
def summarize_inbox() -> str:
    """List unread Gmail messages."""
    result = subprocess.run(
        ["gog", "gmail", "messages", "list",
         "is:unread",
         "--account", os.environ["GMAIL_ACCOUNT"],
         "--max", "50", "--json"],
        capture_output=True, text=True
    )
    return result.stdout

@tool
def clean_spam_trash() -> str:
    """Purge spam and trash folders."""
    result = subprocess.run(
        ["bash", "skills/gmail-agent/bins/gmail-cleanup.sh"],
        capture_output=True, text=True
    )
    return result.stdout
```
</details>

<details>
<summary>CrewAI</summary>

Use CrewAI's shell tool or a custom tool that calls `gmail-cleanup.sh` and the `gog` CLI commands listed in SKILL.md.
</details>

<details>
<summary>Plain cron (no agent framework)</summary>

Skip agent frameworks entirely and schedule via system cron:

```bash
# crontab -e
0 12 * * * source ~/.env && bash ~/Projects/gmail-agent/skills/gmail-agent/bins/gmail-cleanup.sh >> ~/gmail-agent.log 2>&1
```
</details>

## Project Structure

```
gmail-agent/
├── .env.example                       # Template for environment variables
├── .gitignore                         # Excludes .env, credentials, OS artifacts
├── README.md                          # This file
├── skills/
│   └── gmail-agent/
│       ├── SKILL.md                   # Agent skill definition (OpenClaw + general)
│       └── bins/
│           └── gmail-cleanup.sh       # Standalone spam & trash purge script
└── setup/
    ├── install-skill.sh               # Symlink skill into OpenClaw workspace
    └── register-cron-jobs.sh          # Register cron jobs via OpenClaw CLI
```

### What lives where

| Layer | Files | Framework dependency |
|---|---|---|
| **Core logic** | `gmail-cleanup.sh`, `gog` CLI commands in SKILL.md | None — just bash + gog + jq |
| **Agent instructions** | `SKILL.md` | OpenClaw format, but readable by any LLM |
| **OpenClaw integration** | `setup/*.sh` | OpenClaw CLI |

## Environment Variables Reference

| Variable | Required | Description |
|---|---|---|
| `GMAIL_ACCOUNT` | Yes | Gmail address to manage |
| `CRON_TIMEZONE` | No | Timezone for scheduled runs (default: `America/Los_Angeles`) |
| `CRON_SCHEDULE` | No | Cron expression (default: `0 12 * * *` = noon daily) |

## Troubleshooting

### `gog: command not found`

Install it: `npm install -g gogcli`. Ensure your npm global bin directory is in `$PATH`.

### `jq: command not found`

See [Installing Prerequisites](#installing-prerequisites) for your platform.

### `Error: No Gmail account specified`

Set `GMAIL_ACCOUNT` in your `.env` file and run `source .env`, or pass it as an argument:
```bash
bash skills/gmail-agent/bins/gmail-cleanup.sh your-email@gmail.com
```

### Gmail API returns 403 Forbidden

1. Confirm the Gmail API is enabled in your GCP project
2. Verify your OAuth consent screen includes the `gmail.readonly` and `gmail.modify` scopes
3. Re-authenticate: `gog auth login`

### Cron job not firing (OpenClaw)

```bash
openclaw cron list                       # Is the job registered?
openclaw cron run gmail-daily-noon       # Does manual trigger work?
openclaw gateway status                  # Is the gateway running?
```

## License

MIT
