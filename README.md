# Claude Conversation Extractor - Export & Save Claude Code Chat History

> 🚀 **Export Claude conversations**, save Claude Code logs, and backup your AI chat history with this powerful Python tool.

[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PyPI version](https://badge.fury.io/py/claude-conversation-extractor.svg)](https://badge.fury.io/py/claude-conversation-extractor)
[![Downloads](https://pepy.tech/badge/claude-conversation-extractor)](https://pepy.tech/project/claude-conversation-extractor)
[![GitHub stars](https://img.shields.io/github/stars/ZeroSumQuant/claude-conversation-extractor?style=social)](https://github.com/ZeroSumQuant/claude-conversation-extractor)
[![Export Claude Conversations](https://img.shields.io/badge/Export-Claude%20Conversations-blue)](https://github.com/ZeroSumQuant/claude-conversation-extractor)
[![Save Claude Logs](https://img.shields.io/badge/Save-Claude%20Logs-green)](https://github.com/ZeroSumQuant/claude-conversation-extractor)

**The #1 tool to export Claude conversations from Claude Code.** Extract, search, and backup your Claude chat history with zero dependencies.

🔥 **Popular features:** [Real-time search](#real-time-search) | [Export conversations](#quick-start) | [Save Claude logs](#export-claude-code-logs) | [Backup all sessions](#backup-all-conversations)

## 📸 Demo

![How to export Claude conversations - Demo](https://raw.githubusercontent.com/ZeroSumQuant/claude-conversation-extractor/main/assets/demo.gif)

## 🎯 The Problem: Can't Export Claude Code Conversations?

Claude Code stores all your conversations locally but doesn't provide an easy export feature. You need a way to:
- ❌ Export Claude conversations before they're lost
- ❌ Search through your Claude chat history
- ❌ Backup Claude Code logs for future reference
- ❌ Convert Claude sessions to readable formats

## ✅ The Solution: Claude Conversation Extractor

This tool solves all these problems by:
- ✅ Automatically finding and extracting Claude Code logs
- ✅ Converting conversations to clean markdown
- ✅ **NEW:** Real-time search - type and see results instantly!
- ✅ Enabling batch export of all conversations
- ✅ Working seamlessly across Windows, macOS, and Linux

## ✨ Features

- **🔍 Real-Time Search**: No flags needed! Just type and watch results appear live
- **📝 Clean Markdown Export**: Get your conversations in readable markdown format
- **⚡ Smart Search**: Automatically uses best search strategy (exact, regex, semantic)
- **📦 Batch Operations**: Extract single, multiple, or all conversations at once
- **🎯 Interactive UI**: Beautiful terminal interface - no command memorization needed
- **🚀 Zero Dependencies**: Core functionality uses only Python standard library
- **🖥️ Cross-Platform**: Works on Windows, macOS, and Linux
- **📊 97% Test Coverage**: Robust and reliable codebase

## 📦 How to Install Claude Conversation Extractor

### Recommended: Install with pipx (All Platforms)

[pipx](https://pipx.pypa.io/) installs Python applications in isolated environments. **This is the best way to avoid installation issues.**

#### macOS
```bash
# Install pipx
brew install pipx
pipx ensurepath

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor
```

#### Windows
```bash
# Install pipx
py -m pip install --user pipx
py -m pipx ensurepath
# Restart your terminal, then:

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor
```

#### Linux
```bash
# Ubuntu/Debian
sudo apt install pipx
pipx ensurepath

# Fedora
sudo dnf install pipx

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor
```

### Alternative: Install with pip

See [INSTALL.md](INSTALL.md) for detailed installation instructions and troubleshooting.

```bash
pip install claude-conversation-extractor
```

## 🚀 Quick Start

```bash
# Just run this - no flags needed!
claude-logs
```

That's it! The interactive UI will guide you through everything.

## 🎯 Export Claude Conversations - Usage Guide

### The Magic of No Flags

We've eliminated the need for complex command-line flags. Everything is interactive:

```bash
claude-logs
```

This launches the main interface where you can:
1. **Search conversations** - Select option and start typing for live results
2. **Export recent** - Quick access to your latest conversations  
3. **Export specific** - Choose exactly which conversations to save
4. **Export all** - One-click backup of everything

### 🔍 Real-Time Search

The killer feature - search without any flags:

```bash
# Option 1: From main menu
claude-logs
# Then select "Search conversations"

# Option 2: Direct search command
claude-logs search
```

**How it works:**
- Start typing - results appear instantly
- No need to press Enter after your query
- Arrow keys to navigate results
- Press Enter to export selected conversation
- ESC to go back

**Search is smart:**
- Finds exact matches first
- Then tries regex patterns
- Then semantic similarity (if available)
- All automatically - no configuration needed!

### Export Claude Code Logs

For power users who prefer commands:

```bash
# List all conversations
claude-logs --list

# Export specific ones
claude-logs --extract 1,3,5

# Export recent
claude-logs --recent 5

# Export everything
claude-logs --all

# Custom output location
claude-logs --output ~/my-backups
```

## 📁 Where Are Claude Code Logs Saved?

Conversations are saved as clean markdown files:

```text
claude-conversation-2025-05-25-a1b2c3d4.md
├── Session metadata (ID, date, time)
├── User messages (👤)
├── Claude responses (🤖)
└── Clean formatting with no terminal artifacts
```

**Default locations:**
- **Source**: `~/.claude/projects/*/chat_*.jsonl`
- **Output**: `~/Desktop/Claude logs/` (or `~/Documents/Claude logs/`)

## ❓ Frequently Asked Questions

### How do I export Claude conversations?
Simply install with `pipx install claude-conversation-extractor` and run `claude-logs`. No flags or complex commands needed!

### How do I search my Claude chat history?
Run `claude-logs` and select "Search conversations", or use `claude-logs search` directly. Just start typing - results appear live!

### Where are Claude Code logs stored?
Claude Code stores conversations in `~/.claude/projects/` as JSONL files. This tool automatically finds and extracts them.

### How to backup all Claude conversations?
Run `claude-logs` and select "Export all conversations", or use `claude-logs --all` for command-line usage.

### Does this work with Claude.ai?
This tool is specifically designed for Claude Code (the CLI/desktop app). For claude.ai, use the built-in export feature.

### Why is search so fast?
We cache results and use smart search strategies, checking exact matches first before trying more complex patterns.

### Why should I use pipx instead of pip?
pipx solves the "externally managed environment" error on modern systems and ensures the tool works reliably across all platforms.

## 📚 Use Cases

- **Developers**: Export Claude Code conversations for documentation
- **Researchers**: Save Claude AI chat history for analysis  
- **Teams**: Backup Claude conversations for knowledge sharing
- **Students**: Extract Claude coding sessions for study notes
- **Content Creators**: Convert Claude chats to blog posts
- **Professionals**: Archive important AI consultations

## 📊 Claude Export Tools Comparison

| Export Method | Works with Claude Code | Clean Output | Batch Export | Live Search | No Flags Needed |
|--------------|------------------------|--------------|--------------|-------------|-----------------|
| **This Tool** | ✅ Export Claude logs | ✅ Clean markdown | ✅ Backup all | ✅ Real-time results | ✅ Interactive UI |
| claude.ai Export | ❌ | ❌ | ❌ | ❌ | ❌ |
| Manual Copy | ✅ | ❌ | ❌ | ❌ | ❌ |

## 🔧 Technical Details

### How It Works

1. Claude Code stores conversations in `~/.claude/projects/` as JSONL files
2. This tool parses the undocumented JSONL format
3. Extracts user prompts and Claude responses
4. Converts to clean markdown without terminal formatting
5. Provides real-time search with smart result ranking

### Requirements

- Python 3.8 or higher
- Claude Code installed and used at least once
- No external dependencies for core features

### Optional Features

- **Semantic Search**: Install spaCy for AI-powered search
  ```bash
  pip install spacy
  python -m spacy download en_core_web_sm
  ```

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Clone the repo
git clone https://github.com/ZeroSumQuant/claude-conversation-extractor.git
cd claude-conversation-extractor

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install development dependencies
pip install -r requirements-dev.txt

# Run tests (97% coverage!)
pytest
```

## 🐛 Troubleshooting

### Installation Issues

See [INSTALL.md](INSTALL.md) for detailed troubleshooting:
- "Externally managed environment" errors
- PATH configuration
- Platform-specific issues

### No sessions found
- Make sure you've used Claude Code at least once
- Check that `~/.claude/projects/` exists
- Verify read permissions

### Search not working
- Ensure you have at least one conversation
- Try the export list option first to verify conversations are detected
- Check file permissions on `~/.claude/projects/`

## 🔒 Privacy & Security

- ✅ All data stays local on your machine
- ✅ No internet connection required
- ✅ No telemetry or data collection
- ✅ You control your exported conversations
- ✅ Open source and auditable

## ⚖️ Disclaimer

This tool accesses conversation data that Claude Code stores locally on your machine. By using this tool, you acknowledge that you're accessing your own user-generated conversation data and are responsible for compliance with any applicable terms of service.

This is an independent project and is not affiliated with, endorsed by, or sponsored by Anthropic.

## 📜 License

MIT License - see [LICENSE](LICENSE) for details.

## 🚧 Roadmap

- [x] Search functionality across all conversations ✅
- [x] Real-time search interface ✅  
- [x] Smart search (automatic strategy selection) ✅
- [ ] Export to different formats (JSON, HTML, PDF)
- [ ] Conversation merging and organization
- [ ] Integration with note-taking tools
- [ ] GUI version for non-technical users

## 🙏 Acknowledgments

- Thanks to the Claude Code team for creating an amazing tool
- Community feedback and contributions
- Special thanks to early adopters and testers

---

**Note**: This tool is not officially affiliated with Anthropic or Claude. It's a community-built solution for managing Claude Code conversations.

<!-- SEO Keywords: export claude conversations, claude code logs, extract claude chat history, save claude conversations, claude conversation backup, claude code export tool, how to export claude chats, claude terminal logs, backup claude sessions, claude markdown export, search claude conversations, claude chat archive -->