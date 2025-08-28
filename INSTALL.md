# How to Install Claude Conversation Extractor - Export Claude Code Logs

This guide helps you install the Claude Code export tool on any platform. If you're getting errors trying to export Claude conversations, you're in the right place!

## Table of Contents
- [Quick Install - Export Claude Code Conversations](#quick-install-export-claude-code-conversations)
- [Platform-Specific Instructions](#platform-specific-instructions)
  - [Export Claude Code on macOS](#export-claude-code-on-macos)
  - [Export Claude Code on Windows](#export-claude-code-on-windows)
  - [Export Claude Code on Linux](#export-claude-code-on-linux)
- [Troubleshooting Claude Export Issues](#troubleshooting-claude-export-issues)
- [Alternative Methods to Export Claude Conversations](#alternative-methods-to-export-claude-conversations)
- [Verify Claude Conversation Extractor Installation](#verify-claude-conversation-extractor-installation)

## Quick Install - Export Claude Code Conversations

The easiest way to install the Claude Code export tool is using pipx:

```bash
# Install pipx first (see platform sections for details)
pipx install claude-conversation-extractor
```

This installs the tool to export Claude Code conversations from ~/.claude/projects to markdown files.

## Platform-Specific Instructions

### Export Claude Code on macOS

#### Method 1: Using pipx (Recommended for Claude Code Export)

```bash
# Install pipx via Homebrew
brew install pipx
pipx ensurepath

# Restart terminal or run:
source ~/.zshrc  # or ~/.bash_profile for older macOS

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor

# Now you can export Claude Code logs:
claude-extract
```

#### Method 2: Using pip with venv (Alternative Claude Export Method)

```bash
# Create virtual environment for Claude export tool
python3 -m venv claude-export-env
source claude-export-env/bin/activate

# Install the Claude Code export tool
pip install claude-conversation-extractor

# Create alias to export Claude conversations easily
echo 'alias claude-extract="source ~/claude-export-env/bin/activate && claude-extract"' >> ~/.zshrc
source ~/.zshrc
```

#### Common macOS Issues When Exporting Claude Code

**"command not found" after installing Claude extractor**
```bash
# Add ~/.local/bin to PATH for Claude export commands
echo $PATH | grep -q ~/.local/bin || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**"externally managed environment" error (macOS 13+)**
- This is why pipx is recommended for Claude Code export
- Alternative: `pip install --user --break-system-packages claude-conversation-extractor`

### Export Claude Code on Windows

#### Method 1: Using pipx (Best for Exporting Claude Conversations)

```batch
REM Install pipx for Claude export tool
py -m pip install --user pipx
py -m pipx ensurepath

REM Restart Command Prompt or PowerShell

REM Install Claude Conversation Extractor
pipx install claude-conversation-extractor

REM Export Claude Code conversations:
claude-logs
```

#### Method 2: PowerShell Installation for Claude Export

```powershell
# If execution policy blocks Claude export tool:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Install pipx for Claude Code export
python -m pip install --user pipx
python -m pipx ensurepath

# Restart PowerShell

# Install tool to export Claude conversations
pipx install claude-conversation-extractor
```

#### Common Windows Issues Exporting Claude Code

**"'claude-extract' is not recognized" when trying to export Claude conversations**
1. Add Python Scripts to PATH:
   ```batch
   REM Replace YourUsername with actual username
   setx PATH "%PATH%;C:\Users\YourUsername\AppData\Local\Programs\Python\Python311\Scripts"
   ```
2. Restart Command Prompt
3. Try `claude-extract` again to export Claude Code logs

**"Access denied" when installing Claude export tool**
- Run as Administrator
- Or use: `pip install --user claude-conversation-extractor`

### Export Claude Code on Linux

#### Ubuntu/Debian - Install Claude Conversation Extractor

```bash
# Install pipx for Claude export tool
sudo apt update
sudo apt install pipx
pipx ensurepath

# Restart terminal or run:
source ~/.bashrc

# Install tool to export Claude Code conversations
pipx install claude-conversation-extractor

# Export Claude logs:
claude-extract
```

#### Fedora/RHEL - Extract Claude Conversations

```bash
# Install pipx for Claude Code export
sudo dnf install pipx

# Install Claude Conversation Extractor
pipx install claude-conversation-extractor
```

#### Arch Linux - Backup Claude Code Logs

```bash
# Install pipx for Claude export functionality
sudo pacman -S python-pipx

# Install tool to extract Claude sessions
pipx install claude-conversation-extractor
```

#### Common Linux Issues When Exporting Claude Code

**"externally managed environment" (Ubuntu 23.04+, Fedora 38+)**
```bash
# Use pipx to export Claude conversations (recommended)
# Or create virtual environment:
python3 -m venv ~/claude-export-venv
source ~/claude-export-venv/bin/activate
pip install claude-conversation-extractor
```

**"Permission denied" accessing Claude Code logs in ~/.claude/projects**
```bash
# Check Claude Code logs permissions
ls -la ~/.claude/projects/

# Fix permissions to export Claude conversations
chmod -R u+r ~/.claude/projects/
```

## Troubleshooting Claude Export Issues

### Can't Find Claude Code Conversations?

**Check if Claude Code logs exist:**
```bash
# macOS/Linux
ls -la ~/.claude/projects/

# Windows
dir %USERPROFILE%\.claude\projects\
```

**No ~/.claude/projects folder?**
- You must use Claude Code at least once before exporting
- The folder contains JSONL files with your conversations

### "No module named 'claude_conversation_extractor'"

The Claude export tool uses commands, not Python imports:
```bash
claude-extract           # Main command to export Claude conversations
claude-extract --help    # Show all export options
claude-extract --list    # List all Claude Code conversations
```

### Python Version Issues for Claude Export

**Check Python version:**
```bash
python3 --version  # Needs 3.8+ to export Claude Code logs
```

**Install newer Python:**
- macOS: `brew install python@3.11`
- Windows: Download from [python.org](https://python.org)
- Linux: Use package manager or pyenv

### Claude Export Command Not Found After Installation

**Verify Claude Conversation Extractor installation:**
```bash
# With pipx
pipx list | grep claude

# With pip
pip show claude-conversation-extractor
```

**Add to PATH manually for Claude export:**
- macOS/Linux: Add `~/.local/bin` to PATH
- Windows: Add `%APPDATA%\Python\Scripts` to PATH

## Alternative Methods to Export Claude Conversations

### Install from Source (Claude Code Export Development)

```bash
# Clone Claude Conversation Extractor repository
git clone https://github.com/ZeroSumQuant/claude-conversation-extractor.git
cd claude-conversation-extractor

# Install Claude export tool in development mode
pip install -e .
```

### Using UV (Fast Claude Export Installation)

```bash
# Install uv package manager
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Claude Conversation Extractor
uv pip install claude-conversation-extractor
```

### Manual Python Script to Export Claude Code

If installation fails, run the extractor directly:
```bash
# Download the Claude export script
curl -O https://raw.githubusercontent.com/ZeroSumQuant/claude-conversation-extractor/main/extract_claude_logs.py

# Run to export Claude conversations
python3 extract_claude_logs.py
```

## Verify Claude Conversation Extractor Installation

After installing the Claude Code export tool:

```bash
# Check if Claude export command exists
which claude-extract  # macOS/Linux
where claude-extract  # Windows

# Test Claude Conversation Extractor
claude-extract --version
claude-extract --help

# List your Claude Code conversations
claude-extract --list

# Export recent Claude sessions
claude-extract --recent 5
```

If you see your Claude conversations listed, the export tool is working!

## Still Can't Export Claude Code Conversations?

1. **Check Claude Code is installed**: The tool exports from ~/.claude/projects
2. **Verify Python 3.8+**: Run `python3 --version`
3. **Try pipx**: Solves most installation issues
4. **Report issues**: https://github.com/ZeroSumQuant/claude-conversation-extractor/issues

Include these details when reporting Claude export problems:
- Operating system
- Python version
- Error message
- Installation method used
- Output of `ls ~/.claude/projects/` (or Windows equivalent)

## Quick Reference - Claude Export Commands

After installation, these commands export Claude Code conversations:
- `claude-extract` - Interactive UI to export Claude conversations (recommended)
- `claude-search` - Real-time search across all Claude conversations
- `claude-extract --all` - Export all Claude Code conversations at once
- `claude-extract --recent 10` - Export last 10 Claude sessions
- `claude-start` - Alias for claude-extract (same functionality)

---

**Keywords**: install claude conversation extractor, export claude code conversations, claude code export tool, extract claude logs, backup claude sessions, claude jsonl to markdown, ~/.claude/projects export, pip install claude-conversation-extractor

Remember: pipx is the best way to install the Claude Code export tool. It handles everything automatically and works on all platforms where Claude Code runs.