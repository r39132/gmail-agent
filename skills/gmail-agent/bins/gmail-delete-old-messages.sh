#!/usr/bin/env bash
#
# gmail-delete-old-messages.sh — Delete messages older than a specific date from a label
#
# Usage: gmail-delete-old-messages.sh <label-name> <date> [account-email]
#
# This script deletes all messages older than the specified date from a label
# and all its sublabels. Date format: MM/DD/YYYY
#
# Requirements:
# - gog CLI (for listing labels)
# - python3 with google-auth and google-api-python-client
#
set -euo pipefail

usage() {
    echo "Usage: $0 <label-name> <date> [account-email]" >&2
    echo "" >&2
    echo "  label-name    The Gmail label (e.g., 'Personal/Archive')" >&2
    echo "  date          Delete messages older than this date (MM/DD/YYYY)" >&2
    echo "  account       Gmail address (defaults to \$GMAIL_ACCOUNT)" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 'Personal/Archive' '01/01/2020'        # Delete messages before Jan 1, 2020" >&2
    echo "  $0 'Personal/Old' '12/31/2019' user@gmail.com" >&2
    exit 1
}

# --- Parse arguments ---
for arg in "$@"; do
    case "$arg" in
        --help|-h) usage ;;
    esac
done

if ! command -v gog &>/dev/null; then
    echo "Error: gog CLI not found. Install via: npm install -g gogcli" >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found." >&2
    exit 1
fi

if ! python3 -c "from google.oauth2.credentials import Credentials; from googleapiclient.discovery import build" 2>/dev/null; then
    echo "Error: Missing Python packages. Install via:" >&2
    echo "  pip install google-auth google-api-python-client" >&2
    exit 1
fi

LABEL=""
DATE=""
ACCOUNT="${GMAIL_ACCOUNT:-}"

for arg in "$@"; do
    case "$arg" in
        --help|-h) ;; # already handled
        *)
            if [[ -z "$LABEL" ]]; then
                LABEL="$arg"
            elif [[ -z "$DATE" ]]; then
                DATE="$arg"
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

if [[ -z "$DATE" ]]; then
    echo "Error: No date specified." >&2
    usage
fi

if [[ -z "$ACCOUNT" ]]; then
    echo "Error: No Gmail account specified. Set GMAIL_ACCOUNT or pass as argument." >&2
    exit 1
fi

# Validate date format
if ! [[ "$DATE" =~ ^[0-9]{2}/[0-9]{2}/[0-9]{4}$ ]]; then
    echo "Error: Invalid date format. Use MM/DD/YYYY" >&2
    exit 1
fi

echo "=== Delete Old Messages ==="
echo "Label: ${LABEL}"
echo "Delete messages before: ${DATE}"
echo "Account: ${ACCOUNT}"
echo ""

# --- Step 1: Find matching labels ---
echo "[1/4] Finding matching labels..."

all_labels_tsv=$(gog gmail labels list --account "$ACCOUNT" --plain 2>/dev/null | tail -n +2)

matching_labels=()
declare -A label_ids

while IFS=$'\t' read -r label_id label_name label_type; do
    [[ -z "$label_name" ]] && continue
    if [[ "$label_name" == "$LABEL" || "$label_name" == "$LABEL/"* ]]; then
        matching_labels+=("$label_name")
        label_ids["$label_name"]="$label_id"
    fi
done <<< "$all_labels_tsv"

