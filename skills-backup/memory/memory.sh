#!/usr/bin/env bash
# Persistent memory with vector search using ChromaDB

set -e

MEMORY_DIR="$HOME/workspace/.memory"
mkdir -p "$MEMORY_DIR"

OPERATION="$1"
shift || true

# Parse arguments
CONTENT=""
CATEGORY="general"
QUERY=""
MEMORY_ID=""
CONFIRM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --confirm)
            CONFIRM="yes"
            shift
            ;;
        *)
            if [[ -z "$CONTENT" ]]; then
                CONTENT="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$OPERATION" ]]; then
    echo "Usage: $0 <operation> [content] [--category name]"
    echo ""
    echo "Operations:"
    echo "  store <text> [--category name]  - Store a memory"
    echo "  recall <query> [--category]     - Search memories"
    echo "  list [--category name]          - List memories"
    echo "  compact                         - Summarize old memories"
    echo "  delete <id>                     - Delete a memory"
    echo "  clear --confirm                 - Clear all memories"
    exit 1
fi

# Python script for vector operations
python3 << EOF
import os
import sys
import json
import hashlib
from datetime import datetime
from pathlib import Path

MEMORY_DIR = Path("$MEMORY_DIR")
MEMORY_FILE = MEMORY_DIR / "memories.json"

def load_memories():
    if MEMORY_FILE.exists():
        return json.loads(MEMORY_FILE.read_text())
    return []

def save_memories(memories):
    MEMORY_FILE.write_text(json.dumps(memories, indent=2))

def generate_id(content):
    return hashlib.md5(f"{content}{datetime.now().isoformat()}".encode()).hexdigest()[:8]

operation = "$OPERATION"
content = """$CONTENT"""
category = "$CATEGORY"
confirm = "$CONFIRM"

memories = load_memories()

if operation == "store":
    if not content:
        print("Error: No content provided")
        sys.exit(1)

    memory = {
        "id": generate_id(content),
        "content": content,
        "category": category,
        "timestamp": datetime.now().isoformat(),
    }
    memories.append(memory)
    save_memories(memories)
    print(f"Stored memory [{memory['id']}] in category '{category}'")

elif operation == "recall":
    query = content.lower() if content else ""

    # Simple keyword search (would use embeddings with full ChromaDB)
    results = []
    for m in memories:
        if category != "general" and m.get("category") != category:
            continue
        # Simple relevance scoring
        score = 0
        for word in query.split():
            if word in m["content"].lower():
                score += 1
        if score > 0 or not query:
            results.append((score, m))

    results.sort(key=lambda x: (-x[0], x[1]["timestamp"]), reverse=True)

    if results:
        print("Recalled memories:")
        for score, m in results[:5]:
            print(f"\n[{m['id']}] ({m['category']}) - {m['timestamp'][:10]}")
            print(f"  {m['content']}")
    else:
        print("No matching memories found")

elif operation == "list":
    filtered = [m for m in memories if category == "general" or m.get("category") == category]

    if filtered:
        print(f"Memories ({len(filtered)} total):")
        for m in filtered[-10:]:  # Show last 10
            preview = m["content"][:60] + "..." if len(m["content"]) > 60 else m["content"]
            print(f"  [{m['id']}] ({m['category']}) {preview}")
    else:
        print("No memories stored")

elif operation == "compact":
    # Group by category and keep summaries
    by_category = {}
    for m in memories:
        cat = m.get("category", "general")
        if cat not in by_category:
            by_category[cat] = []
        by_category[cat].append(m)

    print("Memory summary by category:")
    for cat, mems in by_category.items():
        print(f"\n{cat} ({len(mems)} memories):")
        for m in mems[-3:]:  # Show last 3 per category
            preview = m["content"][:50] + "..." if len(m["content"]) > 50 else m["content"]
            print(f"  - {preview}")

    print("\nTo truly compact, manually review and delete old entries with 'delete <id>'")

elif operation == "delete":
    if not content:
        print("Error: No memory ID provided")
        sys.exit(1)

    original_count = len(memories)
    memories = [m for m in memories if m["id"] != content]

    if len(memories) < original_count:
        save_memories(memories)
        print(f"Deleted memory {content}")
    else:
        print(f"Memory not found: {content}")

elif operation == "clear":
    if confirm != "yes":
        print("Error: Use --confirm to clear all memories")
        sys.exit(1)

    save_memories([])
    print("All memories cleared")

else:
    print(f"Unknown operation: {operation}")
    sys.exit(1)
EOF
