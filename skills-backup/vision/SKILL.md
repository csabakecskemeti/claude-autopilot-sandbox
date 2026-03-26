---
name: vision
description: Analyze images using vision AI model. Use for UI screenshot verification, understanding downloaded images/assets, reading text from pictures (OCR), or any visual analysis task.
allowed-tools: Bash
---

# Vision Analysis Result

!`~/.claude/skills/vision/vision.sh $ARGUMENTS 2>&1`

---

## What Just Happened

The vision skill executed automatically with your arguments. Review the output above.

- **PASS** = UI/image matches expectations
- **FAIL** = Issues found, fix before proceeding

## Commands Reference

| Command | Usage |
|---------|-------|
| `/vision analyze <url_or_file> "<prompt>"` | Analyze image or webpage |
| `/vision verify <url_or_file> "<expected>"` | Verify UI matches description |
| `/vision ocr <url_or_file>` | Extract text from image |
| `/vision logs` | Show recent vision logs |

## Examples

```bash
/vision verify http://localhost:8000 "Should show a todo list with input field"
/vision analyze ./screenshot.png "What do you see?"
/vision ocr ./document.png
```

## Logs

All results saved to `~/workspace/.vision_logs/`
