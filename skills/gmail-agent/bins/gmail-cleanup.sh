#!/usr/bin/env bash
#
# gmail-cleanup.sh — Clean out Gmail Spam and Trash folders
# Uses batch modify to remove labels (requires only gmail.modify scope)
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
    local label_upper
    label_upper=$(echo "$label" | tr '[:lower:]' '[:upper:]')

    # Search for all message IDs in the given label (plain TSV, first column is ID)
    # Skip the header line, extract just the ID column
    local ids
    ids=$(gog gmail messages search "in:${label}" \
        --account "$ACCOUNT" \
        --max 500 \
        --plain 2>&1 \
        | tail -n +2 \
        | grep -vE '^(#|No results)' \
        | cut -f1 || true)

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

        # Batch modify in groups of 100 (Gmail API limit per batch)
        if [[ ${#batch_ids[@]} -ge 100 ]]; then
            gog gmail batch modify "${batch_ids[@]}" \
                --account "$ACCOUNT" \
                --remove="$label_upper" \
                --force >&2
            batch_ids=()
        fi
    done <<< "$ids"

    # Process remaining messages
    if [[ ${#batch_ids[@]} -gt 0 ]]; then
        gog gmail batch modify "${batch_ids[@]}" \
            --account "$ACCOUNT" \
            --remove="$label_upper" \
            --force >&2
    fi

    echo "$count"
}

echo "Cleaning Gmail for $ACCOUNT..."
echo ""

spam_count=$(cleanup_label "spam")
echo "Spam: ${spam_count} messages cleaned"

trash_count=$(cleanup_label "trash")
echo "Trash: ${trash_count} messages cleaned"

echo ""
echo "Done."
