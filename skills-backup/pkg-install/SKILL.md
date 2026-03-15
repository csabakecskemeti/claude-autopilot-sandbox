---
name: pkg-install
description: Install software packages at runtime in the Docker container. Use when a required tool or library is missing, or when asked to install packages.
allowed-tools: Bash
---

# Package Installer

Install additional software packages at runtime.

## Usage

### Install apt packages
```bash
~/.claude/skills/pkg-install/install.sh apt postgresql-client redis-tools
```

### Install Python packages
```bash
~/.claude/skills/pkg-install/install.sh pip pandas numpy matplotlib
```

### Install Node.js packages
```bash
~/.claude/skills/pkg-install/install.sh npm axios cheerio
```

### Check if installed
```bash
~/.claude/skills/pkg-install/install.sh check python3
~/.claude/skills/pkg-install/install.sh check pip:pandas
~/.claude/skills/pkg-install/install.sh check npm:axios
```

### List installed
```bash
~/.claude/skills/pkg-install/install.sh list pip
```

## Common Packages

**Data analysis:**
```bash
~/.claude/skills/pkg-install/install.sh pip pandas numpy scipy matplotlib
```

**Web scraping:**
```bash
~/.claude/skills/pkg-install/install.sh pip beautifulsoup4 requests lxml
```

**Database clients:**
```bash
~/.claude/skills/pkg-install/install.sh apt postgresql-client
~/.claude/skills/pkg-install/install.sh pip psycopg2-binary
```

Note: Packages persist only for current container session.