if [[ ${#matching_labels[@]} -eq 0 ]]; then
    echo "No labels found matching '${LABEL}' or '${LABEL}/*'"
    exit 0
fi

echo "Found ${#matching_labels[@]} label(s):"
for lbl in "${matching_labels[@]}"; do
    echo "  - ${lbl}"
done
echo ""

# --- Step 2: Convert date to Gmail search format (YYYY/MM/DD) ---
echo "[2/4] Converting date format..."
IFS='/' read -r month day year <<< "$DATE"
GMAIL_DATE="${year}/${month}/${day}"
echo "Gmail search format: before:${GMAIL_DATE}"
echo ""

# --- Step 3: Search and delete old messages ---
echo "[3/4] Finding and trashing old messages..."

# Export gog token
TOKEN_FILE=$(mktemp /tmp/gog_token_XXXXXX.json)
trap "rm -f '$TOKEN_FILE'" EXIT

gog auth tokens export "$ACCOUNT" --out "$TOKEN_FILE" 2>/dev/null

GOG_CREDS_DIR="${HOME}/Library/Application Support/gogcli"
if [[ ! -f "$GOG_CREDS_DIR/credentials.json" ]]; then
    GOG_CREDS_DIR="${HOME}/.config/gogcli"
fi

if [[ ! -f "$GOG_CREDS_DIR/credentials.json" ]]; then
    echo "Error: Cannot find gog credentials." >&2
    exit 1
fi

# Build search queries for each label
SEARCH_QUERIES="["
first=true
for lbl in "${matching_labels[@]}"; do
    if [[ "$first" == true ]]; then
        first=false
    else
        SEARCH_QUERIES+=","
    fi
    SEARCH_QUERIES+="{\"label\":\"${lbl}\",\"before\":\"${GMAIL_DATE}\"}"
done
SEARCH_QUERIES+="]"

# Run Python to search and delete
result=$(python3 - "$TOKEN_FILE" "$GOG_CREDS_DIR/credentials.json" "$SEARCH_QUERIES" << 'PYEOF'
import json, sys
from datetime import datetime

token_file = sys.argv[1]
creds_file = sys.argv[2]
queries_json = sys.argv[3]

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

with open(creds_file) as f:
    client = json.load(f)
with open(token_file) as f:
    token = json.load(f)

creds = Credentials(
    token=None,
    refresh_token=token["refresh_token"],
    token_uri="https://oauth2.googleapis.com/token",
    client_id=client["client_id"],
    client_secret=client["client_secret"],
)

service = build("gmail", "v1", credentials=creds)
queries = json.loads(queries_json)

all_msg_ids = set()
for query in queries:
    label = query["label"]
    before_date = query["before"]

    print(f"  Searching: {label} before {before_date}")

    # Search for messages
    search_query = f'label:"{label}" before:{before_date}'
    try:
        results = service.users().messages().list(
            userId="me",
            q=search_query,
            maxResults=500
        ).execute()

        messages = results.get("messages", [])
        for msg in messages:
            all_msg_ids.add(msg["id"])

        # Handle pagination
        while "nextPageToken" in results:
            results = service.users().messages().list(
                userId="me",
                q=search_query,
                maxResults=500,
                pageToken=results["nextPageToken"]
            ).execute()
            messages = results.get("messages", [])
            for msg in messages:
                all_msg_ids.add(msg["id"])

        print(f"    Found: {len(messages)} messages")
    except Exception as e:
        print(f"    Error searching: {e}")

print(f"\nTotal unique messages to trash: {len(all_msg_ids)}")

# Trash all messages
trashed = 0
failed = 0
for msg_id in all_msg_ids:
    try:
        service.users().messages().trash(userId="me", id=msg_id).execute()
        trashed += 1
        if trashed % 50 == 0:
            print(f"  Trashed {trashed}/{len(all_msg_ids)}...")
    except Exception as e:
        failed += 1

print(f"\nTRASHED={trashed}")
print(f"FAILED={failed}")
PYEOF
)

echo "$result"

# Parse counts
trashed_count=$(echo "$result" | grep "^TRASHED=" | cut -d= -f2)
failed_count=$(echo "$result" | grep "^FAILED=" | cut -d= -f2)

echo ""
echo "=== Summary ==="
echo "Messages trashed: ${trashed_count:-0}"
if [[ "${failed_count:-0}" -gt 0 ]]; then
    echo "Messages failed: $failed_count"
fi
echo ""

# --- Step 4: Empty trash if messages were trashed ---
if [[ "${trashed_count:-0}" -gt 0 ]]; then
    echo "[4/4] Emptying trash..."

    trash_emptied=0
    while true; do
        # Get trash message IDs
        ids=$(gog gmail messages search "in:trash" \
            --account "$ACCOUNT" \
            --max 500 \
            --plain 2>&1 \
            | tail -n +2 \
            | grep -vE '^(#|No results)' \
            | cut -f1 || true)

        if [[ -z "$ids" ]]; then
            break
        fi

        batch_count=0
        batch_ids=()

        while IFS= read -r id; do
            [[ -z "$id" ]] && continue
            batch_ids+=("$id")
            ((batch_count++))

            if [[ ${#batch_ids[@]} -ge 100 ]]; then
                gog gmail batch modify "${batch_ids[@]}" \
                    --account "$ACCOUNT" \
                    --remove="TRASH" \
                    --force &>/dev/null
                batch_ids=()
            fi
        done <<< "$ids"

        if [[ ${#batch_ids[@]} -gt 0 ]]; then
            gog gmail batch modify "${batch_ids[@]}" \
                --account "$ACCOUNT" \
                --remove="TRASH" \
                --force &>/dev/null
        fi

        trash_emptied=$((trash_emptied + batch_count))

        if [[ $batch_count -lt 500 ]]; then
            break
        fi
    done

    echo "Trash emptied: $trash_emptied messages permanently deleted"
    echo ""
fi

echo "Done!"
