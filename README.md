# Claude Conversation Extractor - Export Claude Code Conversations to Markdown | Save Chat History

> 🚀 **The ONLY tool to export Claude Code conversations**. Extract Claude chat history from ~/.claude/projects, search through logs, and backup your AI programming sessions.

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
- ❌ **Search Claude Code chat history** to find that solution from last week
- ❌ **Backup Claude Code logs** for documentation or sharing
- ❌ **Convert Claude JSONL to Markdown** for readable archives

## ✅ Claude Conversation Extractor: The First Export Tool for Claude Code

This is the **ONLY tool that exports Claude Code conversations**:
- ✅ **Finds Claude Code logs** automatically in ~/.claude/projects
- ✅ **Extracts Claude conversations** to clean Markdown files
- ✅ **Searches Claude chat history** with real-time results
- ✅ **Backs up all Claude sessions** with one command
- ✅ **Works on Windows, macOS, Linux** - wherever Claude Code runs

## ✨ Features for Claude Code Users

- **🔍 Real-Time Search**: Search Claude conversations as you type - no flags needed
- **📝 Claude JSONL to Markdown**: Clean export without terminal artifacts
- **⚡ Find Any Chat**: Search by content, date, or conversation name
- **📦 Bulk Export**: Extract all Claude Code conversations at once
- **🎯 Zero Config**: Just run `claude-logs` - we find everything automatically
- **🚀 No Dependencies**: Pure Python - no external packages required
- **🖥️ Cross-Platform**: Export Claude Code logs on any OS
- **📊 97% Test Coverage**: Reliable extraction you can trust

## 📦 Install Claude Conversation Extractor

### Recommended: Install with pipx (Solves "externally managed environment" errors)

[pipx](https://pipx.pypa.io/) installs the Claude Code export tool in an isolated environment.

#### Export Claude Code on macOS
```bash
# Install pipx
brew install pipx
pipx ensurepath

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor
```

#### Export Claude Code on Windows
```bash
# Install pipx
py -m pip install --user pipx
py -m pipx ensurepath
# Restart terminal, then:

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor
```

#### Export Claude Code on Linux
```bash
# Ubuntu/Debian
sudo apt install pipx
pipx ensurepath

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor
```

### Alternative: Install with pip
```bash
pip install claude-conversation-extractor
```

## 🚀 How to Export Claude Code Conversations

### Quick Start - Export Claude Conversations
```bash
# Just run this - finds all Claude Code logs automatically
claude-logs
```

That's it! The tool will:
1. Find your Claude Code conversations in ~/.claude/projects
2. Show an interactive menu to search or export
3. Convert Claude JSONL files to readable Markdown

### Export Claude Code Logs - All Methods

```bash
# Interactive mode - easiest way to export Claude conversations
claude-logs

# List all Claude Code conversations
claude-logs --list

# Export specific Claude chats by number
claude-logs --extract 1,3,5

# Export recent Claude Code sessions
claude-logs --recent 5

# Backup all Claude conversations at once
claude-logs --all

# Save Claude logs to custom location
claude-logs --output ~/my-claude-backups
```

### 🔍 Search Claude Code Chat History

Real-time search across all your Claude conversations:

```bash
# Method 1: From main menu
claude-logs
# Select "Search conversations"

# Method 2: Direct search
claude-logs search
```

**Search features:**
- Type to search - results appear instantly
- Finds exact matches, patterns, and semantic similarity
- Navigate with arrow keys
- Press Enter to export found conversations

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
Install with `pipx install claude-conversation-extractor` then run `claude-logs`. The tool automatically finds all conversations in ~/.claude/projects.

### Where does Claude Code store conversations?
Claude Code saves all chats in `~/.claude/projects/` as JSONL files. There's no built-in export feature - that's why this tool exists.

### Can I search my Claude Code history?
Yes! Run `claude-logs search` or select "Search conversations" from the menu. Type anything and see results instantly.

### How to backup all Claude Code sessions?
Run `claude-logs --all` to export every conversation at once, or use the interactive menu option "Export all conversations".

### Does this work with Claude.ai (web version)?
No, this tool specifically exports Claude Code (desktop app) conversations. Claude.ai has its own export feature in settings.

### Can I convert Claude JSONL to other formats?
Currently exports to Markdown. JSON, HTML, and PDF exports are planned. The Markdown format is clean and converts easily to other formats.

### Is this tool official?
No, this is an independent open-source tool. It reads the local Claude Code files on your computer - no API or internet required.

## 📊 Why This is the Best Claude Code Export Tool

| Feature | Claude Conversation Extractor | Manual Copy | Claude.ai Export |
|---------|------------------------------|-------------|------------------|
| Works with Claude Code | ✅ Full support | ✅ Tedious | ❌ Different product |
| Bulk export | ✅ All conversations | ❌ One at a time | ❌ N/A |
| Search capability | ✅ Real-time search | ❌ None | ❌ N/A |
| Clean formatting | ✅ Perfect Markdown | ❌ Terminal artifacts | ❌ N/A |
| Zero configuration | ✅ Auto-detects | ❌ Manual process | ❌ N/A |
| Cross-platform | ✅ Win/Mac/Linux | ✅ Manual works | ❌ N/A |

## 🔧 Technical Details

### How Claude Conversation Extractor Works

1. **Locates Claude Code logs**: Scans ~/.claude/projects for JSONL files
2. **Parses undocumented format**: Handles Claude's internal data structure
3. **Extracts conversations**: Preserves user inputs and Claude responses
4. **Converts to Markdown**: Clean format without terminal escape codes
5. **Enables search**: Indexes content for instant searching

### Requirements
- Python 3.8+ (works with 3.9, 3.10, 3.11, 3.12)
- Claude Code installed with existing conversations
- No external dependencies for core features

### Optional: Advanced Search with spaCy
```bash
# For semantic search capabilities
pip install spacy
python -m spacy download en_core_web_sm
```

## 🤝 Contributing

Help make the best Claude Code export tool even better! See [CONTRIBUTING.md](CONTRIBUTING.md).

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
See [INSTALL.md](INSTALL.md) for:
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

- [x] Export Claude Code conversations to Markdown
- [x] Real-time search for Claude chat history  
- [x] Bulk export all Claude sessions
- [ ] Export to JSON, HTML, PDF formats
- [ ] Chrome extension to add export button to Claude Code
- [ ] Automated daily backups of Claude conversations
- [ ] Integration with Obsidian, Notion, Roam

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