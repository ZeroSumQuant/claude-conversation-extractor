#!/usr/bin/env python3
"""Setup script for Claude Conversation Extractor"""

import atexit
from pathlib import Path

from setuptools import setup
from setuptools.command.install import install


class PostInstallCommand(install):
    """Post-installation for installation mode."""

    def run(self):
        install.run(self)

        # Print helpful messages after installation
        def print_success_message():
            print("\n🎉 Installation complete!")
            print("\n📋 Quick Start Commands:")
            print("  claude-start         # Interactive UI with logo & real-time search")
            print("  claude-extract       # CLI for extraction & searching")
            print("  claude-search        # Search and view conversations")
            print("\n⭐ If you find this tool helpful, please star us on GitHub:")
            print("   https://github.com/ZeroSumQuant/claude-conversation-extractor")
            print("\nThank you for using Claude Conversation Extractor! 🚀\n")

        # Register to run after pip finishes
        atexit.register(print_success_message)


# Read the README for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text(encoding="utf-8")

setup(
    name="claude-conversation-extractor",
    version="1.1.2",
    author="Dustin Kirby",
    author_email="",  # Contact via GitHub
    description=(
        "Export Claude Code conversations from ~/.claude/projects. "
        "Extract, search, and backup Claude chat history to markdown files."
    ),
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/ZeroSumQuant/claude-conversation-extractor",
    project_urls={
        "Bug Tracker": (
            "https://github.com/ZeroSumQuant/claude-conversation-extractor/issues"
        ),
        "Documentation": (
            "https://github.com/ZeroSumQuant/claude-conversation-extractor#readme"
        ),
        "Source": "https://github.com/ZeroSumQuant/claude-conversation-extractor",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: End Users/Desktop",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Text Processing :: Markup :: Markdown",
        "Topic :: Communications :: Chat",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: Utilities",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Environment :: Console",
    ],
    python_requires=">=3.8",
    package_dir={"": "src"},
    py_modules=[
        "extract_claude_logs",
        "interactive_ui",
        "search_conversations",
        "realtime_search",
        "search_cli",
    ],
    entry_points={
        "console_scripts": [
            "claude-extract=extract_claude_logs:launch_interactive",  # Primary command
            "claude-logs=extract_claude_logs:launch_interactive",     # Kept for backward compatibility
            "claude-start=extract_claude_logs:launch_interactive",    # Alternative alias
            "claude-search=search_cli:main",                          # Direct search command
        ],
    },
    cmdclass={
        "install": PostInstallCommand,
    },
    install_requires=[],  # No dependencies!
    keywords=(
        "export-claude-code-conversations claude-conversation-extractor "
        "claude-code-export-tool backup-claude-code-logs save-claude-chat-history "
        "claude-jsonl-to-markdown extract-claude-sessions claude-code-no-export-button "
        "where-are-claude-code-logs-stored claude-terminal-logs anthropic-claude-code "
        "search-claude-conversations claude-code-logs-location ~/.claude/projects "
        "export-claude-conversations extract-claude-code backup-claude-sessions"
    ),
)
