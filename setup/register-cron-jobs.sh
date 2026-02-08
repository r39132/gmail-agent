#!/usr/bin/env bash
#
# register-cron-jobs.sh — Register Gmail agent cron jobs with OpenClaw
#
# Usage: register-cron-jobs.sh [whatsapp-target]
#   whatsapp-target: WhatsApp phone number or contact ID for delivery
#
set -euo pipefail

WHATSAPP_TARGET="${1:-${WHATSAPP_TARGET:-}}"
CRON_TIMEZONE="${CRON_TIMEZONE:-America/Los_Angeles}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 12 * * *}"

if [[ -z "$WHATSAPP_TARGET" ]]; then
    echo "Error: WhatsApp target not specified." >&2
    echo "Usage: $0 <whatsapp-target>" >&2
    echo "  Or set WHATSAPP_TARGET in your .env file." >&2
    echo "" >&2
    echo "  whatsapp-target: phone number (e.g., +1234567890) or contact ID" >&2
    exit 1
fi

echo "Registering Gmail daily noon cron job..."
echo ""

openclaw cron add \
    --name "gmail-daily-noon" \
    --cron "$CRON_SCHEDULE" \
    --tz "$CRON_TIMEZONE" \
    --session isolated \
    --message "Run the gmail-agent skill: 1) Summarize all unread emails in my inbox. 2) Clean out my spam and trash folders. Report what you did." \
    --model opus \
    --announce \
    --channel whatsapp \
    --to "$WHATSAPP_TARGET"

echo ""
echo "Cron job 'gmail-daily-noon' registered successfully."
echo ""
echo "Schedule: $CRON_SCHEDULE ($CRON_TIMEZONE)"
echo "Delivery: WhatsApp to $WHATSAPP_TARGET"
echo ""
echo "Verify with:  openclaw cron list"
echo "Test with:    openclaw cron run gmail-daily-noon"
