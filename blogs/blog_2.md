# From Cleanup to Full Inbox Control: What's New in Gmail Agent

*February 12, 2026*

---

When I wrote the [first blog post](blog_1.md), Gmail Agent could summarize your inbox, audit labels, and purge spam. Useful — but still pretty limited. I kept running into situations where I needed to actually *do* things with messages and labels, not just report on them. So over the past few days, I've added five new capabilities that turn Gmail Agent from a read-only reporter into a full inbox management tool.

Here's what changed.

## 1. Move Messages to Labels from WhatsApp

This was the feature I wanted most. Gmail's mobile app is terrible at label navigation when you have a deeply nested folder structure. Searching for a label by typing characters? Not supported. So I built it.

The workflow is interactive and designed for agent use:

```bash
# Search for labels matching a keyword
bash skills/gmail-agent/bins/gmail-move-to-label.sh "$GMAIL_ACCOUNT" --search-labels "receipts"

# List inbox messages
bash skills/gmail-agent/bins/gmail-move-to-label.sh "$GMAIL_ACCOUNT" --list-inbox

# Move specific messages to a label
bash skills/gmail-agent/bins/gmail-move-to-label.sh "$GMAIL_ACCOUNT" --move "Personal/Receipts" msg-1 msg-2

# Changed your mind? Undo
bash skills/gmail-agent/bins/gmail-move-to-label.sh "$GMAIL_ACCOUNT" --undo "Personal/Receipts" msg-1 msg-2
```

From WhatsApp through OpenClaw, I just say "Move messages to Receipts" and the agent walks through the steps: find matching labels, show my inbox, confirm which messages, move them. No more opening the Gmail app on my phone and scrolling through a flat label list.

## 2. Delete Labels (and Everything Under Them)

I had accumulated dozens of labels from old projects that I no longer needed. Gmail's UI lets you delete one label at a time — with no sublabel handling. Gmail Agent does the whole tree:

```bash
# Delete label + all sublabels (keep messages)
bash skills/gmail-agent/bins/gmail-delete-labels.sh "Professional/OldCompany" "$GMAIL_ACCOUNT"

# Delete label + trash ALL messages
bash skills/gmail-agent/bins/gmail-delete-labels.sh "Professional/OldCompany" --delete-messages "$GMAIL_ACCOUNT"
```

This was my first script that uses the Gmail API directly through Python instead of purely relying on `gog`. The `gog` CLI doesn't expose label deletion, so the script reads `gog`'s OAuth credentials and calls the Gmail API via `google-api-python-client`. Same credentials, no extra auth step.

I initially tried using [GAM](https://github.com/GAM-team/GAM) (Google Apps Manager) for this, but it required Google Workspace admin access — overkill for a personal Gmail account. Calling the Gmail API directly with Python was simpler and worked with the same OAuth credentials I already had.

## 3. Delete Old Messages by Date

This is the feature that reclaimed the most storage. I had years of messages under labels like `Personal/Archive` and `Professional/Learn` that I'd never look at again. The script takes a label and a date, finds every message older than that date in the label and all its sublabels, and deletes them:

```bash
bash skills/gmail-agent/bins/gmail-delete-old-messages.sh "Personal/Archive" "01/01/2020" "$GMAIL_ACCOUNT"
```

There's a subtlety here: Gmail's search index isn't instantly consistent after batch deletions. The script handles this by looping — search, delete batch, search again — until no more matches come back. Without this loop, you'd think you were done but still have hundreds of messages lingering.

## 4. Permanent Delete (Full-Scope Auth)

By default, all delete operations in Gmail Agent just trash messages — Gmail auto-deletes them after 30 days. But if you're trying to reclaim storage *now*, that's not enough. The problem is that permanent deletion requires the `https://mail.google.com/` scope, which is broader than the `gmail.modify` scope that `gog` uses.

I added a one-time OAuth setup script that grants this scope and stores the token separately:

```bash
bash skills/gmail-agent/bins/gmail-auth-full-scope.sh "$GMAIL_ACCOUNT"
# Token saved to: ~/.gmail-agent/full-scope-token.json
```

Once this token exists, the delete-old-messages script automatically switches from `messages.trash` to `messages.batchDelete` — permanent, immediate deletion. The full-scope token is stored separately from `gog`'s credentials so there's no risk of breaking existing functionality.

## 5. Background Execution with WhatsApp Notifications

Some operations take a long time. Deleting 10,000 messages from a label hierarchy, or fetching message counts for every label in a large account — these can run for 5-10 minutes. The OpenClaw agent would time out waiting.

The solution: run any task in the background with WhatsApp progress updates.

```bash
export WHATSAPP_NOTIFY_TARGET="+15555550123"
bash skills/gmail-agent/bins/gmail-bg "Archive Cleanup" \
    "bash skills/gmail-agent/bins/gmail-delete-old-messages.sh 'Personal/Archive' '01/01/2020' '$GMAIL_ACCOUNT'"
```

The script fully daemonizes the task using `nohup` + subshell + `disown`, so it survives even if the agent process dies. A monitor loop polls every 5 seconds and sends a WhatsApp update every 30 seconds with elapsed time. When the task completes (or fails), you get a final notification with the full output.

Job tracking is built in — every background task gets registered in `~/.gmail-agent/jobs/` as a JSON file:

```bash
bash skills/gmail-agent/bins/gmail-jobs              # All jobs
bash skills/gmail-agent/bins/gmail-jobs --running    # Running only
bash skills/gmail-agent/bins/gmail-jobs --completed  # Completed only
bash skills/gmail-agent/bins/gmail-jobs --clean      # Remove old records
```

This was also the trickiest feature to get right. The first version had a race condition where the monitor would outlive the task but not detect it. The fix was polling `kill -0 $PID` every 5 seconds (fast detection) while only sending WhatsApp notifications every 30 seconds (not spammy).

## What Got Removed

Not everything survived. The Label Audit capability from blog 1 — the one that classified messages as single-label vs. multi-label — turned out to be more complex than useful. The distinction became irrelevant once I had proper label deletion and date-based cleanup. I removed it and simplified the remaining capabilities.

I also changed the inbox summary to show ALL messages (read + unread), marking unread ones with `**` prefix, instead of only showing unread. Turns out knowing what's in my inbox matters more than just what's new.

## The Stack Today

The architecture hasn't changed — it's still bash scripts wrapping `gog` CLI wrapping the Gmail API. But the dependency surface grew slightly:

| Layer | What's needed |
|-------|--------------|
| **Core** | bash + `gog` + jq |
| **Label/message delete** | + python3, google-auth, google-api-python-client |
| **Permanent delete** | + google-auth-oauthlib (one-time setup) |
| **Background tasks** | + OpenClaw (for WhatsApp notifications) |

Everything still works standalone from the CLI. OpenClaw adds the chat interface and cron scheduling, but you can run every script directly.

## What's Next

With these additions, Gmail Agent covers the workflows I actually use daily. The daily cron digest handles the routine, and the interactive commands handle everything else — all from WhatsApp. The next areas I'm thinking about:

- **Smart categorization** — use an LLM to classify messages by urgency and topic
- **Auto-archival rules** — define rules for messages that should auto-archive after N days
- **Storage analytics** — break down storage usage by label, sender, and date range

The full source is on GitHub: [github.com/r39132/gmail-agent](https://github.com/r39132/gmail-agent). If you're using OpenClaw, install it from [ClawHub](https://clawhub.ai/r39132/gmail-agent) in one command:

```bash
clawhub install gmail-agent
```
