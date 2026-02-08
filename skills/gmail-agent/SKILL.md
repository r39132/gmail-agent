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

There are two modes. Choose based on what the user asks:

- **Inbox only (default):** When the user says "summarize my emails", "check my inbox", "what's in my inbox", or any request that doesn't explicitly say "all" — search only the inbox.
- **All unread:** When the user explicitly says "all my unread emails", "all unread", or "everything unread" — search across all labels, excluding spam and trash.

### Step 1 — Search unread messages

**Inbox only (default):**
```bash
gog gmail messages search "is:unread in:inbox" --account "$GMAIL_ACCOUNT" --max 50 --plain
```

**All unread (when user explicitly asks for all):**
```bash
gog gmail messages search "is:unread -in:spam -in:trash" --account "$GMAIL_ACCOUNT" --max 50 --plain
```

Both return a TSV table with columns: ID, THREAD, DATE, FROM, SUBJECT, LABELS.

### Step 2 — Fetch a specific message (if more detail is needed)

```bash
gog gmail get <message-id> --account "$GMAIL_ACCOUNT" --format full --json
```

Use `--format metadata --headers "From,Subject,Date"` for just headers, or `--format full` for the complete message.

### Step 3 — Format the summary

Present the summary in this format:

```
Unread Inbox Summary — <count> messages          (or "Unread Summary (All)" for all-unread mode)

From: <sender>
Subject: <subject>
Date: <date>
---
(repeat for each message)
```

Group messages by sender if there are multiple from the same sender. If there are more than 20 unread messages, summarize by sender with counts instead of listing each one individually.

If there are no unread messages, respond with:
```
Inbox Zero — no unread messages!
```

## Capability 2: Clean Spam & Trash

When asked to clean spam and trash (or as part of a scheduled daily run), execute the bundled cleanup script:

```bash
bash skills/gmail-agent/bins/gmail-cleanup.sh "$GMAIL_ACCOUNT"
```

The script will output the number of messages deleted from each folder. Report these counts to the user:

```
Gmail Cleanup Complete
- Spam: <count> messages purged
- Trash: <count> messages purged
```

## Scheduled Daily Run

When triggered by the daily cron job, perform both capabilities in order:
1. Summarize all unread emails (use the "all unread" mode, not inbox-only)
2. Clean spam and trash folders
3. Combine both reports into a single message for delivery
