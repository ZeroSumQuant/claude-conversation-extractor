# Claude Conversation Extractor - Export Claude Code Conversations to Markdown | Save Chat History

> 🚀 **The ONLY tool to export Claude Code conversations**. Extract Claude chat history from ~/.claude/projects and backup your AI programming sessions.

## 🎮 Two Ways to Use

- **`claude-start`** - Interactive UI with ASCII art logo and menu-driven interface (recommended)
- **`claude-extract`** - Plain CLI for command-line operations and scripting

[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PyPI version](https://badge.fury.io/py/claude-conversation-extractor.svg)](https://badge.fury.io/py/claude-conversation-extractor)
[![Downloads](https://pepy.tech/badge/claude-conversation-extractor)](https://pepy.tech/project/claude-conversation-extractor)
[![GitHub stars](https://img.shields.io/github/stars/ZeroSumQuant/claude-conversation-extractor?style=social)](https://github.com/ZeroSumQuant/claude-conversation-extractor)
[![Export Claude Code](https://img.shields.io/badge/Export-Claude%20Code%20Conversations-blue)](https://github.com/ZeroSumQuant/claude-conversation-extractor)
[![Claude Code Logs](https://img.shields.io/badge/Backup-Claude%20Code%20Logs-green)](https://github.com/ZeroSumQuant/claude-conversation-extractor)

**Export Claude Code conversations with the #1 extraction tool.** Claude Code stores chats in ~/.claude/projects as JSONL files with no export button - this tool solves that.

🔥 **What users search for:** [Export Claude conversations](#how-to-export-claude-code-conversations) | [Claude Code logs location](#where-are-claude-code-logs-stored) | [Backup Claude sessions](#backup-all-claude-conversations) | [Claude JSONL to Markdown](#convert-claude-jsonl-to-markdown)

## 📸 How to Export Claude Code Conversations - Demo

![Export Claude Code conversations demo - Claude Conversation Extractor in action](https://raw.githubusercontent.com/ZeroSumQuant/claude-conversation-extractor/main/assets/demo.gif)

## 🎯 Can't Export Claude Code Conversations? We Solved It.

**Claude Code has no export button.** Your conversations are trapped in `~/.claude/projects/` as undocumented JSONL files. You need:
- ❌ **Export Claude Code conversations** before they're deleted
- ❌ **Backup Claude Code logs** for documentation or sharing
- ❌ **Convert Claude JSONL to Markdown** for readable archives

## ✅ Claude Conversation Extractor: The First Export Tool for Claude Code

This is the **ONLY tool that exports Claude Code conversations**:
- ✅ **Finds Claude Code logs** automatically in ~/.claude/projects
- ✅ **Extracts Claude conversations** to clean Markdown files
- ✅ **Backs up all Claude sessions** with one command
- ✅ **Works on Windows, macOS, Linux** - wherever Claude Code runs

## ✨ Features for Claude Code Users

- **📝 Claude JSONL to Markdown**: Clean export without terminal artifacts
- **📦 Bulk Export**: Extract all Claude Code conversations at once
- **🎯 Zero Config**: Just run `claude-extract` - we find everything automatically
- **🚀 No Dependencies**: Pure Python - no external packages required
- **🖥️ Cross-Platform**: Export Claude Code logs on any OS
- **📊 Tested**: Core extraction functionality tested and reliable

## 📦 Install Claude Conversation Extractor

### Quick Install (Recommended)

```bash
# Using pipx (solves Python environment issues)
pipx install claude-conversation-extractor

# OR using pip
pip install claude-conversation-extractor
```

### Platform-Specific Setup

<details>
<summary>macOS</summary>

```bash
# Install pipx first
brew install pipx
pipx ensurepath

# Then install the extractor
pipx install claude-conversation-extractor
```
</details>

<details>
<summary>Windows</summary>

```bash
# Install pipx
py -m pip install --user pipx
py -m pipx ensurepath
# Restart terminal, then:

# Install the extractor
pipx install claude-conversation-extractor
```
</details>

<details>
<summary>Linux</summary>

```bash
# Ubuntu/Debian
sudo apt install pipx
pipx ensurepath

# Install the extractor
pipx install claude-conversation-extractor
```
</details>

## 🚀 How to Export Claude Code Conversations

### Quick Start - Export Claude Conversations
```bash
# Run the interactive UI with ASCII art logo
claude-start

# Run the standard CLI interface
claude-extract

# Note: claude-logs also works for backward compatibility
```

That's it! The tool will:
1. Find your Claude Code conversations in ~/.claude/projects
2. Show an interactive menu to search or export
3. Convert Claude JSONL files to readable Markdown, JSON, or HTML

### Export Claude Code Logs - All Methods

```bash
# Interactive mode with UI - easiest way to export Claude conversations
claude-start

# CLI mode - command-line interface
claude-extract

# List all Claude Code conversations
claude-extract --list

# Export specific Claude chats by number
claude-extract --extract 1,3,5

# Export recent Claude Code sessions
claude-extract --recent 5

# Backup all Claude conversations at once
claude-extract --all

# Save Claude logs to custom location
claude-extract --output ~/my-claude-backups
```

### 📄 Export Formats - NEW in v1.2.0!

Export conversations in multiple formats:

```bash
# Export as JSON for programmatic processing
claude-extract --format json --extract 1

# Export as HTML with beautiful formatting
claude-extract --format html --all

# Export as PDF (requires optional dependency)
pip install claude-conversation-extractor[pdf]
claude-extract --format pdf --extract 1

# Export as DOCX (requires optional dependency)
pip install claude-conversation-extractor[docx]
claude-extract --format docx --all

# Install all optional export formats
pip install claude-conversation-extractor[all]

# Include tool use, MCP responses, and system messages
claude-extract --detailed --extract 1

# Combine options for complete exports
claude-extract --format html --detailed --recent 5
```

**Supported Formats:**
- **Markdown** (default) - Clean, readable text format
- **JSON** - Structured data for analysis and processing
- **HTML** - Beautiful web-viewable format with syntax highlighting
- **PDF** - Portable document format (optional: `pip install .[pdf]`)
- **DOCX** - Microsoft Word format (optional: `pip install .[docx]`)

**Detailed Mode (`--detailed`):**
Includes complete conversation transcript with:
- Tool use invocations and parameters
- MCP server responses
- System messages and errors
- Terminal command outputs
- All metadata from the conversation

## 📁 Where Are Claude Code Logs Stored?

### Claude Code Default Locations:
- **macOS/Linux**: `~/.claude/projects/*/chat_*.jsonl`
- **Windows**: `%USERPROFILE%\.claude\projects\*\chat_*.jsonl`
- **Format**: Undocumented JSONL with base64 encoded content

### Exported Claude Conversation Locations:
```text
~/Desktop/Claude logs/claude-conversation-2025-06-09-abc123.md
├── Metadata (session ID, timestamp)
├── User messages with 👤 prefix
├── Claude responses with 🤖 prefix
└── Clean Markdown formatting
```

## ❓ Frequently Asked Questions

### How do I export Claude Code conversations?
Install with `pipx install claude-conversation-extractor` then run `claude-extract`. The tool automatically finds all conversations in ~/.claude/projects.

### How do I export the detailed transcript with tool use?
Use the `--detailed` flag to include tool invocations, MCP responses, terminal outputs, and system messages:
```bash
claude-extract --detailed --format html --extract 1
```
This gives you the complete conversation as seen in Claude's Ctrl+R view.

### Where does Claude Code store conversations?
Claude Code saves all chats in `~/.claude/projects/` as JSONL files. There's no built-in export feature - that's why this tool exists.

### How to backup all Claude Code sessions?
Run `claude-extract --all` to export every conversation at once, or use the interactive menu option "Export all conversations".

### Does this work with Claude.ai (web version)?
No, this tool specifically exports Claude Code (desktop app) conversations. Claude.ai has its own export feature in settings.

### Can I convert Claude JSONL to other formats?
Yes! Version 1.2.0 supports multiple export formats:
- **Markdown** - Default clean text format
- **JSON** - Structured data with timestamps and metadata
- **HTML** - Beautiful web-viewable format with modern styling
- **PDF** - Portable document format (requires: `pip install claude-conversation-extractor[pdf]`)
- **DOCX** - Microsoft Word format (requires: `pip install claude-conversation-extractor[docx]`)
Use `--format json`, `--format html`, `--format pdf`, or `--format docx` when extracting.

### Is this tool official?
No, this is an independent open-source tool. It reads the local Claude Code files on your computer - no API or internet required.

## 📊 Why This is the Best Claude Code Export Tool

| Feature | Claude Conversation Extractor | Manual Copy | Claude.ai Export |
|---------|------------------------------|-------------|------------------|
| Works with Claude Code | ✅ Full support | ✅ Tedious | ❌ Different product |
| Bulk export | ✅ All conversations | ❌ One at a time | ❌ N/A |
| Clean formatting | ✅ Perfect Markdown | ❌ Terminal artifacts | ❌ N/A |
| Zero configuration | ✅ Auto-detects | ❌ Manual process | ❌ N/A |
| Cross-platform | ✅ Win/Mac/Linux | ✅ Manual works | ❌ N/A |

## 🔧 Technical Details

### How Claude Conversation Extractor Works

1. **Locates Claude Code logs**: Scans ~/.claude/projects for JSONL files
2. **Parses undocumented format**: Handles Claude's internal data structure
3. **Extracts conversations**: Preserves user inputs and Claude responses
4. **Converts to Markdown**: Clean format without terminal escape codes

### Requirements
- Python 3.8+ (works with 3.9, 3.10, 3.11, 3.12)
- Claude Code installed with existing conversations
- No external dependencies for core features

## 🤝 Contributing

Help make the best Claude Code export tool even better! See [CONTRIBUTING.md](docs/development/CONTRIBUTING.md).

### Development Setup
```bash
# Clone the repo
git clone https://github.com/ZeroSumQuant/claude-conversation-extractor.git
cd claude-conversation-extractor

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dev dependencies
pip install -r requirements-dev.txt

# Run tests
pytest
```

## 🐛 Troubleshooting Claude Export Issues

### Can't find Claude Code conversations?
- Ensure Claude Code has been used at least once
- Check `~/.claude/projects/` exists and has .jsonl files
- Verify read permissions on the directory
- Try `ls -la ~/.claude/projects/` to see if files exist

### "No Claude sessions found" error
- Claude Code must be installed and used before exporting
- Check the correct user directory is being scanned
- Ensure you're running the tool as the same user who uses Claude Code

### Installation issues?
See [INSTALL.md](docs/user/INSTALL.md) for:
- Fixing "externally managed environment" errors
- PATH configuration help
- Platform-specific troubleshooting

## 🔒 Privacy & Security

- ✅ **100% Local**: Never sends your Claude conversations anywhere
- ✅ **No Internet**: Works completely offline
- ✅ **No Tracking**: Zero telemetry or analytics
- ✅ **Open Source**: Audit the code yourself
- ✅ **Read-Only**: Never modifies your Claude Code files

## 📈 Roadmap for Claude Code Export Tool

### ✅ Completed in v1.2.0
- [x] Export Claude Code conversations to Markdown
- [x] Bulk export all Claude sessions
- [x] Export to JSON format with metadata
- [x] Export to HTML with beautiful formatting
- [x] Detailed transcript mode with tool use/MCP responses
- [x] Export to PDF format (optional dependency)
- [x] Export to DOCX format (optional dependency)

### 🚧 Planned Features
- [ ] Automated daily backups of Claude conversations
- [ ] Integration with Obsidian, Notion, Roam
- [ ] Watch mode for auto-export of new conversations
- [ ] Filter by date range (--after, --before flags)
- [ ] Export statistics and analytics dashboard

## ⚖️ Legal Disclaimer

This tool accesses Claude Code conversation data stored locally in ~/.claude/projects on your computer. You are accessing your own data. This is an independent project not affiliated with Anthropic. Use responsibly and in accordance with Claude's terms of service.

## 📜 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Support the Project

If this tool helps you export Claude Code conversations:
- ⭐ Star this repo to help others find it
- 🐛 Report issues if you find bugs
- 💡 Suggest features you'd like to see
- 📣 Share with other Claude Code users

---

**Keywords**: export claude code conversations, claude conversation extractor, claude code export tool, backup claude code logs, save claude chat history, claude jsonl to markdown, ~/.claude/projects, extract claude sessions, claude code no export button, where are claude code logs stored, claude terminal logs, anthropic claude code export

**Note**: This is an independent tool for exporting Claude Code conversations. Not affiliated with Anthropic.