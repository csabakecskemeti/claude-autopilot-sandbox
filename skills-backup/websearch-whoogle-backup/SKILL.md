---
name: websearch
description: Search the web using the local Whoogle search service. Use for ANY web search - the native WebSearch tool does not work with local LLMs. Use when asked to search online, look up information, research topics, or find current information.
allowed-tools: Bash
---

# Web Search

Search the web using the local Whoogle instance.

**IMPORTANT:** Always use this skill for web searches. The native WebSearch tool does not work with local LLMs.

## Usage

```bash
~/.claude/skills/websearch/local_websearch.sh "<search query>"
```

## Examples

```bash
# General search
~/.claude/skills/websearch/local_websearch.sh "Python asyncio tutorial"

# Technical documentation
~/.claude/skills/websearch/local_websearch.sh "Docker compose networking guide"

# Current information
~/.claude/skills/websearch/local_websearch.sh "latest news about AI"
```

## Response

Returns JSON results from Whoogle (configured via `WHOOGLE_URL` environment variable).

Parse the JSON and present relevant results to the user in a readable format with:
- Title
- URL
- Brief description
