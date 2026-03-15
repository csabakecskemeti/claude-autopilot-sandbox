#!/usr/bin/env bash
# File format converter

set -e

OPERATION="$1"
INPUT="$2"
OUTPUT="$3"

if [[ -z "$OPERATION" ]] || [[ -z "$INPUT" ]]; then
    echo "Usage: $0 <operation> <input> [output]"
    echo "Operations: pdf2txt, md2html, json2csv, csv2json, html2txt"
    exit 1
fi

case "$OPERATION" in
    pdf2txt)
        pdftotext "$INPUT" "${OUTPUT:--}"
        ;;
    md2html)
        python3 -c "
import markdown
import sys
with open('$INPUT', 'r') as f:
    html = markdown.markdown(f.read(), extensions=['tables', 'fenced_code'])
if '$OUTPUT':
    with open('$OUTPUT', 'w') as f:
        f.write(html)
else:
    print(html)
"
        ;;
    json2csv)
        python3 -c "
import json
import csv
import sys
with open('$INPUT', 'r') as f:
    data = json.load(f)
if not isinstance(data, list):
    data = [data]
if data:
    output = open('$OUTPUT', 'w') if '$OUTPUT' else sys.stdout
    writer = csv.DictWriter(output, fieldnames=data[0].keys())
    writer.writeheader()
    writer.writerows(data)
    if '$OUTPUT':
        output.close()
"
        ;;
    csv2json)
        python3 -c "
import json
import csv
import sys
with open('$INPUT', 'r') as f:
    reader = csv.DictReader(f)
    data = list(reader)
output = json.dumps(data, indent=2)
if '$OUTPUT':
    with open('$OUTPUT', 'w') as f:
        f.write(output)
else:
    print(output)
"
        ;;
    html2txt)
        python3 -c "
import html.parser
import sys

class HTMLTextExtractor(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
    def handle_data(self, data):
        self.text.append(data)
    def get_text(self):
        return ''.join(self.text)

with open('$INPUT', 'r') as f:
    parser = HTMLTextExtractor()
    parser.feed(f.read())
    text = parser.get_text()
if '$OUTPUT':
    with open('$OUTPUT', 'w') as f:
        f.write(text)
else:
    print(text)
"
        ;;
    *)
        echo "Unknown operation: $OPERATION"
        exit 1
        ;;
esac
