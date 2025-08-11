# Claude Conversation Extractor - Project Context

## 🚀 PRODUCTION EXTRACTOR - FULLY WORKING VERSION

**Last Updated**: August 11, 2025 at 6:03 PM EDT

### WORKING PRODUCTION EXTRACTOR ✅
- **File**: `zig-out/bin/extractor` and `extractor` (root)
- **Size**: 504KB (516,096 bytes)
- **Date**: Aug 11 15:02 EDT
- **Version**: 2.0.0 (SQLite-only with protocol mode)
- **SHA256**: `4c7d3e0d525f081db2017e902b9267afd915752906e709352493a30642134e62`
- **Backup**: `~/Desktop/extractor_working_aug11_v2.0.0_504KB`
- **Deployed to app**: Aug 11 15:02 EDT
- **Git Commit**: `f73dcad` on branch `fix-message-display-issue`

### THIS IS THE ONE VERSION
**NO MULTIPLE VERSIONS** - This is the single, unified implementation

### 🚨 BREAK GLASS - Version Verification & Recovery

#### Quick Verification
Run `./VERIFY_WORKING_EXTRACTOR.sh` to check if you have the correct version.

#### Emergency Restore Methods
1. **From Desktop Backup** (Fastest):
   ```bash
   cp ~/Desktop/extractor_working_aug11_v2.0.0_504KB extractor
   cp ~/Desktop/extractor_working_aug11_v2.0.0_504KB zig-out/bin/extractor
   cp ~/Desktop/extractor_working_aug11_v2.0.0_504KB claude_ui/macos/extractor
   ```

2. **From Git**:
   ```bash
   git checkout f73dcad -- extractor.zig
   zig build -Doptimize=ReleaseFast
   ```

3. **From TAR Backup**:
   ```bash
   cd ~/Desktop
   tar -xzf COMPLETE_WORKING_PROJECT_*.tar.gz
   ```

#### Red Flags - WRONG Versions
- Binary size is 2.4MB or larger
- Binary size is exactly 573KB
- SHA256 starts with "5b323bd..." (old version)
- Error: "cannot rollback - no transaction is active"
- Search returns IDs like "093fc10c-b732..." instead of "session_12"
- Messages show "0 messages" when clicking sessions

See `EMERGENCY_RESTORE_INSTRUCTIONS.md` for complete details.

### What's Working in This Version
- ✅ **Messages display correctly** when clicking session cards
- ✅ **Search works perfectly** - returns proper session_N format
- ✅ **Snippets highlight** in search results
- ✅ **No transaction errors** - fixed rollback issue
- ✅ **Protocol mode** for Flutter UI communication
- ✅ **Database**: 49,380 messages indexed from 30 conversations
- ✅ **CLI search**: Works independently
- ✅ **Export formats**: Markdown, JSON, HTML all working

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
