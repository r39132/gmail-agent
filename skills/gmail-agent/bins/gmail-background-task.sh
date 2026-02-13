#!/usr/bin/env bash
#
# gmail-background-task.sh — Run Gmail tasks in background with WhatsApp progress updates
#
# Usage: gmail-background-task.sh <task-name> <command> [args...]
#
# The task + monitor are fully daemonized (survive agent timeout).
# The script returns immediately after launching.
#
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Error: Missing arguments." >&2
    echo "Usage: $0 <task-name> <command> [args...]" >&2
    exit 1
fi

TASK_NAME="$1"
shift
COMMAND="$@"

ACCOUNT="${GMAIL_ACCOUNT:-}"
NOTIFY_TARGET="${WHATSAPP_NOTIFY_TARGET:-}"
UPDATE_INTERVAL="${WHATSAPP_UPDATE_INTERVAL:-30}"

if [[ -z "$ACCOUNT" ]]; then
    echo "Error: GMAIL_ACCOUNT env var not set." >&2
    exit 1
fi

if [[ -z "$NOTIFY_TARGET" ]]; then
    echo "Error: WHATSAPP_NOTIFY_TARGET env var not set." >&2
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
JOB_ID="gmail-bg-${TIMESTAMP}"
LOG_FILE="/tmp/${JOB_ID}.log"
REGISTRY_DIR="${HOME}/.gmail-agent/jobs"
REGISTRY_FILE="${REGISTRY_DIR}/${JOB_ID}.json"

mkdir -p "$REGISTRY_DIR"

# Send initial notification (before daemonizing, so agent sees it)
openclaw message send \
    --channel whatsapp \
    --target "$NOTIFY_TARGET" \
    --message "📧 Gmail Agent: Starting task '$TASK_NAME'

Account: $ACCOUNT
Started: $(date '+%Y-%m-%d %H:%M:%S')

Running in background... Updates every ${UPDATE_INTERVAL}s" \
    >/dev/null 2>&1 || true

# Echo job info for the agent
echo "Background task '$TASK_NAME' launched (job: $JOB_ID)"
echo "Log: $LOG_FILE"

# Daemonize: fork the entire task + monitor into a fully detached process
# Uses nohup + subshell + disown to survive agent/parent process death
nohup bash -c '
TASK_NAME="'"$TASK_NAME"'"
COMMAND="'"$COMMAND"'"
ACCOUNT="'"$ACCOUNT"'"
NOTIFY_TARGET="'"$NOTIFY_TARGET"'"
UPDATE_INTERVAL="'"$UPDATE_INTERVAL"'"
JOB_ID="'"$JOB_ID"'"
LOG_FILE="'"$LOG_FILE"'"
REGISTRY_FILE="'"$REGISTRY_FILE"'"

get_duration() {
    local elapsed=$(( $(date +%s) - $1 ))
    if [[ $elapsed -lt 60 ]]; then echo "${elapsed}s"
    elif [[ $elapsed -lt 3600 ]]; then echo "$((elapsed / 60))m $((elapsed % 60))s"
    else echo "$((elapsed / 3600))h $((elapsed % 3600 / 60))m"
    fi
}

send_notify() {
    openclaw message send --channel whatsapp --target "$NOTIFY_TARGET" --message "$1" >/dev/null 2>&1 || true
}

START_TIME=$(date +%s)
echo "Running: $COMMAND" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Run the actual task
eval "$COMMAND" >> "$LOG_FILE" 2>&1 &
TASK_PID=$!

# Register job
cat > "$REGISTRY_FILE" <<REOF
{
  "job_id": "$JOB_ID",
  "task_name": "$TASK_NAME",
  "account": "$ACCOUNT",
  "pid": $TASK_PID,
  "start_time": $START_TIME,
  "start_time_human": "$(date "+%Y-%m-%d %H:%M:%S")",
  "log_file": "$LOG_FILE",
  "status": "running",
  "notify_target": "$NOTIFY_TARGET"
}
REOF

# Monitor + send updates
UPDATE_COUNT=0
while kill -0 $TASK_PID 2>/dev/null; do
    sleep "$UPDATE_INTERVAL"
    if kill -0 $TASK_PID 2>/dev/null; then
        UPDATE_COUNT=$((UPDATE_COUNT + 1))
        send_notify "⏳ Gmail Agent: Task '"'"'$TASK_NAME'"'"' still running...

Duration: $(get_duration $START_TIME)
Updates: $UPDATE_COUNT"
    fi
done

wait $TASK_PID
EXIT_CODE=$?
DURATION=$(get_duration $START_TIME)

if [[ $EXIT_CODE -eq 0 ]]; then JOB_STATUS="completed"; else JOB_STATUS="failed"; fi

cat > "$REGISTRY_FILE" <<REOF
{
  "job_id": "$JOB_ID",
  "task_name": "$TASK_NAME",
  "account": "$ACCOUNT",
  "pid": $TASK_PID,
  "start_time": $START_TIME,
  "start_time_human": "$(date "+%Y-%m-%d %H:%M:%S")",
  "end_time": $(date +%s),
  "end_time_human": "$(date "+%Y-%m-%d %H:%M:%S")",
  "duration": "$DURATION",
  "log_file": "$LOG_FILE",
  "status": "$JOB_STATUS",
  "exit_code": $EXIT_CODE,
  "notify_target": "$NOTIFY_TARGET"
}
REOF

OUTPUT=$(tail -50 "$LOG_FILE")

if [[ $EXIT_CODE -eq 0 ]]; then
    send_notify "✅ Gmail Agent: Task '"'"'$TASK_NAME'"'"' completed successfully

Duration: $DURATION
Account: $ACCOUNT

━━━━━━━━━━━━━━━━━━━━━━━━━━
$OUTPUT"
else
    send_notify "❌ Gmail Agent: Task '"'"'$TASK_NAME'"'"' failed (exit $EXIT_CODE)

Duration: $DURATION
Account: $ACCOUNT

━━━━━━━━━━━━━━━━━━━━━━━━━━
$OUTPUT"
fi
' </dev/null >/dev/null 2>&1 &
disown

exit 0
