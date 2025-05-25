# Claude Conversation Extractor

Extract clean, readable conversation logs from Claude Code's internal storage - no more messy terminal logs!

[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🎯 Problem Solved

Claude Code stores all your conversations locally but doesn't provide an easy way to export them. This tool:

- 📤 Extracts conversations from Claude's undocumented JSONL format
- 📝 Converts them to clean, readable markdown 
- 🔍 Makes your Claude history searchable and archivable
- 💾 Preserves your work when sessions crash or get cleared
- 🚀 Works with your existing Claude Code installation

## ✨ Features

- **Clean Markdown Export**: Get your conversations in readable markdown format
- **Batch Operations**: Extract single, multiple, or all conversations at once
- **Smart Defaults**: Automatically finds the best location for your logs
- **Zero Dependencies**: Uses only Python standard library
- **Session Management**: List, search, and organize your Claude sessions
- **Preserves Context**: Maintains timestamps and session IDs

## 📦 Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/yourusername/claude-conversation-extractor.git
cd claude-conversation-extractor

# Make the script executable
chmod +x extract_claude_logs.py

# Optional: Add to your PATH for system-wide access
sudo ln -s $(pwd)/extract_claude_logs.py /usr/local/bin/claude-extract
```

### Install with pip (coming soon)

```bash
pip install claude-conversation-extractor
```

## 🚀 Usage

### Basic Commands

```bash
# List all available Claude sessions
./extract_claude_logs.py --list

# Extract the most recent conversation
./extract_claude_logs.py --extract 1

# Extract multiple specific conversations
./extract_claude_logs.py --extract 1,3,5

# Extract the 5 most recent conversations
./extract_claude_logs.py --recent 5

# Extract all conversations
./extract_claude_logs.py --all

# Specify custom output directory
./extract_claude_logs.py --extract 1 --output ~/my-claude-logs
```

### Shell Aliases (Recommended)

Add these to your `~/.bashrc` or `~/.zshrc`:

```bash
# Quick access commands
alias claude-list='python3 ~/path/to/extract_claude_logs.py --list'
alias claude-recent='python3 ~/path/to/extract_claude_logs.py --recent 5'
alias claude-extract='python3 ~/path/to/extract_claude_logs.py --extract'
alias claudelogs='open ~/Desktop/Claude\ logs'  # macOS
# alias claudelogs='xdg-open ~/Desktop/Claude\ logs'  # Linux
```

## 📁 Output Format

Conversations are saved as markdown files with this structure:

```
claude-conversation-2025-05-25-a1b2c3d4.md
├── Session metadata (ID, date, time)
├── User messages (👤)
├── Claude responses (🤖)
└── Clean formatting with no terminal artifacts
```

### Example Output

```markdown
# Claude Conversation Log

Session ID: a1b2c3d4-5678-90ef-ghij-klmnopqrstuv
Date: 2025-05-25 14:30:00

---

## 👤 User

How do I read a file in Python?

---

## 🤖 Claude

To read a file in Python, you can use the built-in `open()` function...

---
```

## 🔧 Technical Details

### How It Works

1. Claude Code stores conversations in `~/.claude/projects/` as JSONL files
2. This tool parses the undocumented JSONL format
3. Extracts user prompts and Claude responses
4. Converts to clean markdown without terminal formatting
5. Preserves conversation flow and context

### File Locations

- **Source**: `~/.claude/projects/*/chat_*.jsonl`
- **Default Output**: `~/Desktop/Claude logs/` (or `~/Documents/Claude logs/`)
- **Fallback**: Current directory if default locations aren't writable

### Requirements

- Python 3.8 or higher
- Claude Code installed and used at least once
- No external dependencies required

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup

```bash
# Clone the repo
git clone https://github.com/yourusername/claude-conversation-extractor.git
cd claude-conversation-extractor

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # or `venv\Scripts\activate` on Windows

# Install development dependencies
pip install -r requirements-dev.txt

# Run tests
pytest
```

## 📊 Comparison with Other Tools

| Feature | This Tool | claude.ai Export | Manual Copy |
|---------|-----------|------------------|-------------|
| Works with Claude Code CLI | ✅ | ❌ | ✅ |
| Clean markdown output | ✅ | ❌ | ❌ |
| Batch export | ✅ | ❌ | ❌ |
| Preserves formatting | ✅ | ⚠️ | ❌ |
| No manual effort | ✅ | ✅ | ❌ |
| Searchable archive | ✅ | ⚠️ | ❌ |

## 🐛 Troubleshooting

### No sessions found
- Make sure you've used Claude Code at least once
- Check that `~/.claude/projects/` exists
- Verify you have read permissions

### Permission errors
- Ensure you have write access to the output directory
- Try using `--output` to specify a different location

### Incomplete conversations
- Some very old sessions might have different formats
- Crashed sessions may have incomplete data

## 🔒 Privacy & Security

- All data stays local on your machine
- No internet connection required
- No data is sent anywhere
- You have full control over your exported conversations

## ⚖️ Disclaimer

This tool accesses conversation data that Claude Code stores locally on your machine. By using this tool:
- You acknowledge that you're accessing your own user-generated conversation data
- You are responsible for compliance with any applicable terms of service
- This tool does not modify, reverse engineer, or interfere with Claude Code's operation
- The authors are not responsible for any misuse of exported conversation data

This is an independent project and is not affiliated with, endorsed by, or sponsored by Anthropic.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Thanks to the Claude Code team for creating an amazing tool
- Inspired by the need for better conversation management
- Community feedback and contributions

## 🚧 Roadmap

- [ ] Search functionality across all conversations
- [ ] Export to different formats (JSON, HTML, PDF)
- [ ] Conversation merging and organization
- [ ] Integration with note-taking tools
- [ ] GUI version for non-technical users

---

**Note**: This tool is not officially affiliated with Anthropic or Claude. It's a community-built solution for managing Claude Code conversations.