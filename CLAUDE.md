# Claude Conversation Extractor - Project Context

## 🚀 HIGH-PERFORMANCE EXTRACTOR - CURRENT PRODUCTION VERSION

**Last Updated**: August 11, 2025 at 1:08 PM EDT

### CURRENT PRODUCTION EXTRACTOR (HIGH-PERFORMANCE VERSION)
- **File**: `zig-out/bin/extractor`
- **Size**: 2.4M (2,516,992 bytes)
- **Date**: Aug 11 12:46
- **Version**: 2.0.0 (high-performance database version)
- **SHA256**: `5b323bd1a184be0329f8cb4526d9a868d4b984c1412dcbcfb79ebe3cabfd1a5a`
- **Deployed to app**: Aug 11 13:08 EDT

### Performance Metrics (PRODUCTION VERSION)
- **Search Speed**: ~1.5ms (7,000x faster than old version!)
- **Extract Speed**: 36ms total (100x faster than old version!)
- **Large file (530MB)**: Loads in 21ms (was 1,360ms)
- **Small file (2KB)**: Loads in 0.21ms (was ~100ms)
- **Database**: 49,378 messages indexed from 30 conversations

### What This Version Includes
- ✅ **Full SQLite database integration** - All messages stored in database
- ✅ **SQLite FTS5 full-text search** - Sub-millisecond search across all conversations
- ✅ **Instant message loading** - Database queries instead of file parsing
- ✅ **Incremental importing** - Only new messages are processed
- ✅ **BlockIndex tracking** - Efficient file position tracking
- ✅ **All export formats** - Markdown, JSON, HTML
- ✅ **Performance instrumentation** - Built-in timing metrics

### Database Schema (FULLY OPERATIONAL)
```sql
- source_files     - Tracks JSONL files and import status
- conversations    - Conversation metadata
- messages        - All message content (49,378 messages)
- messages_fts    - FTS5 full-text search index
```

### To Deploy to App
```bash
# Deploy the HIGH-PERFORMANCE extractor
cp zig-out/bin/extractor claude_ui/macos/extractor
cp zig-out/bin/extractor claude_ui/build/macos/Build/Products/Release/claude_ui.app/Contents/MacOS/
```

### OLD VERSION (DEPRECATED - DO NOT USE)
- **File**: `./extractor` (project root)
- **Size**: 502K
- **SHA256**: `9ae3e44f534671e7ed648dc4b4f83e64feccf0fc1e53c16bc2e065b477d80cab`
- **Issue**: Re-parses entire JSONL files on every click (5-10 second delays)

### Performance Comparison
| Operation | Old Extractor (502K) | New Extractor (2.4M) | Improvement |
|-----------|---------------------|---------------------|-------------|
| Search | 10+ seconds | 1.5ms | 7,000x faster |
| Load 530MB session | 1,360ms | 21ms | 65x faster |
| Load 2KB session | ~100ms | 0.21ms | 476x faster |
| Database queries | N/A (file parsing) | <1ms | Instant |

## Project Overview

This is a standalone tool that extracts Claude Code conversations from the
undocumented JSONL format in `~/.claude/projects/` and converts them to clean
markdown files. This is the FIRST publicly available solution for this problem.

## Key Goals

- **Professional Quality**: This project needs to be polished and professional -
  it's important for the developer's family
- **Easy Installation**: Setting up PyPI publishing so users can
  `pip install claude-conversation-extractor`
- **Wide Adoption**: Make this the go-to solution for Claude Code users

## Repository Structure

```text
claude-conversation-extractor/
├── extract_claude_logs.py    # Main script
├── setup.py                   # PyPI packaging configuration
├── README.md                  # Professional documentation
├── LICENSE                    # MIT License with disclaimer
├── CONTRIBUTING.md            # Contribution guidelines
├── requirements.txt           # No dependencies (stdlib only)
├── .gitignore                # Python gitignore
└── CLAUDE.md                 # This file
```

## Development Workflow

1. Always create feature branches for new work
2. Ensure code passes flake8 linting (max-line-length=100)
3. Test manually before committing
4. Update version numbers in setup.py for releases
5. Create detailed commit messages

## Current Status

- ✅ Core functionality complete and tested
- ✅ Professional documentation
- ✅ Published to GitHub:
  <https://github.com/ZeroSumQuant/claude-conversation-extractor>
- 🚧 Setting up PyPI publishing
- 📋 TODO: Add tests, CI/CD, screenshots

## PyPI Publishing Setup (In Progress)

1. Update setup.py with proper metadata
2. Create pyproject.toml for modern packaging
3. Set up GitHub Actions for automated publishing
4. Register on PyPI and get API token
5. Configure repository secrets

## Testing Commands

```bash
# Test extraction
python3 extract_claude_logs.py --list
python3 extract_claude_logs.py --extract 1

# Lint check
python3 -m flake8 extract_claude_logs.py --max-line-length=100

# Test installation
pip install -e .
```

## Important Notes

- No external dependencies (uses only Python stdlib)
- Supports Python 3.8+
- Cross-platform (Windows, macOS, Linux)
- Read-only access to Claude's conversation files
- Includes legal disclaimer for safety

## Marketing/Sharing Plan

- Anthropic Discord
- r/ClaudeAI subreddit
- Hacker News
- Twitter/X with relevant hashtags
- Create demo GIF showing the tool in action

## Version History

- 1.0.0 - Initial release (planned)
  - Core extraction functionality
  - Multiple output formats
  - Batch operations
