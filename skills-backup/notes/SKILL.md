---
name: notes
description: Persistent note-taking across sessions. Use when asked to save notes, remember something, create reminders, or store information for later.
allowed-tools: Bash
---

# Notes

Create, read, and manage persistent notes stored in the workspace.

## Usage

### Create/update a note
```bash
~/.claude/skills/notes/notes.sh add "meeting-notes" "Met with team about Q2 roadmap"
```

### Append to a note
```bash
~/.claude/skills/notes/notes.sh append "meeting-notes" "Follow-up: send summary"
```

### Read a note
```bash
~/.claude/skills/notes/notes.sh read "meeting-notes"
```

### List all notes
```bash
~/.claude/skills/notes/notes.sh list
```

### Search notes
```bash
~/.claude/skills/notes/notes.sh search "roadmap"
```

### Delete a note
```bash
~/.claude/skills/notes/notes.sh delete "meeting-notes"
```

## Storage

Notes are stored as markdown files in `~/workspace/.notes/` with timestamps.
Use lowercase names with hyphens (e.g., `project-ideas`, `meeting-notes`).
