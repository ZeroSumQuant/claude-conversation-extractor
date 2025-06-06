# Claude Conversation Extractor v1.1.0 Release Notes

## 🎉 Big Button Release - Interactive UI Edition

This release introduces a beautiful interactive terminal UI that makes extracting Claude conversations as easy as possible. No more memorizing commands - just run and click!

## ✨ What's New

### 🖥️ Interactive Terminal UI
- **Big, Bold, Magenta ASCII Banner** - Can't miss it when you launch!
- **Easy Folder Selection** - Pre-configured suggestions for Desktop, Documents, Downloads
- **Visual Conversation List** - See all your Claude chats with dates and sizes
- **Simple Export Options**:
  - `A` - Extract ALL conversations
  - `R` - Extract 5 most RECENT
  - `S` - SELECT specific ones
  - `Q` - QUIT

### 🚀 New Commands
- `claude-extract --export logs` - The new primary command to launch the interactive UI
- `claude-start` - Quick shortcut for even faster access
- All existing commands still work for backwards compatibility

### 📦 Improved Installation Experience
- Clear post-install message with quick start instructions
- GitHub star reminder (⭐ If this tool helps you!)
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

## 🙏 Thank You

Thank you to everyone who has used and starred this project! This tool has become the #1 search result for Claude conversation extraction, with 319+ downloads in the first 9 days.

If this tool helps you, please:
- ⭐ Star us on GitHub: https://github.com/ZeroSumQuant/claude-conversation-extractor
- 🐛 Report issues: https://github.com/ZeroSumQuant/claude-conversation-extractor/issues
- 🤝 Contribute: PRs welcome!

## 📈 Stats
- 345 GitHub clones from 79 unique sources
- #1 search result for "Claude conversation extractor"
- Growing community of Claude Code users

---

**Note**: This tool is not affiliated with Anthropic. It's a community-built solution for managing Claude Code conversations.