---
name: websearch
description: Search the web using Playwright browser automation
---

# Web Search

Use these Playwright MCP tools for web search:

| Tool | Use for |
|------|---------|
| `mcp__playwright__browser_navigate` | Go to a URL |
| `mcp__playwright__browser_snapshot` | Get page content (use this!) |
| `mcp__playwright__browser_type` | Type text, submit forms |
| `mcp__playwright__browser_click` | Click elements |

**WARNING: Do NOT use `browser_screenshot`** - it returns binary image data that will crash the session.

**To capture screenshots**, save to file then use /vision:
```javascript
// Use browser_runjs:
await page.screenshot({ path: '/home/claude/workspace/screenshot.png' });
```
Then: `~/.claude/skills/vision/vision.sh analyze /home/claude/workspace/screenshot.png "describe"`

## Quick Search

1. `mcp__playwright__browser_navigate` → `https://www.google.com`
2. `mcp__playwright__browser_type` → element: "Search", text: "your query", submit: true
3. `mcp__playwright__browser_snapshot` → read results
