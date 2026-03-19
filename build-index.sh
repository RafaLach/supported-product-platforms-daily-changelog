#!/bin/bash
# Generates docs/report-index.json from all reports in reports/
# Also copies reports into docs/ so they're accessible from GitHub Pages

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
DOCS_DIR="$SCRIPT_DIR/docs"

mkdir -p "$DOCS_DIR"

# Copy all reports into docs/
cp "$REPORTS_DIR"/*.md "$DOCS_DIR/" 2>/dev/null || true

# Generate index JSON by parsing each report
echo "[" > "$DOCS_DIR/report-index.json"

first=true
for report_file in $(ls -r "$REPORTS_DIR"/report-*.md 2>/dev/null); do
    filename=$(basename "$report_file")
    # Extract date from filename: report-YYYY-MM-DD.md
    date=$(echo "$filename" | sed 's/report-\(.*\)\.md/\1/')

    # Parse platform statuses from the report
    platforms="[]"
    if [ -f "$report_file" ]; then
        platforms=$(python3 -c "
import re, json, sys

with open('$report_file', 'r') as f:
    content = f.read()

platforms = []
# Match ### Platform Name followed by **Changes detected:** or **Status:**
sections = re.split(r'###\s+', content)
for section in sections[1:]:
    lines = section.strip().split('\n')
    name = lines[0].strip()

    # Skip non-platform sections like 'Errors', 'Configuration', 'Zenity Security'
    skip_keywords = ['Error', 'Configuration', 'Zenity Security', 'Key Highlight']
    if any(k.lower() in name.lower() for k in skip_keywords):
        continue

    body = '\n'.join(lines[1:]).lower()
    if 'initial scan' in body or 'initial —' in body or 'baseline' in body:
        status = 'initial'
    elif 'unable to determine' in body or 'failed' in body or 'http 403' in body or 'http 404' in body:
        if 'changes detected' in body or 'change' in body:
            status = 'error'
        else:
            status = 'error'
    elif 'no change' in body or 'changes detected:** none' in body or 'no major' in body:
        status = 'stable'
    elif 'change' in body:
        status = 'changed'
    else:
        status = 'stable'

    platforms.append({'name': name, 'status': status})

print(json.dumps(platforms))
" 2>/dev/null || echo "[]")
    fi

    if [ "$first" = true ]; then
        first=false
    else
        echo "," >> "$DOCS_DIR/report-index.json"
    fi

    cat >> "$DOCS_DIR/report-index.json" <<ENTRY
  {"date": "$date", "file": "$filename", "platforms": $platforms}
ENTRY

done

echo "]" >> "$DOCS_DIR/report-index.json"

echo "Index built: $(cat "$DOCS_DIR/report-index.json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo '?') reports"
