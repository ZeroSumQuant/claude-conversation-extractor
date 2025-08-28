# Contributing to Claude Conversation Extractor - Help Export Claude Code Conversations

Thank you for helping improve the #1 tool to export Claude Code conversations! 🎉

## How to Contribute to Claude Export Tool

### Report Bugs in Claude Conversation Extraction

Found an issue exporting Claude Code logs? Before reporting, please:
- Check [existing issues](https://github.com/ZeroSumQuant/claude-conversation-extractor/issues)
- Search for your error message

When reporting Claude export bugs, include:
- Operating system and version
- Python version (`python3 --version`)
- Claude Code version
- Steps that caused the export failure
- Error messages when trying to extract Claude conversations
- Output of `ls -la ~/.claude/projects/` (to verify Claude logs exist)

### Suggest Features for Claude Code Export

Have ideas to improve exporting Claude conversations? We'd love to hear them!

Enhancement suggestions should include:
- Clear description of the feature
- How it helps users export Claude Code logs better
- Example use case for Claude conversation extraction
- Possible implementation approach

Popular requests:
- Export Claude conversations to different formats (PDF, HTML)
- Batch export with filters
- Integration with note-taking apps
- Automated Claude Code backup

### Submit Code to Improve Claude Export

#### Setup Development Environment

```bash
# Fork and clone Claude Conversation Extractor
git clone https://github.com/your-username/claude-conversation-extractor.git
cd claude-conversation-extractor

# Create virtual environment for Claude export development
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install Claude extractor in development mode
pip install -e .

# Install development dependencies
pip install -r requirements-dev.txt
```

#### Development Workflow for Claude Export Features

1. Create feature branch:
   ```bash
   git checkout -b feature/better-claude-export
   ```

2. Make changes to improve Claude Code export

3. Test your changes:
   ```bash
   # Run tests
   pytest
   
   # Test Claude export functionality
   python extract_claude_logs.py --list
   
   # Check code quality
   flake8 . --max-line-length=100
   black . --check
   ```

4. Commit using conventional commits:
   ```bash
   git commit -m "feat: add PDF export for Claude conversations"
   ```

5. Push and create PR:
   ```bash
   git push origin feature/better-claude-export
   ```

## Code Standards for Claude Export Tool

### Python Style Guide
- Follow PEP 8 with 100-character line limit
- Use black for formatting
- Use type hints where helpful
- Document functions that handle Claude Code logs

### Testing Claude Conversation Export
- Write tests for new export features
- Test edge cases (empty conversations, corrupt JSONL)
- Mock file system operations
- Aim for >90% coverage on new code

### Documentation for Claude Export Features
- Update README.md for user-facing changes
- Add docstrings to new functions
- Include examples of exporting Claude conversations
- Update CHANGELOG.md

## Pull Request Guidelines for Claude Extractor

### PR Title Format
Use conventional commit format:
- `feat: add real-time search for Claude conversations`
- `fix: handle missing Claude Code logs gracefully`
- `docs: improve Claude export installation guide`
- `perf: speed up bulk Claude conversation export`

### PR Description Template
```markdown
## What This PR Does
Describe how this improves exporting Claude Code conversations

## Why This Change
Explain the benefit to users extracting Claude logs

## Testing
- [ ] Tested on macOS/Linux/Windows
- [ ] Added/updated tests
- [ ] Verified Claude export still works
- [ ] Documentation updated

## Screenshots (if UI changes)
Show before/after of Claude export interface
```

## Areas Needing Help

### High Priority - Claude Export Improvements
- **Windows testing**: Ensure Claude export works on all Windows versions
- **Performance**: Optimize large Claude conversation exports
- **Search**: Improve semantic search for Claude Code logs
- **UI**: Enhance interactive mode for easier Claude extraction

### Documentation - Help Users Export Claude Code
- Installation guides for specific platforms
- Video tutorials showing Claude export process
- Troubleshooting guides for common issues
- Translations for non-English Claude Code users

### Testing - Ensure Reliable Claude Export
- Cross-platform testing
- Edge case handling
- Performance benchmarks
- User experience testing

## Community Guidelines

### Be Respectful
- Welcome newcomers wanting to export Claude conversations
- Provide constructive feedback
- Help others troubleshoot Claude export issues

### Be Patient
- This is a volunteer project
- Reviews may take time
- Focus on helping Claude Code users

### Be Helpful
- Share your Claude export use cases
- Help test PRs on your platform
- Spread the word about the tool

## Questions?

- Open an issue for Claude export questions
- Discuss in PRs for implementation details
- Check README for user documentation

Thank you for helping make Claude Conversation Extractor the best tool to export Claude Code logs! Your contributions help thousands of users preserve their AI conversations.

---

**Keywords**: contribute claude conversation extractor, help export claude code, improve claude export tool, claude code logs development, submit PR claude extractor