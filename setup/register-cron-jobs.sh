#!/usr/bin/env bash
#
# register-cron-jobs.sh — Register Gmail agent cron jobs with OpenClaw
#
# Usage: register-cron-jobs.sh
#   Delivers to the last-used channel (e.g., WhatsApp) by default.
#   Set CRON_TIMEZONE and CRON_SCHEDULE in .env to customize.
#
set -euo pipefail

CRON_TIMEZONE="${CRON_TIMEZONE:-America/Los_Angeles}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 12 * * *}"

echo "Registering Gmail daily noon cron job..."
echo ""

openclaw cron add \
    --name "gmail-daily-noon" \
    --cron "$CRON_SCHEDULE" \
    --tz "$CRON_TIMEZONE" \
    --session isolated \
    --message "Run the gmail-agent skill: 1) Summarize all unread emails in my inbox. 2) Clean out my spam and trash folders. Report what you did." \
    --model opus \
    --deliver

echo ""
echo "Cron job 'gmail-daily-noon' registered successfully."
echo ""
echo "Schedule: $CRON_SCHEDULE ($CRON_TIMEZONE)"
echo "Delivery: last-used channel"
echo ""
echo "Verify with:  openclaw cron list"
echo "Test with:    openclaw cron run gmail-daily-noon"
