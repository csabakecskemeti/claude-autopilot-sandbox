#!/usr/bin/env python3
"""
Web Search Skill - Free, no API key required
Uses DuckDuckGo with Playwright fallback
"""

import sys
import os

def search_duckduckgo(query: str, max_results: int = 10) -> bool:
    """Search using duckduckgo-search library (primary method)."""
    try:
        from duckduckgo_search import DDGS

        print(f"Searching DuckDuckGo for: {query}\n")
        print("=" * 60)

        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))

            if not results:
                print("No results found.")
                return False

            for i, r in enumerate(results, 1):
                print(f"\n## {i}. {r.get('title', 'No title')}")
                print(f"**URL:** {r.get('href', 'No URL')}")
                print(f"{r.get('body', 'No description')}")

            print("\n" + "=" * 60)
            print(f"Found {len(results)} results.")
            return True

    except ImportError:
        print("ERROR: duckduckgo-search not installed.", file=sys.stderr)
        print("Install with: pip install duckduckgo-search", file=sys.stderr)
        return False
    except Exception as e:
        print(f"ERROR: DuckDuckGo search failed: {e}", file=sys.stderr)
        return False


def print_fallback_instructions():
    """Print instructions for Playwright fallback."""
    print("""
FALLBACK: Use Playwright for manual search:

```bash
playwright-cli open "https://duckduckgo.com"
playwright-cli browser_snapshot
playwright-cli type e12 "your search query"
playwright-cli click e15
playwright-cli browser_snapshot
playwright-cli close
```
""")


def main():
    if len(sys.argv) < 2:
        print("Usage: search.py <query> [max_results]")
        print("\nExamples:")
        print('  search.py "Python web scraping"')
        print('  search.py "Claude AI news" 5')
        sys.exit(1)

    query = sys.argv[1]
    max_results = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    success = search_duckduckgo(query, max_results)

    if not success:
        print_fallback_instructions()
        sys.exit(1)


if __name__ == "__main__":
    main()
