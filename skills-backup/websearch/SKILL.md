---
name: websearch
description: Search the web using browser automation
---

# Web Search

Use `playwright-cli` directly for web searches.

## Quick Search

```bash
# 1. Open browser and go to Google
playwright-cli open "https://google.com"

# 2. Get page snapshot (find search box ref)
playwright-cli browser_snapshot
# Look for: textbox "Search" [ref=e35]

# 3. Type your query
playwright-cli type e35 "your search query"

# 4. Click search button
playwright-cli click e21

# 5. Get results
playwright-cli browser_snapshot
```

## Reading a Page

```bash
# Click on a search result link
playwright-cli click e42

# Get page content
playwright-cli browser_snapshot

# Navigate to a different URL
playwright-cli goto "https://example.com"
```

## Taking Screenshots

```bash
# Save screenshot to file
playwright-cli screenshot --filename="$HOME/workspace/search-results.png"

# Analyze with vision
~/.claude/skills/vision/vision.sh analyze "$HOME/workspace/search-results.png" "describe"
```

## Close Browser

```bash
# Always close when done
playwright-cli close
```

## Tips

- **Always `open` first** - Other commands need an open browser
- `browser_snapshot` returns YAML with element refs (e21, e35, etc.)
- Use those refs with `click` and `type` commands
- Screenshots save to files (no binary in response)
- Run `playwright-cli --help` for all commands
- For complex research, use the `web-researcher` subagent
