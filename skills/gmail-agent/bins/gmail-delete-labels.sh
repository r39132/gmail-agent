#!/usr/bin/env bash
#
# gmail-delete-labels.sh — Delete a Gmail label and all sublabels, with optional message deletion
#
# Usage: gmail-delete-labels.sh <label-name> [--delete-messages] [account-email]
#
# This script performs a two-phase deletion:
# 1. Optional: Delete messages where the target label (or sublabels) is the ONLY user label
# 2. Delete the label(s) themselves using GAM
#
# Requirements:
# - gog CLI (for message operations)
# - GAM (Google Apps Manager) for label deletion
# - jq (for JSON parsing)
#
set -euo pipefail

usage() {
    echo "Usage: $0 <label-name> [--delete-messages] [account-email]" >&2
    echo "" >&2
    echo "  label-name         The Gmail label to delete (e.g., 'Professional/OldCompany')" >&2
    echo "  --delete-messages  Also delete messages with only this label (single-label messages)" >&2
    echo "  account            Gmail address (defaults to \$GMAIL_ACCOUNT)" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 'Professional/OldCompany'                    # Delete label only" >&2
    echo "  $0 'Professional/OldCompany' --delete-messages  # Delete label + single-label messages" >&2
    exit 1
}

# --- Parse arguments (check for --help first) ---
for arg in "$@"; do
    case "$arg" in
        --help|-h) usage ;;
    esac
done

# --- Check dependencies ---
if ! command -v gog &>/dev/null; then
    echo "Error: gog CLI not found. Install via: npm install -g gogcli" >&2
    exit 1
fi

if ! command -v gam &>/dev/null; then
    echo "Error: GAM (Google Apps Manager) not found." >&2
    echo "Install via: https://github.com/GAM-team/GAM" >&2
    echo "Or use Homebrew (if available): brew install gam" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq not found. Install via: brew install jq" >&2
    exit 1
fi

# --- Parse arguments ---
LABEL=""
DELETE_MESSAGES=false
ACCOUNT="${GMAIL_ACCOUNT:-}"

for arg in "$@"; do
    case "$arg" in
        --delete-messages) DELETE_MESSAGES=true ;;
        --help|-h) ;; # already handled above
        *)
            if [[ -z "$LABEL" ]]; then
                LABEL="$arg"
            elif [[ -z "$ACCOUNT" ]]; then
                ACCOUNT="$arg"
            fi
            ;;
    esac
done

if [[ -z "$LABEL" ]]; then
    echo "Error: No label specified." >&2
    usage
fi

if [[ -z "$ACCOUNT" ]]; then
    echo "Error: No Gmail account specified. Set GMAIL_ACCOUNT or pass as argument." >&2
    exit 1
fi

# --- System labels to ignore when determining "single-label" ---
SYSTEM_LABELS="INBOX|SENT|DRAFT|TRASH|SPAM|CHAT|STARRED|IMPORTANT|UNREAD|YELLOW_STAR|CATEGORY_PERSONAL|CATEGORY_SOCIAL|CATEGORY_PROMOTIONS|CATEGORY_UPDATES|CATEGORY_FORUMS"

echo "=== Gmail Label Deletion ==="
echo "Label: ${LABEL}"
echo "Account: ${ACCOUNT}"
echo "Delete messages: ${DELETE_MESSAGES}"
echo ""

# --- Step 1: Find all matching labels (target + sublabels) ---
echo "[1/3] Finding matching labels..."

all_labels=$(gog gmail labels list --account "$ACCOUNT" --plain 2>/dev/null \
    | tail -n +2 \
    | cut -f2)

matching_labels=()
while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    # Match exact label or sublabels (label/*)
    if [[ "$name" == "$LABEL" || "$name" == "$LABEL/"* ]]; then
        matching_labels+=("$name")
    fi
done <<< "$all_labels"

if [[ ${#matching_labels[@]} -eq 0 ]]; then
    echo "No labels found matching '${LABEL}' or '${LABEL}/*'"
    exit 0
fi

echo "Found ${#matching_labels[@]} label(s):"
for lbl in "${matching_labels[@]}"; do
    echo "  - ${lbl}"
done
echo ""

# --- Step 2: Optionally delete single-label messages ---
if [[ "$DELETE_MESSAGES" == true ]]; then
    echo "[2/3] Identifying and deleting single-label messages..."

    total_deleted=0

    for lbl in "${matching_labels[@]}"; do
        echo "  Processing label: ${lbl}"

        # Search for all messages with this label
        messages=$(gog gmail messages search "label:\"${lbl}\"" \
            --account "$ACCOUNT" \
            --max 500 \
            --json 2>/dev/null || echo "[]")

        if [[ "$messages" == "[]" ]] || [[ -z "$messages" ]]; then
            echo "    No messages found"
            continue
        fi

        # Process each message
        count=0
        while IFS= read -r msg_id; do
            [[ -z "$msg_id" ]] && continue

            # Get full message details to check all labels
            msg_data=$(gog gmail get "$msg_id" \
                --account "$ACCOUNT" \
                --format metadata \
                --json 2>/dev/null || echo "{}")

            # Extract all labels for this message
            msg_labels=$(echo "$msg_data" | jq -r '.payload.headers[] | select(.name == "X-Gmail-Labels") | .value' 2>/dev/null || echo "")

            if [[ -z "$msg_labels" ]]; then
                # Fallback: get labels from labelIds field
                msg_labels=$(echo "$msg_data" | jq -r '.labelIds[]?' 2>/dev/null | tr '\n' ',' || echo "")
            fi

            # Count non-system user labels
            user_label_count=0
            IFS=',' read -ra label_array <<< "$msg_labels"
            for label in "${label_array[@]}"; do
                label=$(echo "$label" | xargs) # trim whitespace
                [[ -z "$label" ]] && continue

                # Skip system labels
                if echo "$label" | grep -qE "^(${SYSTEM_LABELS})$"; then
                    continue
                fi

                # This is a user label
                ((user_label_count++))
            done

            # If this message has only ONE user label (our target label), delete it
            if [[ $user_label_count -eq 1 ]]; then
                gog gmail trash "$msg_id" --account "$ACCOUNT" &>/dev/null
                ((count++))
                ((total_deleted++))
            fi
        done < <(echo "$messages" | jq -r '.[].id' 2>/dev/null)

        if [[ $count -gt 0 ]]; then
            echo "    Deleted $count single-label message(s)"
        fi
    done

    echo ""
    echo "Total messages deleted: $total_deleted"
    echo ""
else
    echo "[2/3] Skipping message deletion (--delete-messages not specified)"
    echo ""
fi

# --- Step 3: Delete the labels using GAM ---
echo "[3/3] Deleting labels using GAM..."

deleted_count=0
for lbl in "${matching_labels[@]}"; do
    echo "  Deleting: ${lbl}"

    # Use GAM to delete the label
    if gam user "$ACCOUNT" delete label "$lbl" 2>&1 | grep -qi "deleted\|removed\|success"; then
        ((deleted_count++))
    else
        echo "    Warning: Failed to delete '${lbl}'" >&2
    fi
done

echo ""
echo "=== Summary ==="
echo "Labels deleted: $deleted_count/${#matching_labels[@]}"
if [[ "$DELETE_MESSAGES" == true ]]; then
    echo "Messages deleted: $total_deleted"
fi
echo ""
echo "Done!"
