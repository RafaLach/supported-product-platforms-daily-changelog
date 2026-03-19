#!/bin/bash
# Zenity Platform Monitor — Daily documentation change tracker
# Runs via launchd daily, invokes Claude Code to check for platform changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/monitor-$(date +%Y-%m-%d).log"
PROMPT_FILE="$SCRIPT_DIR/monitor-prompt.md"

echo "=== Platform Monitor Run: $(date) ===" >> "$LOG_FILE"

# Run Claude Code with the monitoring prompt
claude -p "$(cat "$PROMPT_FILE")" \
  --allowedTools "WebFetch,Read,Write,Bash(curl:*),Bash(mkdir:*),Glob,Grep" \
  >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "=== Run completed successfully ===" >> "$LOG_FILE"
else
  echo "=== Run failed with exit code $EXIT_CODE ===" >> "$LOG_FILE"
fi

# Keep only last 30 days of logs
find "$SCRIPT_DIR/logs" -name "monitor-*.log" -mtime +30 -delete 2>/dev/null || true

exit $EXIT_CODE
