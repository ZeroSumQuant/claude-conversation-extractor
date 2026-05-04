# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

`claude-conversation-extractor` is a published PyPI tool (`pip install claude-conversation-extractor`, currently v1.1.2) that reads Claude Code's local JSONL conversation files from `~/.claude/projects/` and exports them as Markdown, JSON, or HTML. It is intentionally **stdlib-only** for runtime; `spacy` is the only optional dependency (semantic search).

**Naming clash to watch for:** the source repo lives at `~/Code/claude-projects/claude-conversation-extractor/`, but the directory the tool *reads* is `~/.claude/projects/` (Claude Code's actual storage). Don't conflate them when writing tests or examples — never point output at `~/.claude/projects/`.

## Common commands

```bash
# Install for development (editable, no deps required)
pip install -e .
pip install -r requirements/dev.txt          # pytest, pytest-cov, black, flake8, bandit

# Run the full test suite
pytest

# Run a single test file or test
pytest tests/test_extractor.py
pytest tests/test_extractor.py::TestClaudeConversationExtractor::test_find_sessions

# Run with coverage (matches the modules CI lints)
pytest --cov=extract_claude_logs --cov=search_conversations \
       --cov=interactive_ui --cov=realtime_search --cov-report=term-missing

# scripts/run_tests.py runs each suite separately and emits htmlcov/index.html
python scripts/run_tests.py

# Lint (CI only lints the main module — see "Known gaps")
flake8 src/extract_claude_logs.py --max-line-length=100
black src/

# Run the tool from a checkout
python -m extract_claude_logs --list                # PYTHONPATH=src first, or run via console script
claude-extract --list                                # after `pip install -e .`
claude-start                                         # interactive UI
claude-search "query"                                # direct search
```

## Architecture

The `src/` directory uses a **flat module layout** (declared via `py_modules` in both `setup.py` and `pyproject.toml`), not a real package. Each file is imported as a top-level module:

| File | Role |
|---|---|
| `src/extract_claude_logs.py` | `ClaudeConversationExtractor` (parses JSONL, writes MD/JSON/HTML), the `main()` argparse CLI, and `launch_interactive()` which dispatches to UI vs. search vs. CLI based on `sys.argv` |
| `src/interactive_ui.py` | `InteractiveUI` — ASCII-art menu, recent sessions list, format chooser |
| `src/realtime_search.py` | `RealTimeSearch` orchestrator + `KeyboardHandler` (raw stdin) + `TerminalDisplay` (ANSI) + `SearchState` + `create_smart_searcher` factory |
| `src/search_conversations.py` | `ConversationSearcher` (full-text indexing/search across JSONL files) + `SearchResult` + `create_search_index` |
| `src/search_cli.py` | `claude-search` entry point — thin wrapper that wires `ConversationSearcher` to `RealTimeSearch` |

**Console scripts** (`pyproject.toml` `[project.scripts]`):
- `claude-extract`, `claude-logs`, `claude-start` all map to `extract_claude_logs:launch_interactive`. The dispatch differentiator is `sys.argv` inside `launch_interactive`.
- `claude-search` maps to `search_cli:main`.

**Dual-import pattern.** Because the layout is flat-modules, every cross-module import in `src/` uses a try/except fallback:
```python
try:
    from .interactive_ui import main as interactive_main
except ImportError:
    from interactive_ui import main as interactive_main
```
The relative form works under `pip install -e .`; the absolute form works when running files directly. Preserve this pattern when adding new cross-module imports.

**Test path injection.** `tests/conftest.py` prepends `src/` to `sys.path` so tests can `import extract_claude_logs` etc. directly. There is no `pytest.ini` / `[tool.pytest.ini_options]` — adding one that overrides `pythonpath` would break the conftest setup.

## Key behaviour to know before changing things

- **Output directory fallback chain.** `ClaudeConversationExtractor.__init__` tries `~/Desktop/Claude logs`, `~/Documents/Claude logs`, `~/Claude logs`, then `./claude-logs`, picking the first writable one. CI/headless environments hit the cwd fallback. Don't assume `~/Desktop` exists.
- **Detailed mode** (`--detailed`) preserves tool use, MCP responses, and system messages. Default mode strips them. Both modes share `extract_conversation()`; the flag changes filtering, not parsing.
- **Format dispatch.** `extract_multiple()` accepts `format` in `{"markdown", "json", "html"}`. Adding a format means a new writer method on `ClaudeConversationExtractor` plus a branch in the dispatch.
- **Read-only contract.** The tool must never modify files under `~/.claude/projects/`. This is a privacy promise in the README and a regression here would be a serious bug.
- **No deps in the runtime path.** Don't add a runtime dependency without explicit discussion — "zero dependencies" is a feature called out repeatedly in the README. Test/dev deps in `requirements/dev.txt` are fine.

## Known gaps (worth knowing if you trip over them)

- **`pyproject.toml` author is "Dustin Kirby"** but recent commits are by David Katz. Don't "fix" attribution without checking with the user first.
- **CI lint covers all of `src/`** but black isn't enforced anywhere. If you run `black src/`, expect a diff against current code; coordinate before committing a sweeping reformat.

## Repo conventions worth respecting

- **Version bumps live in three places:** `pyproject.toml`, `setup.py`, and `src/__init__.py`. Keep them in sync.
- **Test organisation:** there are paired `_aligned`, `_comprehensive`, `_coverage`, `_integration`, `_threading`, `_unit`, `_ui` suites for the search/UI modules. Match the suffix convention when adding tests.
- **No external deps in tests either** — tests use `unittest.mock` and pytest fixtures only.
