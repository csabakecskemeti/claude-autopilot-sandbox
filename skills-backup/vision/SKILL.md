---
name: vision
description: Analyze images using vision AI model. Use for UI screenshot verification, understanding downloaded images/assets, reading text from pictures (OCR), or any visual analysis task. Essential for testing web UIs - take screenshot then analyze to verify it looks correct. All requests are logged to ~/workspace/.vision_logs/ for review.
allowed-tools: Bash
---

# Vision

Analyze images using a vision-capable AI model. **You have vision capabilities!**

All requests are logged to `~/workspace/.vision_logs/` with both the image and response.

## Commands

| Command | Usage |
|---------|-------|
| `analyze` | Analyze any image or URL |
| `ocr` | Extract text from image |
| `verify` | Verify UI/image matches expected description |
| `logs` | Show recent vision logs |

## Input Types

The `<image_or_url>` parameter accepts:
- **Local file**: `./image.png`, `/path/to/screenshot.jpg`
- **Web URL**: `http://localhost:5000` (takes screenshot)
- **Image URL**: `https://example.com/photo.jpg` (downloads image)

## Usage

### Analyze an image or webpage
```bash
# Analyze local file
~/.claude/skills/vision/vision.sh analyze ./screenshot.png "What do you see?"

# Analyze webpage (takes screenshot automatically)
~/.claude/skills/vision/vision.sh analyze http://localhost:5000 "Describe this web page"

# Analyze image from URL
~/.claude/skills/vision/vision.sh analyze https://example.com/image.jpg "What is this?"
```

### OCR - Extract text
```bash
~/.claude/skills/vision/vision.sh ocr ./document.png
~/.claude/skills/vision/vision.sh ocr http://localhost:5000
```

### Verify UI matches expectations
```bash
~/.claude/skills/vision/vision.sh verify http://localhost:5000 \
    "Should show: a title, input form, and list of todos"

~/.claude/skills/vision/vision.sh verify ./screenshot.png \
    "Should have a login button and email field"
```

### View logs
```bash
~/.claude/skills/vision/vision.sh logs
```

## UI Testing Workflow

When building web UIs, use this workflow:

```bash
# 1. Start your app
python app.py &
sleep 2

# 2. Verify empty state
~/.claude/skills/vision/vision.sh verify http://localhost:5000 \
    "Should show empty todo list with add form"

# 3. Add test data
curl -X POST http://localhost:5000/add -d "title=Test item"

# 4. Verify with data
~/.claude/skills/vision/vision.sh verify http://localhost:5000 \
    "Should show 'Test item' in the todo list"

# 5. Check logs to review all screenshots
~/.claude/skills/vision/vision.sh logs
```

## Log Format

Each request creates two files in `~/workspace/.vision_logs/`:
- `YYYY-MM-DD_HH-MM-SS_<command>.png` - The image analyzed
- `YYYY-MM-DD_HH-MM-SS_<command>.md` - Request details and response

## When to Use Vision

1. **UI Testing** - Verify web app looks correct after changes
2. **Asset Verification** - Check downloaded images/sprites are correct
3. **OCR** - Read text from images, screenshots, documents
4. **Visual Debugging** - See what's actually displayed when something looks wrong
5. **Image Understanding** - Describe any image content
