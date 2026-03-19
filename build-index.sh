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
python3 -c "
import re, json, os, glob

reports_dir = '$REPORTS_DIR'
report_files = sorted(glob.glob(os.path.join(reports_dir, 'report-*.md')), reverse=True)

index = []
for report_file in report_files:
    filename = os.path.basename(report_file)
    date = filename.replace('report-', '').replace('.md', '')

    with open(report_file, 'r') as f:
        content = f.read()

    # Extract platforms from ### sections under ## Platform Details
    platforms = []
    platform_section = re.search(r'## Platform Details\s*\n(.*?)(?=\n## [^#])', content, re.DOTALL)
    if platform_section:
        sections = re.split(r'###\s+', platform_section.group(1))
        for section in sections[1:]:
            lines = section.strip().split('\n')
            name = lines[0].strip()
            body = '\n'.join(lines[1:]).lower()

            if 'initial scan' in body or 'baseline' in body:
                status = 'initial'
            elif 'unable to determine' in body:
                status = 'error'
            elif 'changes detected:** none' in body or 'changes detected:** no' in body:
                status = 'stable'
            elif 'changes detected:** yes' in body:
                status = 'changed'
            elif 'no change' in body or 'no major' in body:
                status = 'stable'
            else:
                status = 'stable'

            platforms.append({'name': name, 'status': status})

    # Extract AIDR items
    aidr_items = []
    aidr_match = re.search(r'### AIDR.*?\n(.*?)(?=\n### AISPM|\n## )', content, re.DOTALL)
    if aidr_match:
        for line in aidr_match.group(1).strip().split('\n'):
            m = re.match(r'- \*\*\[(\w+)\]\s*(.*?)\*\*:\s*(.*)', line)
            if m:
                aidr_items.append({
                    'severity': m.group(1),
                    'title': m.group(2).strip(),
                    'description': m.group(3).strip(),
                    'module': 'AIDR'
                })

    # Extract AISPM items
    aispm_items = []
    aispm_match = re.search(r'### AISPM.*?\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
    if aispm_match:
        for line in aispm_match.group(1).strip().split('\n'):
            m = re.match(r'- \*\*\[(\w+)\]\s*(.*?)\*\*:\s*(.*)', line)
            if m:
                aispm_items.append({
                    'severity': m.group(1),
                    'title': m.group(2).strip(),
                    'description': m.group(3).strip(),
                    'module': 'AISPM'
                })

    # Extract key highlights
    highlights = []
    hl_match = re.search(r'## Key Highlights\s*\n(.*?)(?=\n## )', content, re.DOTALL)
    if hl_match:
        for line in hl_match.group(1).strip().split('\n'):
            line = line.strip()
            if line.startswith('- '):
                highlights.append(line[2:])

    index.append({
        'date': date,
        'file': filename,
        'platforms': platforms,
        'aidr': aidr_items,
        'aispm': aispm_items,
        'highlights': highlights
    })

with open('$DOCS_DIR/report-index.json', 'w') as f:
    json.dump(index, f, indent=2)

print(f'Index built: {len(index)} reports, {sum(len(r[\"aidr\"]) + len(r[\"aispm\"]) for r in index)} security items')
"

