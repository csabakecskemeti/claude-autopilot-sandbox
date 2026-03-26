---
name: fetch
description: Fetch content from a URL and save it to a file. Use this when you need to retrieve web content (documentation, API responses, articles). Content is saved to ~/workspace/.fetch_cache/ and you can read it with the Read tool. For complex research across multiple sources, use the web-researcher subagent instead.
version: 1.0.0
---

# Fetch Skill

Downloads web content and saves it to a local file for you to read.

## Usage

```bash
~/.claude/skills/fetch/fetch.py <url>
```

## What It Does

1. Fetches the URL with a realistic browser user-agent
2. Converts HTML to clean Markdown (or formats JSON)
3. Saves to `~/workspace/.fetch_cache/<hash>.md` with metadata
4. Returns the file path for you to read

## Output File Format

```markdown
---
url: https://example.com/docs
final_url: https://example.com/docs  # after redirects
fetched_at: 2026-03-21T14:32:00+00:00
content_type: text/html
detected_type: html
size_bytes: 45230
status_code: 200
---

# Page Title

Content in markdown format...
```

## Examples

### Fetch documentation
```bash
~/.claude/skills/fetch/fetch.py https://docs.python.org/3/library/json.html
# Returns: File path, then use Read tool to access
```

### Fetch API schema
```bash
~/.claude/skills/fetch/fetch.py https://api.example.com/openapi.json
```

## Reading the Content

After fetching, use the Read tool to access the content:

```
# Read entire file
Read: ~/workspace/.fetch_cache/a1b2c3d4e5f6.md

# Read first 100 lines only (for large files)
Read: ~/workspace/.fetch_cache/a1b2c3d4e5f6.md (limit: 100)

# Paginate through large files
Read: ~/workspace/.fetch_cache/a1b2c3d4e5f6.md (offset: 100, limit: 100)
```

## When to Use This vs web-researcher

| Use `/fetch` when... | Use `web-researcher` subagent when... |
|---------------------|--------------------------------------|
| You need one specific URL | You need to research a topic |
| Quick lookup | Multiple sources needed |
| You know exactly what page has the info | You need to search first |
| Small to medium content | Synthesis across sources |

## Cache Location

All fetched content is stored in:
```
~/workspace/.fetch_cache/
├── a1b2c3d4e5f6.md
├── f7e8d9c0b1a2.md
└── ...
```

Files persist across sessions. Delete manually if needed.
