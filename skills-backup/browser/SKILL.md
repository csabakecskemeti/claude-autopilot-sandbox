---
name: browser
description: "Browser automation with Python Playwright. Use for screenshots, web scraping, form filling, and visual verification of web apps."
---

# Browser Automation (Python Playwright)

Use Python Playwright for browser automation. Chromium is pre-installed.

## Quick Examples

### Take a Screenshot

```python
python3 -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1280, 'height': 720})
    page.goto('https://example.com', wait_until='networkidle', timeout=30000)
    page.screenshot(path='screenshot.png')
    browser.close()
    print('Screenshot saved to screenshot.png')
"
```

### Screenshot a Local App

```python
python3 -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1280, 'height': 720})
    page.goto('http://localhost:8000', wait_until='networkidle', timeout=30000)
    page.screenshot(path='app_screenshot.png', full_page=True)
    browser.close()
    print('Screenshot saved to app_screenshot.png')
"
```

### Extract Text from Page

```python
python3 -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto('https://example.com', wait_until='networkidle')
    text = page.inner_text('body')
    print(text)
    browser.close()
"
```

### Fill a Form

```python
python3 -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto('https://example.com/login')
    page.fill('input[name=\"username\"]', 'myuser')
    page.fill('input[name=\"password\"]', 'mypass')
    page.click('button[type=\"submit\"]')
    page.wait_for_load_state('networkidle')
    page.screenshot(path='after_login.png')
    browser.close()
"
```

### Click and Navigate

```python
python3 -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto('https://example.com')
    page.click('a:has-text(\"More information\")')
    page.wait_for_load_state('networkidle')
    print('Navigated to:', page.url)
    page.screenshot(path='after_click.png')
    browser.close()
"
```

## When to Use This vs Other Skills

| Need | Use |
|------|-----|
| Search the web | `/websearch` (faster, no browser) |
| Download a URL | `/fetch` |
| Interact with a page | `/browser` (this skill) |
| Take screenshots | `/browser` (this skill) |
| Analyze an image | `/vision` |

## Common Selectors

| Selector | Description |
|----------|-------------|
| `#id` | Element by ID |
| `.class` | Element by class |
| `button` | Element by tag |
| `[name="field"]` | Element by attribute |
| `a:has-text("Click")` | Link with text |
| `input[type="submit"]` | Input by type |
| `form >> input` | Nested element |

## Tips

- **Always use `headless=True`** - No physical display available
- **Set viewport size** for consistent screenshots: `viewport={'width': 1280, 'height': 720}`
- **Use `wait_until='networkidle'`** to wait for page to fully load
- **Use `full_page=True`** in screenshot() for long pages
- **Save screenshots to workspace** - They'll be accessible on the host

## Analyzing Screenshots

After taking a screenshot, use `/vision` to analyze it:

```bash
# Take screenshot
python3 -c "
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={'width': 1280, 'height': 720})
    page.goto('http://localhost:8000', wait_until='networkidle')
    page.screenshot(path='page.png')
    browser.close()
"

# Analyze with vision
~/.claude/skills/vision/vision.sh analyze page.png "describe what you see"
```

## Debugging

If browser fails to launch:
```bash
# Check Xvfb is running
pgrep Xvfb

# Check DISPLAY is set
echo $DISPLAY  # Should be :99

# Test Playwright
python3 -c "from playwright.sync_api import sync_playwright; print('OK')"
```
