---
name: browser
description: Browser automation using Playwright CLI. Use for web scraping, screenshots, UI testing.
---

# Browser Automation with Playwright CLI

Use `playwright-cli` directly for browser automation. **No wrapper script needed.**

## Quick Start

```bash
# 1. Open browser and navigate to URL
playwright-cli open "https://example.com"

# 2. Get page content with element references
playwright-cli browser_snapshot

# 3. Interact with elements (use refs from snapshot like e21, e35)
playwright-cli click e21
playwright-cli type e35 "search text"

# 4. Take screenshot (saves to file - safe for LLMs)
playwright-cli screenshot --filename="$HOME/workspace/screenshot.png"

# 5. Navigate to another page
playwright-cli goto "https://another-url.com"

# 6. Close browser when done
playwright-cli close
```

## When to Use This vs /websearch

- **Need search results?** → Use `/websearch` (faster, no browser needed)
- **Need to interact with a page?** → Use `/browser` (this skill)
- **Need page content?** → Use `/fetch`

## Common Workflow Example

```bash
# Screenshot a webpage
playwright-cli open "https://example.com/dashboard"
playwright-cli screenshot --filename="$HOME/workspace/dashboard.png"
playwright-cli close

# Fill a form
playwright-cli open "https://example.com/login"
playwright-cli browser_snapshot                    # Find form element refs
playwright-cli type e12 "username"                 # Type in username field
playwright-cli type e15 "password"                 # Type in password field
playwright-cli click e21                           # Click submit button
playwright-cli close
```

## Core Commands

| Command | Description |
|---------|-------------|
| `open [url]` | Start browser, optionally navigate to URL |
| `goto <url>` | Navigate to URL (browser must be open) |
| `browser_snapshot` | Get page content as YAML with element refs |
| `click <ref>` | Click element by reference (e.g., e21) |
| `type <ref> <text>` | Type text in element |
| `screenshot --filename=<path>` | Save screenshot to file |
| `close` | Close browser session |

## Important Notes

1. **Always `open` first** - Other commands need an open browser
2. **Use `browser_snapshot`** to see element references (e21, e35, etc.)
3. **Screenshots save to files** - Safe for LLMs, no binary in response
4. **Remember to `close`** when done to free resources

## Full Help

Run `playwright-cli --help` for all available commands and options.

## Element References

The `browser_snapshot` command returns YAML with element references:

```yaml
- button "Search" [ref=e21]
- textbox "Search" [ref=e35]
- link "Images" [ref=e42]
```

Use these refs with `click` and `type` commands.

## Analyzing Screenshots

After taking a screenshot, use the `/vision` skill to analyze it:

```bash
playwright-cli screenshot --filename="$HOME/workspace/page.png"
~/.claude/skills/vision/vision.sh analyze "$HOME/workspace/page.png" "describe what you see"
```
