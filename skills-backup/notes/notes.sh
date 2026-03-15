#!/usr/bin/env bash
# Persistent notes system

set -e

NOTES_DIR="$HOME/workspace/.notes"
mkdir -p "$NOTES_DIR"

OPERATION="$1"
NOTE_NAME="$2"
CONTENT="$3"

if [[ -z "$OPERATION" ]]; then
    echo "Usage: $0 <operation> [note-name] [content]"
    echo "Operations:"
    echo "  add <name> <content>    - Create or replace note"
    echo "  append <name> <content> - Append to note"
    echo "  read <name>             - Read note"
    echo "  list                    - List all notes"
    echo "  search <term>           - Search notes"
    echo "  delete <name>           - Delete note"
    exit 1
fi

note_file() {
    echo "$NOTES_DIR/${1}.md"
}

case "$OPERATION" in
    add)
        if [[ -z "$NOTE_NAME" ]] || [[ -z "$CONTENT" ]]; then
            echo "Usage: $0 add <name> <content>"
            exit 1
        fi
        FILE=$(note_file "$NOTE_NAME")
        cat > "$FILE" << EOF
# $NOTE_NAME
Created: $(date -Iseconds)
Modified: $(date -Iseconds)

---

$CONTENT
EOF
        echo "Note created: $NOTE_NAME"
        ;;
    append)
        if [[ -z "$NOTE_NAME" ]] || [[ -z "$CONTENT" ]]; then
            echo "Usage: $0 append <name> <content>"
            exit 1
        fi
        FILE=$(note_file "$NOTE_NAME")
        if [[ ! -f "$FILE" ]]; then
            echo "Note not found: $NOTE_NAME"
            exit 1
        fi
        # Update modified timestamp
        sed -i "s/^Modified:.*/Modified: $(date -Iseconds)/" "$FILE"
        echo "" >> "$FILE"
        echo "$CONTENT" >> "$FILE"
        echo "Note updated: $NOTE_NAME"
        ;;
    read)
        if [[ -z "$NOTE_NAME" ]]; then
            echo "Usage: $0 read <name>"
            exit 1
        fi
        FILE=$(note_file "$NOTE_NAME")
        if [[ ! -f "$FILE" ]]; then
            echo "Note not found: $NOTE_NAME"
            exit 1
        fi
        cat "$FILE"
        ;;
    list)
        echo "Notes:"
        for f in "$NOTES_DIR"/*.md 2>/dev/null; do
            [[ -f "$f" ]] || continue
            name=$(basename "$f" .md)
            modified=$(grep "^Modified:" "$f" | cut -d' ' -f2-)
            echo "  - $name (modified: $modified)"
        done
        ;;
    search)
        if [[ -z "$NOTE_NAME" ]]; then
            echo "Usage: $0 search <term>"
            exit 1
        fi
        echo "Searching for: $NOTE_NAME"
        grep -l -i "$NOTE_NAME" "$NOTES_DIR"/*.md 2>/dev/null | while read -r f; do
            echo ""
            echo "=== $(basename "$f" .md) ==="
            grep -i --color=never -C 1 "$NOTE_NAME" "$f"
        done
        ;;
    delete)
        if [[ -z "$NOTE_NAME" ]]; then
            echo "Usage: $0 delete <name>"
            exit 1
        fi
        FILE=$(note_file "$NOTE_NAME")
        if [[ ! -f "$FILE" ]]; then
            echo "Note not found: $NOTE_NAME"
            exit 1
        fi
        rm "$FILE"
        echo "Note deleted: $NOTE_NAME"
        ;;
    *)
        echo "Unknown operation: $OPERATION"
        exit 1
        ;;
esac
