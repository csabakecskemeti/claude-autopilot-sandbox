---
name: websearch
description: Free web search using DuckDuckGo. No API key required. Falls back to Playwright if needed.
---

# Web Search

Free, independent web search. No API keys needed.

## Usage

```bash
~/.claude/skills/websearch/websearch.py "your search query"
~/.claude/skills/websearch/websearch.py "your search query" 5   # limit to 5 results
```

## Example

```bash
~/.claude/skills/websearch/websearch.py "Python async tutorial"
```

Output:
```
Searching DuckDuckGo for: Python async tutorial
============================================================

## 1. Async IO in Python: A Complete Walkthrough
**URL:** https://realpython.com/async-io-python/
This tutorial covers async IO in Python with examples...

## 2. Python Asyncio Tutorial
**URL:** https://docs.python.org/3/library/asyncio.html
...

============================================================
Found 10 results.
```

## Fallback: Playwright

If DuckDuckGo search fails (rate limit, network issues), use Playwright:

```bash
playwright-cli open "https://duckduckgo.com"
playwright-cli browser_snapshot
playwright-cli type e12 "your search query"
playwright-cli click e15
playwright-cli browser_snapshot
playwright-cli close
```

## Features

- **Free** - No API keys, no costs
- **Private** - Uses DuckDuckGo
- **Reliable** - Python library, not scraping
- **Fallback** - Playwright if primary fails
