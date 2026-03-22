#!/bin/bash
# Generates docs/report-index.json from last 7 days of reports
# Also copies reports into docs/ so they're accessible from GitHub Pages

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
DOCS_DIR="$SCRIPT_DIR/docs"

mkdir -p "$DOCS_DIR"

# Copy all reports into docs/
cp "$REPORTS_DIR"/*.md "$DOCS_DIR/" 2>/dev/null || true

# Generate index JSON by parsing each report (last 7 days only)
python3 -c "
import re, json, os, glob
from datetime import datetime, timedelta

reports_dir = '$REPORTS_DIR'
report_files = sorted(glob.glob(os.path.join(reports_dir, 'report-*.md')), reverse=True)

# Only index reports from the last 7 days
cutoff = (datetime.now() - timedelta(days=7)).strftime('%Y-%m-%d')
report_files = [f for f in report_files if os.path.basename(f).replace('report-','').replace('.md','') >= cutoff]

def extract_findings(content, section_name):
    \"\"\"Extract findings from action-category sections within a module section.\"\"\"
    items = []
    # Try new format: findings under ## New Coverage Required or #### action categories
    # First try flat list under ## New Coverage Required
    ncr_match = re.search(r'## New Coverage Required\s*\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
    if ncr_match:
        for line in ncr_match.group(1).strip().split('\n'):
            m = re.match(r'- \*\*\[(\w+)\]\s*\[(\w+)\]\s+(.+?)\*\*:\s*(.*)', line)
            if not m:
                m2 = re.match(r'- \*\*\[(\w+)\]\s*\[(\w+)\]\*\*\s+(.*?)(?:\s*[\u2014\u2013\-]+\s*)(.*)', line)
                if m2:
                    m = m2
                else:
                    m3 = re.match(r'- \*\*\[(\w+)\]\s*\[(\w+)\]\*\*\s+(.*)', line)
                    if m3:
                        full = m3.group(3)
                        source = ''
                        src_m = re.search(r'Source:\s*(https?://\S+)', full)
                        if src_m:
                            source = src_m.group(1)
                            full = full[:src_m.start()].strip().rstrip('.')
                        parts = re.split(r'\s*[\u2014\u2013]\s*|\.\s+', full, 1)
                        title = parts[0].strip()
                        desc = parts[1].strip() if len(parts) > 1 else ''
                        items.append({
                            'severity': m3.group(2),
                            'title': title,
                            'description': desc,
                            'source': source,
                            'module': m3.group(1).upper(),
                            'action': 'New Coverage Required'
                        })
                        continue
            if m:
                module = m.group(1).upper()
                severity = m.group(2).upper()
                title = m.group(3).strip()
                desc = m.group(4).strip() if m.lastindex >= 4 else ''
                source = ''
                src_match = re.search(r'Source:\s*(https?://\S+)', desc)
                if src_match:
                    source = src_match.group(1)
                    desc = desc[:src_match.start()].strip().rstrip('.')
                items.append({
                    'severity': severity,
                    'title': title,
                    'description': desc,
                    'source': source,
                    'module': module,
                    'action': 'New Coverage Required'
                })
        return items

    # Fallback: try action categories
    for action_header in ['Action Required', 'New Capabilities', 'Monitoring Updates']:
        pattern = r'####\s*' + action_header + r'\s*\n(.*?)(?=\n####|\n###|\n##|\Z)'
        match = re.search(pattern, content, re.DOTALL)
        if match:
            for line in match.group(1).strip().split('\n'):
                # Parse: - **[MODULE] [SEVERITY] Title**: Description. Source: URL
                # Also handle: - **[MODULE] [SEVERITY]** Title — Description. Source: URL
                m = re.match(r'- \*\*\[(\w+)\]\s*\[(\w+)\]\s+(.+?)\*\*:\s*(.*)', line)
                if not m:
                    # Alternate: - **[MODULE] [HIGH]** Title — desc. Source: URL
                    m2 = re.match(r'- \*\*\[(\w+)\]\s*\[(\w+)\]\*\*\s+(.*?)(?:\s*[\u2014\u2013\-]+\s*)(.*)', line)
                    if m2:
                        m = m2
                    else:
                        # Last resort: - **[MODULE] [HIGH]** Full sentence. Source: URL
                        m3 = re.match(r'- \*\*\[(\w+)\]\s*\[(\w+)\]\*\*\s+(.*)', line)
                        if m3:
                            full = m3.group(3)
                            source = ''
                            src_m = re.search(r'Source:\s*(https?://\S+)', full)
                            if src_m:
                                source = src_m.group(1)
                                full = full[:src_m.start()].strip().rstrip('.')
                            # Split on first period or dash for title/desc
                            parts = re.split(r'\s*[\u2014\u2013]\s*|\.\s+', full, 1)
                            title = parts[0].strip()
                            desc = parts[1].strip() if len(parts) > 1 else ''
                            items.append({
                                'severity': m3.group(2),
                                'title': title,
                                'description': desc,
                                'source': source,
                                'module': m3.group(1).upper(),
                                'action': action_header
                            })
                            continue
                if m:
                    module = m.group(1).upper()
                    severity = m.group(2).upper()
                    title = m.group(3).strip()
                    desc = m.group(4).strip()
                    source = ''
                    src_match = re.search(r'Source:\s*(https?://\S+)', desc)
                    if src_match:
                        source = src_match.group(1)
                        desc = desc[:src_match.start()].strip().rstrip('.')
                    items.append({
                        'severity': severity,
                        'title': title,
                        'description': desc,
                        'source': source,
                        'module': module,
                        'action': action_header
                    })

    # Fallback: try old format with ### AIDR / ### AISPM / ### AI Endpoint headers
    if not items:
        for mod_name, mod_key in [('AIDR', 'AIDR'), ('AISPM', 'AISPM'), ('AI Endpoint', 'ENDPOINT')]:
            pattern = r'### ' + mod_name + r'[^\n]*\n(.*?)(?=\n### |\n## |\Z)'
            match = re.search(pattern, content, re.DOTALL)
            if match:
                for line in match.group(1).strip().split('\n'):
                    m = re.match(r'- \*\*\[(\w+)\]\s*(.*?)\*\*:\s*(.*)', line)
                    if m:
                        desc = m.group(3).strip()
                        source = ''
                        src_match = re.search(r'Source:\s*(https?://\S+)', desc)
                        if src_match:
                            source = src_match.group(1)
                            desc = desc[:src_match.start()].strip().rstrip('.')
                        items.append({
                            'severity': m.group(1),
                            'title': m.group(2).strip(),
                            'description': desc,
                            'source': source,
                            'module': mod_key,
                            'action': 'Uncategorized'
                        })
    return items

# Load sources.json for tier info
sources_path = os.path.join('$SCRIPT_DIR', 'sources.json')
tiers = {}
if os.path.exists(sources_path):
    with open(sources_path) as sf:
        src_data = json.load(sf)
        for p in src_data.get('platforms', []):
            tiers[p['name']] = p.get('tier', 'primary')

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

            # Improved status detection
            has_bullets = any(l.strip().startswith('- ') and 'no change' not in l.lower() for l in lines[1:])
            body_lower = body.lower()

            if 'initial scan' in body_lower or 'baseline' in body_lower:
                status = 'initial'
            elif 'unable to determine' in body_lower or 'error' in body_lower or '404' in body_lower:
                status = 'error'
            elif has_bullets:
                status = 'changed'
            else:
                status = 'stable'

            details = []
            for l in lines[1:]:
                l = l.strip()
                if l.startswith('- ') and 'no change' not in l.lower():
                    details.append(l[2:])

            platforms.append({
                'name': name,
                'status': status,
                'details': details[:6],
                'tier': tiers.get(name, 'primary')
            })

    # Extract all findings
    all_findings = extract_findings(content, '')

    # Deduplicate findings by title
    seen_titles = set()
    unique_findings = []
    for f in all_findings:
        key = f.get('title', '').strip().lower()
        if key and key not in seen_titles:
            seen_titles.add(key)
            unique_findings.append(f)

    # Get file modification time as scan timestamp
    mtime = os.path.getmtime(report_file)
    scan_time = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M')

    index.append({
        'date': date,
        'scan_time': scan_time,
        'file': filename,
        'platforms': platforms,
        'findings': unique_findings
    })

with open('$DOCS_DIR/report-index.json', 'w') as f:
    json.dump(index, f, indent=2)

total = sum(len(r.get('findings', [])) for r in index)
print(f'Index built: {len(index)} reports (last 7 days), {total} security findings')
"
