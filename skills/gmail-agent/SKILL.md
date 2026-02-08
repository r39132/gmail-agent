---
name: gmail-agent
description: Summarize unread Gmail, show folder structure, and clean spam/trash
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
- Their folder structure, labels, or label counts
- Cleaning spam or trash
- Gmail maintenance or cleanup

## Configuration

The user's Gmail account is available via the `GMAIL_ACCOUNT` environment variable.

## Capability 1: Summarize Unread Emails

**CRITICAL — There are two modes. You MUST choose the correct one:**

1. **Inbox only (THIS IS THE DEFAULT — use this unless the user says "all"):**
   Use this for: "summarize my emails", "check my inbox", "check my email", "what's new", "unread emails", or ANY request that does NOT contain the word "all".
   Query: `is:unread in:inbox`

2. **All unread (ONLY when user explicitly says "all"):**
   Use this ONLY for: "all my unread emails", "all unread", "summarize all", "everything unread".
   The word "all" must appear in the user's request.
   Query: `is:unread -in:spam -in:trash`

**When in doubt, use inbox only.**

### Step 1 — Search unread messages

**Inbox only (default — ALWAYS use this unless user says "all"):**
```bash
gog gmail messages search "is:unread in:inbox" --account "$GMAIL_ACCOUNT" --max 50 --plain
```

**All unread (ONLY when user explicitly includes the word "all"):**
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

## Capability 2: Folder Structure with Message Counts

When the user asks about their folder structure, labels, or how their email is organized, run the bundled labels script:

```bash
bash skills/gmail-agent/bins/gmail-labels.sh "$GMAIL_ACCOUNT"
```

This outputs one line per label with message counts (TSV: label name, total count, unread count if any).

**Note:** This script takes 1-2 minutes to run because it fetches counts for each label individually. Warn the user that it may take a moment.

### Formatting the output

Present the results as a tree, using the `/` separators in label names to show hierarchy. For example:

```
Gmail Folder Structure

INBOX                          16 total, 1 unread
SENT                          4521 total
DRAFT                            2 total

Personal/                      203 total
  Family/                      112 total
    Marriage/Next               44 total
  Home/                        844 total, 6 unread
  Medical                       22 total

Professional/                  1205 total
  Apache/Airflow              18302 total, 13200 unread
  Companies/                     45 total
```

- Indent nested labels under their parent
- Show unread counts only when > 0
- Skip labels with 0 messages
- Group system labels (INBOX, SENT, DRAFT, SPAM, TRASH) at the top, then user labels

## Capability 3: Clean Spam & Trash

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
