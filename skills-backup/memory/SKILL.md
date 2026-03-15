---
name: memory
description: Persistent memory with semantic search - store and recall information across sessions. Use when asked to remember something, recall previous discussions, or manage long-term memory. Also use proactively to store important discoveries and compact context.
allowed-tools: Bash
---

# Memory

Store and recall information across sessions using semantic search.

## Usage

### Store a memory
```bash
~/.claude/skills/memory/memory.sh store "The user prefers Python for backend work"
```

### Store with category
```bash
~/.claude/skills/memory/memory.sh store "API key in .env file" --category "project-config"
```

### Recall (semantic search)
```bash
~/.claude/skills/memory/memory.sh recall "what language does user prefer"
```

### List memories
```bash
~/.claude/skills/memory/memory.sh list
~/.claude/skills/memory/memory.sh list --category "project-config"
```

### Compact/review memories
```bash
~/.claude/skills/memory/memory.sh compact
```

### Delete a memory
```bash
~/.claude/skills/memory/memory.sh delete <memory-id>
```

## Context Compaction

When context gets long, use memory to preserve important information:
1. **Store key facts** before losing context
2. **Recall** relevant memories semantically when needed
3. **Compact** to review and merge related memories

## Categories

- `user-prefs` - User preferences
- `project-config` - Project settings
- `learned` - Discovered patterns
- `decisions` - Important decisions
- `todos` - Pending tasks

Storage: `~/workspace/.memory/`
