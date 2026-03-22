#!/bin/bash
# Zenity Platform Monitor — Daily documentation change tracker
# Runs via launchd daily, invokes Claude Code to check for platform changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/monitor-$(date +%Y-%m-%d).log"
PROMPT_FILE="$SCRIPT_DIR/monitor-prompt.md"
INTERACTIVE=false

# Detect if running interactively (terminal attached)
if [ -t 1 ]; then
  INTERACTIVE=true
fi

echo "=== Platform Monitor Run: $(date) ===" >> "$LOG_FILE"

if $INTERACTIVE; then
  echo "🔍 Platform Monitor — scanning 19 sources..."
  echo ""
  # Run Claude and tee to log, showing progress lines in terminal
  claude -p "$(cat "$PROMPT_FILE")" \
    --allowedTools "WebFetch,WebSearch,Read,Write,Bash(curl:*),Bash(mkdir:*),Bash(bash:*),Bash(python*:*),Bash(git:*),Glob,Grep" \
    2>&1 | tee -a "$LOG_FILE" | while IFS= read -r line; do
      if [[ "$line" =~ \[PROGRESS\ ([0-9]+)/([0-9]+)\]\ (.*) ]]; then
        current="${BASH_REMATCH[1]}"
        total="${BASH_REMATCH[2]}"
        desc="${BASH_REMATCH[3]}"
        pct=$((current * 100 / total))
        filled=$((pct / 5))
        empty=$((20 - filled))
        bar=$(printf '█%.0s' $(seq 1 $filled 2>/dev/null) ; printf '░%.0s' $(seq 1 $empty 2>/dev/null))
        printf "\r  [%s] %3d%% (%d/%d) %s\033[K" "$bar" "$pct" "$current" "$total" "$desc"
      fi
    done
  echo ""
  EXIT_CODE=${PIPESTATUS[0]}
else
  # Non-interactive (launchd): just log
  claude -p "$(cat "$PROMPT_FILE")" \
    --allowedTools "WebFetch,WebSearch,Read,Write,Bash(curl:*),Bash(mkdir:*),Bash(bash:*),Bash(python*:*),Bash(git:*),Glob,Grep" \
    >> "$LOG_FILE" 2>&1
  EXIT_CODE=$?
fi

if [ $EXIT_CODE -eq 0 ]; then
  echo "=== Run completed successfully ===" >> "$LOG_FILE"
  $INTERACTIVE && echo "✅ Scan complete — report saved to reports/report-$(date +%Y-%m-%d).md"
else
  echo "=== Run failed with exit code $EXIT_CODE ===" >> "$LOG_FILE"
  $INTERACTIVE && echo "❌ Scan failed (exit code $EXIT_CODE). Check $LOG_FILE"
fi

# Keep only last 30 days of logs
find "$SCRIPT_DIR/logs" -name "monitor-*.log" -mtime +30 -delete 2>/dev/null || true

exit $EXIT_CODE
