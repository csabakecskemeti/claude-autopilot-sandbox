---
name: api-tester
description: Test REST APIs with curl, format responses, save requests for replay. Use when testing APIs, debugging endpoints, or making HTTP requests.
allowed-tools: Bash
---

# API Tester

Test REST APIs with formatted output and request saving.

## Usage

### Make requests
```bash
~/.claude/skills/api-tester/api.sh <METHOD> <URL> [body] [-H 'Header: Value'] [--save name]
```

### Examples

**GET request:**
```bash
~/.claude/skills/api-tester/api.sh GET https://api.example.com/users
```

**POST with JSON:**
```bash
~/.claude/skills/api-tester/api.sh POST https://api.example.com/users '{"name":"John"}' -H "Authorization: Bearer token"
```

**Save for replay:**
```bash
~/.claude/skills/api-tester/api.sh GET https://api.example.com/users --save get-users
```

**Replay saved:**
```bash
~/.claude/skills/api-tester/api.sh --replay get-users
```

**List saved:**
```bash
~/.claude/skills/api-tester/api.sh --list
```

## Output

Shows HTTP status, headers, formatted JSON body, and timing.
