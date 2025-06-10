# Claude Conversation Extractor v1.1.0

## 🎉 Interactive Terminal UI Release

This release introduces a beautiful interactive terminal UI that makes extracting Claude conversations simple and intuitive. Clear on-screen options guide you through the process!

## ✨ What's New

### 🖥️ Interactive Terminal UI
- **Bold Magenta ASCII Art Banner** - Eye-catching title display
- **Easy Folder Selection** - Pre-configured suggestions for Desktop, Documents, Downloads
- **Visual Conversation List** - See all your Claude chats with dates and sizes
- **Simple Text-Based Selection**:
  - Type `A` - Extract ALL conversations
  - Type `R` - Extract 5 most RECENT
  - Type `S` - SELECT specific ones
  - Type `Q` - QUIT

### 🚀 New Commands
- `claude-extract --export logs` - New command to launch the interactive UI
- `claude-start` - Quick shortcut for even faster access
- All existing commands still work for backwards compatibility

### 📦 Improved Installation Experience
- Clear post-install message with quick start instructions
- GitHub star reminder
- No auto-launching to keep CI/CD pipelines safe

## 📊 Usage Examples

```bash
# After installation
pip install claude-conversation-extractor

# Launch the interactive UI (pick your favorite)
claude-extract --export logs
claude-start
claude-extract --interactive
claude-extract -i

# Or use the classic commands
claude-extract --list
claude-extract --extract 1,3,5
claude-extract --recent 5
```

## 🔧 Technical Details

- **Zero Dependencies** - Still using only Python standard library
- **Python 3.8+** compatible
- **Cross-platform** - Works on Windows, macOS, and Linux
- **Safe** - Read-only access to Claude's conversation files
- **Clean** - Passes all linting (black, isort, flake8, bandit)
- **Tested** - Comprehensive test suite added

## 📈 Current Stats
- 2 GitHub stars
- 152 GitHub clones from 38 unique sources
- Created on May 25, 2025
- Growing community of Claude Code users

## 🙏 Thank You

If this tool helps you, please:
- ⭐ Star us on GitHub: https://github.com/ZeroSumQuant/claude-conversation-extractor
- 🐛 Report issues: https://github.com/ZeroSumQuant/claude-conversation-extractor/issues
- 🤝 Contribute: PRs welcome!

---

**Note**: This tool is not affiliated with Anthropic. It's a community-built solution for managing Claude Code conversations.