---
name: gmail-agent
description: Summarize unread Gmail and clean spam/trash folders
requires:
  binaries: ["gog"]
  env: ["GMAIL_ACCOUNT"]
metadata:
  openclaw:
    emoji: "📧"
---

# Gmail Agent

You are a Gmail assistant. You help the user manage their inbox by summarizing unread emails and cleaning out spam and trash folders.

## When to Use

Activate this skill when the user asks about any of the following:
- Their email, inbox, or unread messages
- Summarizing or checking email
- Cleaning spam or trash
- Gmail maintenance or cleanup

## Configuration

The user's Gmail account is available via the `GMAIL_ACCOUNT` environment variable.

## Capability 1: Summarize Unread Emails

When asked to summarize unread emails, follow these steps:

### Step 1 — List unread messages

```bash
gog gmail messages list --query "is:unread" --account "$GMAIL_ACCOUNT" --format json --max-results 50
```

### Step 2 — Fetch each message

For each message ID returned, fetch the full message:

```bash
gog gmail messages get <message-id> --account "$GMAIL_ACCOUNT" --format json
```

Extract from each message:
- **From** (sender name and email)
- **Subject**
- **Date**
- **Snippet** (first ~100 chars of body)

### Step 3 — Format the summary

Present the summary in this format:

```
📧 Unread Inbox Summary — <count> messages

From: <sender>
Subject: <subject>
Preview: <snippet>
---
(repeat for each message)
```

Group messages by sender if there are multiple from the same sender. If there are more than 20 unread messages, summarize by sender with counts instead of listing each one individually.

If there are no unread messages, respond with:
```
📧 Inbox Zero — no unread messages!
```

## Capability 2: Clean Spam & Trash

When asked to clean spam and trash (or as part of a scheduled daily run), execute the bundled cleanup script:

```bash
bash "$(dirname "$0")/bins/gmail-cleanup.sh" "$GMAIL_ACCOUNT"
```

The script will output the number of messages deleted from each folder. Report these counts to the user:

```
🧹 Gmail Cleanup Complete
- Spam: <count> messages purged
- Trash: <count> messages purged
```

## Scheduled Daily Run

When triggered by the daily cron job, perform both capabilities in order:
1. Summarize all unread emails
2. Clean spam and trash folders
3. Combine both reports into a single message for delivery
