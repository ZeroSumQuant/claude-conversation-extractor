# Changelog

All notable changes to Claude Conversation Extractor will be documented in
this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Professional badges to README for PyPI, downloads, and stars
- Comprehensive test suite (coming soon)

## [1.0.0] - 2025-05-25

### 🎉 Initial Release

- Initial release of Claude Conversation Extractor
- Extract conversations from Claude Code's JSONL storage format
- Convert conversations to clean, readable markdown files
- List all available Claude sessions with metadata
- Extract single conversations with `--extract N`
- Extract multiple recent conversations with `--recent N`
- Extract all conversations with `--all`
- Custom output directory support with `--output`
- Zero dependencies - uses only Python standard library
- Cross-platform support (Windows, macOS, Linux)
- Professional documentation with demo GIF
- PyPI packaging for easy installation via pip
- GitHub Actions CI/CD pipeline
- 100% code quality (flake8, black, markdown lint)

### Security

- Read-only access to conversation files
- No external data transmission
- Safe handling of file paths and user data

### Documentation

- Comprehensive README with installation and usage instructions
- CONTRIBUTING guidelines for developers
- Recording guide for demo updates
- MIT License with appropriate disclaimers

[Unreleased]: https://github.com/ZeroSumQuant/claude-conversation-extractor/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ZeroSumQuant/claude-conversation-extractor/releases/tag/v1.0.0
