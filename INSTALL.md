# Installation Guide - Claude Conversation Extractor

This guide provides detailed installation instructions for all platforms. If you're experiencing installation issues, you're in the right place!

## Table of Contents
- [Quick Install (Recommended)](#quick-install-recommended)
- [Platform-Specific Instructions](#platform-specific-instructions)
  - [macOS](#macos)
  - [Windows](#windows)
  - [Linux](#linux)
- [Troubleshooting](#troubleshooting)
- [Alternative Installation Methods](#alternative-installation-methods)
- [Verifying Installation](#verifying-installation)

## Quick Install (Recommended)

The easiest way to install is using pipx, which creates an isolated environment for the tool:

```bash
# Install pipx first (see platform-specific sections below)
pipx install claude-conversation-extractor
```

## Platform-Specific Instructions

### macOS

#### Method 1: Using pipx (Recommended)

```bash
# Install pipx via Homebrew
brew install pipx
pipx ensurepath

# Restart terminal or run:
source ~/.zshrc  # or ~/.bash_profile

# Install the tool
pipx install claude-conversation-extractor
```

#### Method 2: Using pip with venv

```bash
# Create a virtual environment
python3 -m venv claude-env
source claude-env/bin/activate

# Install the tool
pip install claude-conversation-extractor

# Create an alias for easy access
echo 'alias claude-logs="source ~/claude-env/bin/activate && claude-logs"' >> ~/.zshrc
source ~/.zshrc
```

#### Common macOS Issues

**"command not found" after installation**
```bash
# Check if ~/.local/bin is in PATH
echo $PATH | grep -q ~/.local/bin || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**"externally managed environment" error**
- This is why we recommend pipx - it handles this automatically
- Alternative: use `pip install --user --break-system-packages` (not recommended)

### Windows

#### Method 1: Using pipx (Recommended)

```batch
REM Install pipx
py -m pip install --user pipx
py -m pipx ensurepath

REM Restart Command Prompt or PowerShell

REM Install the tool
pipx install claude-conversation-extractor
```

#### Method 2: Using pip with venv

```batch
REM Create virtual environment
py -m venv claude-env
claude-env\Scripts\activate

REM Install the tool
pip install claude-conversation-extractor
```

#### PowerShell Users

```powershell
# If you get execution policy errors:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Install pipx
python -m pip install --user pipx
python -m pipx ensurepath

# Restart PowerShell

# Install the tool
pipx install claude-conversation-extractor
```

#### Common Windows Issues

**"'claude-logs' is not recognized as an internal or external command"**
1. Ensure Python Scripts folder is in PATH:
   ```batch
   REM Add to PATH (adjust username)
   setx PATH "%PATH%;C:\Users\YourUsername\AppData\Local\Programs\Python\Python311\Scripts"
   ```
2. Restart Command Prompt

**"Access is denied" errors**
- Run Command Prompt as Administrator
- Or use `--user` flag: `pip install --user claude-conversation-extractor`

### Linux

#### Ubuntu/Debian

```bash
# Install pipx
sudo apt update
sudo apt install pipx
pipx ensurepath

# Restart terminal or run:
source ~/.bashrc

# Install the tool
pipx install claude-conversation-extractor
```

#### Fedora/RHEL

```bash
# Install pipx
sudo dnf install pipx

# Install the tool
pipx install claude-conversation-extractor
```

#### Arch Linux

```bash
# Install pipx
sudo pacman -S python-pipx

# Install the tool
pipx install claude-conversation-extractor
```

#### Common Linux Issues

**"externally managed environment" (Ubuntu 23.04+, Fedora 38+)**
```bash
# This is why pipx is recommended!
# If you must use pip:
python3 -m venv ~/claude-venv
source ~/claude-venv/bin/activate
pip install claude-conversation-extractor
```

**Permission denied when accessing Claude logs**
```bash
# Check permissions
ls -la ~/.claude/projects/

# If needed, fix permissions
chmod -R u+r ~/.claude/projects/
```

## Troubleshooting

### Issue: "No module named 'claude_conversation_extractor'"

**Solution**: The tool uses entry points, not module imports. Use the commands:
```bash
claude-logs           # Main command
claude-logs --help    # Show help
```

### Issue: "Python 3.8+ required"

**Check Python version:**
```bash
python3 --version
```

**Install newer Python:**
- macOS: `brew install python@3.11`
- Windows: Download from [python.org](https://python.org)
- Linux: Use your package manager or pyenv

### Issue: Installation succeeds but command not found

**Check installation location:**
```bash
# With pipx
pipx list

# With pip
pip show claude-conversation-extractor
```

**Add to PATH manually:**
- macOS/Linux: Add `~/.local/bin` to PATH
- Windows: Add `%APPDATA%\Python\Scripts` to PATH

### Issue: "error: Microsoft Visual C++ 14.0 is required" (Windows)

This shouldn't happen with our tool (no compiled dependencies), but if it does:
1. Install Visual Studio Build Tools
2. Or use pre-compiled wheels: `pip install --only-binary :all: claude-conversation-extractor`

## Alternative Installation Methods

### From Source

```bash
# Clone repository
git clone https://github.com/ZeroSumQuant/claude-conversation-extractor.git
cd claude-conversation-extractor

# Install in development mode
pip install -e .
```

### Using UV (Fast Python Package Manager)

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install tool
uv pip install claude-conversation-extractor
```

### Using Poetry

```bash
# In the cloned repository
poetry install
poetry run claude-logs
```

## Verifying Installation

After installation, verify everything works:

```bash
# Check if command is available
which claude-logs  # macOS/Linux
where claude-logs  # Windows

# Test the tool
claude-logs --version
claude-logs --help

# Try listing conversations
claude-logs --list
```

If you see your conversations listed, installation was successful!

## Still Having Issues?

1. **Check our FAQ**: See README.md for common questions
2. **GitHub Issues**: Search existing issues or create a new one
3. **Provide Details**: When reporting issues, include:
   - Operating system and version
   - Python version (`python3 --version`)
   - Installation method used
   - Complete error message
   - Output of `pip list` or `pipx list`

## Entry Points Reference

The tool provides these command-line entry points:
- `claude-logs` - Main interactive interface (recommended)
- `claude-extract` - Legacy command (kept for compatibility)
- `claude-start` - Quick start alias

All commands provide the same functionality, use whichever you prefer!

---

Remember: pipx is almost always the best installation method. It avoids conflicts, handles PATH automatically, and works on all platforms.