#!/usr/bin/env python3
"""
Fetch skill - Downloads URLs and saves cleaned content to files.
Returns file path for agent to read as needed.
"""

import sys
import os
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse
import re

try:
    import requests
except ImportError:
    print("Error: requests library not installed. Run: pip install requests", file=sys.stderr)
    sys.exit(1)

# Realistic browser user agent
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/122.0.0.0 Safari/537.36"
)

# Cache directory (in workspace)
CACHE_DIR = Path.home() / "workspace" / ".fetch_cache"


def html_to_markdown(html: str) -> str:
    """Convert HTML to clean markdown text."""
    from html.parser import HTMLParser

    class MarkdownConverter(HTMLParser):
        def __init__(self):
            super().__init__()
            self.output = []
            self.skip_tags = {'script', 'style', 'noscript', 'nav', 'footer', 'header', 'aside'}
            self.skip_depth = 0
            self.in_pre = False
            self.in_code = False
            self.list_stack = []
            self.current_link = None

        def handle_starttag(self, tag, attrs):
            tag = tag.lower()
            attrs_dict = dict(attrs)

            if tag in self.skip_tags:
                self.skip_depth += 1
                return
            if self.skip_depth > 0:
                return

            if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
                level = int(tag[1])
                self.output.append('\n\n' + '#' * level + ' ')
            elif tag == 'p':
                self.output.append('\n\n')
            elif tag == 'br':
                self.output.append('\n')
            elif tag == 'strong' or tag == 'b':
                self.output.append('**')
            elif tag == 'em' or tag == 'i':
                self.output.append('*')
            elif tag == 'code':
                self.in_code = True
                if not self.in_pre:
                    self.output.append('`')
            elif tag == 'pre':
                self.in_pre = True
                self.output.append('\n\n```\n')
            elif tag == 'a':
                self.current_link = attrs_dict.get('href', '')
            elif tag == 'ul':
                self.list_stack.append('ul')
                self.output.append('\n')
            elif tag == 'ol':
                self.list_stack.append(1)
                self.output.append('\n')
            elif tag == 'li':
                indent = '  ' * (len(self.list_stack) - 1)
                if self.list_stack and self.list_stack[-1] == 'ul':
                    self.output.append(f'\n{indent}- ')
                elif self.list_stack and isinstance(self.list_stack[-1], int):
                    num = self.list_stack[-1]
                    self.output.append(f'\n{indent}{num}. ')
                    self.list_stack[-1] = num + 1
            elif tag == 'blockquote':
                self.output.append('\n\n> ')
            elif tag == 'hr':
                self.output.append('\n\n---\n\n')
            elif tag == 'img':
                alt = attrs_dict.get('alt', '')
                src = attrs_dict.get('src', '')
                if src:
                    self.output.append(f'![{alt}]({src})')
            elif tag == 'table':
                self.output.append('\n\n')
            elif tag == 'tr':
                self.output.append('\n|')
            elif tag in ('th', 'td'):
                self.output.append(' ')
            elif tag == 'div':
                self.output.append('\n')

        def handle_endtag(self, tag):
            tag = tag.lower()

            if tag in self.skip_tags:
                self.skip_depth = max(0, self.skip_depth - 1)
                return
            if self.skip_depth > 0:
                return

            if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
                self.output.append('\n')
            elif tag == 'strong' or tag == 'b':
                self.output.append('**')
            elif tag == 'em' or tag == 'i':
                self.output.append('*')
            elif tag == 'code':
                self.in_code = False
                if not self.in_pre:
                    self.output.append('`')
            elif tag == 'pre':
                self.in_pre = False
                self.output.append('\n```\n')
            elif tag == 'a' and self.current_link:
                self.output.append(f']({self.current_link})')
                self.current_link = None
            elif tag in ('ul', 'ol') and self.list_stack:
                self.list_stack.pop()
                self.output.append('\n')
            elif tag in ('th', 'td'):
                self.output.append(' |')
            elif tag == 'p':
                self.output.append('\n')

        def handle_data(self, data):
            if self.skip_depth > 0:
                return

            text = data
            if not self.in_pre:
                # Normalize whitespace outside pre blocks
                text = re.sub(r'\s+', ' ', text)

            if self.current_link and not text.strip():
                return

            if self.current_link:
                self.output.append('[' + text)
            else:
                self.output.append(text)

        def get_markdown(self) -> str:
            result = ''.join(self.output)
            # Clean up excessive newlines
            result = re.sub(r'\n{3,}', '\n\n', result)
            # Clean up spaces around newlines
            result = re.sub(r' *\n *', '\n', result)
            return result.strip()

    try:
        converter = MarkdownConverter()
        converter.feed(html)
        return converter.get_markdown()
    except Exception as e:
        # Fallback: strip tags
        text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL | re.IGNORECASE)
        text = re.sub(r'<[^>]+>', ' ', text)
        text = re.sub(r'\s+', ' ', text)
        return text.strip()


