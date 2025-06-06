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
            print("\n📋 Quick Start:")
            print("  claude-extract --export logs    # Launch interactive UI")
            print("  claude-start                    # Quick shortcut")
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
    version="1.1.0",
    author="Dustin Kirby",
    author_email="dustin@zerosumquant.com",
    description="Extract clean conversation logs from Claude Code's internal storage",
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
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Text Processing :: Markup :: Markdown",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.8",
    py_modules=["extract_claude_logs", "interactive_ui"],
    entry_points={
        "console_scripts": [
            "claude-extract=extract_claude_logs:main",
            "claude-start=extract_claude_logs:launch_interactive",
        ],
    },
    cmdclass={
        "install": PostInstallCommand,
    },
    install_requires=[],  # No dependencies!
    keywords="claude anthropic conversation export markdown logs cli",
)
