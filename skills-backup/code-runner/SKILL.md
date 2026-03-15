---
name: code-runner
description: Execute Python, JavaScript, or Bash code snippets and return output. Use when asked to run code, test snippets, or execute scripts.
allowed-tools: Bash
---

# Code Runner

Execute code snippets safely and return the output.

## Usage

Run the code execution script with the language and code:

```bash
~/.claude/skills/code-runner/run.sh <language> '<code>'
```

### Languages
- `python` or `py` - Python 3
- `javascript`, `js`, or `node` - Node.js
- `bash` or `sh` - Bash shell

### Examples

**Python:**
```bash
~/.claude/skills/code-runner/run.sh python '
import math
print(f"Pi is {math.pi}")
for i in range(5):
    print(f"Square of {i} is {i**2}")
'
```

**JavaScript:**
```bash
~/.claude/skills/code-runner/run.sh javascript '
const arr = [1, 2, 3, 4, 5];
console.log("Sum:", arr.reduce((a, b) => a + b, 0));
'
```

**Bash:**
```bash
~/.claude/skills/code-runner/run.sh bash 'echo "Current dir: $(pwd)"'
```

The script returns stdout, stderr, and exit code from the executed code.
