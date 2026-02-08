#!/usr/bin/env bash
#
# gmail-cleanup.sh — Purge all messages from Gmail Spam and Trash folders
#
# Usage: gmail-cleanup.sh [account-email]
#   account-email: Gmail address (defaults to $GMAIL_ACCOUNT env var)
#
set -euo pipefail

ACCOUNT="${1:-${GMAIL_ACCOUNT:-}}"

if [[ -z "$ACCOUNT" ]]; then
    echo "Error: No Gmail account specified." >&2
    echo "Usage: $0 <account-email>  OR  set GMAIL_ACCOUNT env var" >&2
    exit 1
fi

cleanup_label() {
    local label="$1"
    local ids

    # Search for all message IDs in the given label
    ids=$(gog gmail messages search "in:${label}" \
        --account "$ACCOUNT" \
        --max 500 \
        --json 2>/dev/null \
        | jq -r '.[].id // empty' 2>/dev/null || true)

    if [[ -z "$ids" ]]; then
        echo "0"
        return
    fi

    local count=0
    local batch_ids=()

    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        batch_ids+=("$id")
        ((count++))

        # Batch delete in groups of 100 (Gmail API limit per batch)
        if [[ ${#batch_ids[@]} -ge 100 ]]; then
            gog gmail batch delete "${batch_ids[@]}" \
                --account "$ACCOUNT" \
                --force 2>/dev/null || true
            batch_ids=()
        fi
    done <<< "$ids"

    # Delete remaining messages
    if [[ ${#batch_ids[@]} -gt 0 ]]; then
        gog gmail batch delete "${batch_ids[@]}" \
            --account "$ACCOUNT" \
            --force 2>/dev/null || true
    fi

    echo "$count"
}

echo "Cleaning Gmail for $ACCOUNT..."
echo ""

spam_count=$(cleanup_label "spam")
echo "Spam: ${spam_count} messages purged"

trash_count=$(cleanup_label "trash")
echo "Trash: ${trash_count} messages purged"

echo ""
echo "Done."
