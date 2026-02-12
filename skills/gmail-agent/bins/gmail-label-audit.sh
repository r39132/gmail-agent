#!/usr/bin/env bash
#
# gmail-label-audit.sh — Audit a Gmail label and its sublabels, then optionally clean up
#
# Usage: gmail-label-audit.sh <label-name> [--cleanup] [account-email]
#
# Without --cleanup: reports message counts per label/sublabel
# With --cleanup:    removes the target label(s) from ALL messages
#
set -euo pipefail

usage() {
    echo "Usage: $0 <label-name> [--cleanup] [account-email]" >&2
    echo "" >&2
    echo "  label-name    The Gmail label to audit (e.g., 'Professional/Companies')" >&2
    echo "  --cleanup     Remove labels from ALL messages with these labels" >&2
    echo "  account       Gmail address (defaults to \$GMAIL_ACCOUNT)" >&2
    exit 1
}

# --- Parse arguments ---
LABEL=""
CLEANUP=false
ACCOUNT="${GMAIL_ACCOUNT:-}"

for arg in "$@"; do
    case "$arg" in
        --cleanup) CLEANUP=true ;;
        --help|-h) usage ;;
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

# --- Step 1: Find all matching labels (target + sublabels) ---
echo "Auditing label: ${LABEL}"
echo "Account: ${ACCOUNT}"
echo ""

# Get all user labels, filter to target and sublabels
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

echo "Labels in scope (${#matching_labels[@]}):"
for lbl in "${matching_labels[@]}"; do
    echo "  - ${lbl}"
done
echo ""

# --- Step 2: For each label, count messages ---
total_messages=0

# Associative array for per-label counts
declare -A label_total

# Track unique message IDs across all labels (for deduplication)
declare -A msg_ids_seen

for lbl in "${matching_labels[@]}"; do
    # Search for messages with this label
    results=$(gog gmail messages search "label:${lbl}" \
        --account "$ACCOUNT" \
        --max 500 \
        --plain 2>/dev/null | tail -n +2 || true)

    label_count=0

    while IFS=$'\t' read -r id thread date from subject labels_str; do
        [[ -z "$id" ]] && continue
        label_count=$((label_count + 1))

        # Track unique messages for deduplication
        msg_ids_seen[$id]=1
    done <<< "$results"

    label_total[$lbl]=$label_count
    total_messages=$((total_messages + label_count))
done

# --- Step 3: Report ---
echo "=== Label Audit Report ==="
echo ""
printf "%-60s %8s\n" "LABEL" "MESSAGES"
printf "%-60s %8s\n" "-----" "--------"

for lbl in "${matching_labels[@]}"; do
    t="${label_total[$lbl]:-0}"
    printf "%-60s %8d\n" "$lbl" "$t"
done

echo ""
printf "%-60s %8d\n" "TOTAL (deduplicated)" "${#msg_ids_seen[@]}"
echo ""

# --- Step 4: Cleanup (if requested) ---
if [[ "$CLEANUP" == false ]]; then
    echo "Run with --cleanup to remove labels from ALL messages with these labels."
    exit 0
fi

unique_msg_count="${#msg_ids_seen[@]}"
if [[ $unique_msg_count -eq 0 ]]; then
    echo "No messages to clean up."
    exit 0
fi

echo "=== Cleaning Up ==="
echo "Removing labels from ${unique_msg_count} message(s)..."
echo ""

cleaned=0

for lbl in "${matching_labels[@]}"; do
    # Collect ALL message IDs for this label
    batch_ids=()

    results=$(gog gmail messages search "label:${lbl}" \
        --account "$ACCOUNT" \
        --max 500 \
        --plain 2>/dev/null | tail -n +2 || true)

    while IFS=$'\t' read -r id thread date from subject labels_str; do
        [[ -z "$id" ]] && continue
        batch_ids+=("$id")
    done <<< "$results"

    if [[ ${#batch_ids[@]} -eq 0 ]]; then
        continue
    fi

    echo "  ${lbl}: removing from ${#batch_ids[@]} messages..."

    # Process in batches of 100
    for ((i=0; i<${#batch_ids[@]}; i+=100)); do
        chunk=("${batch_ids[@]:i:100}")
        gog gmail batch modify "${chunk[@]}" \
            --account "$ACCOUNT" \
            --remove "$lbl" \
            --force 2>/dev/null || echo "    Warning: batch modify failed for some messages in ${lbl}"
    done

    cleaned=$((cleaned + ${#batch_ids[@]}))
done

echo ""
echo "=== Cleanup Complete ==="
echo "Cleaned: ${cleaned} messages (labels removed from ALL messages)"
