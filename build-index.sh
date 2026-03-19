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

def extract_findings(content, header_pattern, stop_pattern):
    items = []
    match = re.search(header_pattern + r'.*?\n(.*?)(?=' + stop_pattern + r')', content, re.DOTALL)
    if match:
        for line in match.group(1).strip().split('\n'):
            m = re.match(r'- \*\*\[(\w+)\]\s*(.*?)\*\*:\s*(.*)', line)
            if m:
                desc = m.group(3).strip()
                # Extract source URL if present
                source = ''
                src_match = re.search(r'Source:\s*(https?://\S+)', desc)
                if src_match:
                    source = src_match.group(1)
                    desc = desc[:src_match.start()].strip().rstrip('.')
                items.append({
                    'severity': m.group(1),
                    'title': m.group(2).strip(),
                    'description': desc,
                    'source': source
                })
    return items

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
            body = '\n'.join(lines[1:])
            body_lower = body.lower()

            if 'initial scan' in body_lower or 'baseline' in body_lower:
                status = 'initial'
            elif 'unable to determine' in body_lower:
                status = 'error'
            elif 'changes detected:** none' in body_lower or 'changes detected:** no' in body_lower:
                status = 'stable'
            elif 'changes detected:** yes' in body_lower:
                status = 'changed'
            elif 'no change' in body_lower or 'no major' in body_lower:
                status = 'stable'
            else:
                status = 'stable'

            # Extract detail lines (skip first status line, get bullet points)
            details = []
            for l in lines[1:]:
                l = l.strip()
                if l.startswith('- ') and 'sources checked' not in l.lower():
                    details.append(l[2:])

            # Extract source URLs
            sources_checked = []
            for l in lines[1:]:
                if 'sources checked' in l.lower():
                    urls = re.findall(r'https?://\S+', l)
                    sources_checked = urls

            platforms.append({
                'name': name,
                'status': status,
                'details': details[:6],
                'sources': sources_checked
            })

    # Extract findings per module
    aidr_items = extract_findings(content, r'### AIDR', r'\n### AISPM|\n### AI Endpoint|\n## ')
    aispm_items = extract_findings(content, r'### AISPM', r'\n### AI Endpoint|\n## ')
    endpoint_items = extract_findings(content, r'### AI Endpoint', r'\n## ')

    # Extract key highlights
    highlights = []
    hl_match = re.search(r'## Key Highlights\s*\n(.*?)(?=\n## )', content, re.DOTALL)
    if hl_match:
        for line in hl_match.group(1).strip().split('\n'):
            line = line.strip()
            if line.startswith('- '):
                highlights.append(line[2:])

    # Get file modification time as scan timestamp
    mtime = os.path.getmtime(report_file)
    from datetime import datetime
    scan_time = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')

    index.append({
        'date': date,
        'scan_time': scan_time,
        'file': filename,
        'platforms': platforms,
        'aidr': aidr_items,
        'aispm': aispm_items,
        'endpoint': endpoint_items,
        'highlights': highlights
    })

with open('$DOCS_DIR/report-index.json', 'w') as f:
    json.dump(index, f, indent=2)

total = sum(len(r['aidr']) + len(r['aispm']) + len(r['endpoint']) for r in index)
print(f'Index built: {len(index)} reports, {total} security items')
"