def fetch_url(url: str) -> dict:
    """Fetch URL and return content with metadata."""

    headers = {
        'User-Agent': USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
    }

    try:
        response = requests.get(
            url,
            headers=headers,
            timeout=30,
            allow_redirects=True
        )
        response.raise_for_status()

        content_type = response.headers.get('Content-Type', '').lower()

        # Determine if HTML or plain content
        if 'text/html' in content_type:
            content = html_to_markdown(response.text)
            detected_type = 'html'
        elif 'application/json' in content_type:
            # Pretty print JSON
            try:
                data = response.json()
                content = json.dumps(data, indent=2)
            except:
                content = response.text
            detected_type = 'json'
        else:
            content = response.text
            detected_type = 'text'

        return {
            'success': True,
            'url': url,
            'final_url': response.url,
            'content': content,
            'content_type': content_type,
            'detected_type': detected_type,
            'status_code': response.status_code,
            'size_bytes': len(content.encode('utf-8')),
        }

    except requests.exceptions.Timeout:
        return {'success': False, 'error': 'Request timed out (30s limit)'}
    except requests.exceptions.TooManyRedirects:
        return {'success': False, 'error': 'Too many redirects'}
    except requests.exceptions.RequestException as e:
        return {'success': False, 'error': str(e)}


def generate_filename(url: str) -> str:
    """Generate a short filename from URL hash."""
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:12]
    return f"{url_hash}.md"


def save_content(url: str, result: dict) -> Path:
    """Save fetched content to cache file with metadata."""

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    filename = generate_filename(url)
    filepath = CACHE_DIR / filename

    # Build markdown file with frontmatter
    now = datetime.now(timezone.utc).isoformat()

    frontmatter = f"""---
url: {url}
final_url: {result.get('final_url', url)}
fetched_at: {now}
content_type: {result.get('content_type', 'unknown')}
detected_type: {result.get('detected_type', 'unknown')}
size_bytes: {result.get('size_bytes', 0)}
status_code: {result.get('status_code', 0)}
---

"""

    full_content = frontmatter + result['content']
    filepath.write_text(full_content, encoding='utf-8')

    return filepath


def estimate_tokens(text: str) -> int:
    """Rough token estimate (1 token ≈ 4 chars for English)."""
    return len(text) // 4


def main():
    if len(sys.argv) < 2:
        print("Usage: fetch.py <url>")
        print("\nFetches URL content, saves to file, returns path for agent to read.")
        print("\nExample:")
        print("  fetch.py https://docs.python.org/3/library/json.html")
        sys.exit(1)

    url = sys.argv[1]

    # Validate URL
    parsed = urlparse(url)
    if not parsed.scheme in ('http', 'https'):
        print(f"Error: Invalid URL scheme. Must be http:// or https://", file=sys.stderr)
        sys.exit(1)

    # Fetch
    print(f"Fetching: {url}", file=sys.stderr)
    result = fetch_url(url)

    if not result['success']:
        print(f"Error: {result['error']}", file=sys.stderr)
        sys.exit(1)

    # Save to file
    filepath = save_content(url, result)

    # Output summary for agent
    size = result['size_bytes']
    tokens = estimate_tokens(result['content'])

    print(f"""
Fetched successfully!

Source: {url}
File: {filepath}
Size: {size:,} chars (~{tokens:,} tokens)
Type: {result['detected_type']}

Use the Read tool to access content. For large files, use offset/limit to paginate.
""".strip())


if __name__ == '__main__':
    main()
