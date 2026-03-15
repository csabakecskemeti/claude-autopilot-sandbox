---
name: file-convert
description: Convert files between formats (PDF to text, Markdown to HTML, JSON to CSV, CSV to JSON). Use when asked to convert, transform, or export files to different formats.
allowed-tools: Bash
---

# File Converter

Convert files between common formats.

## Usage

```bash
~/.claude/skills/file-convert/convert.sh <operation> <input> [output]
```

## Operations

| Operation | Description |
|-----------|-------------|
| `pdf2txt` | PDF to plain text |
| `md2html` | Markdown to HTML |
| `json2csv` | JSON array to CSV |
| `csv2json` | CSV to JSON array |
| `html2txt` | HTML to plain text |

## Examples

```bash
# PDF to text
~/.claude/skills/file-convert/convert.sh pdf2txt document.pdf output.txt

# Markdown to HTML
~/.claude/skills/file-convert/convert.sh md2html README.md readme.html

# JSON to CSV
~/.claude/skills/file-convert/convert.sh json2csv data.json data.csv

# CSV to JSON
~/.claude/skills/file-convert/convert.sh csv2json users.csv users.json
```

If output is omitted, results are printed to stdout.
