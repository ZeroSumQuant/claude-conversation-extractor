from pathlib import Path


SUPPORTED_SOURCES = ("claude", "copilot")


def normalize_source(source: str) -> str:
    """Normalize a conversation source identifier."""
    if source in SUPPORTED_SOURCES:
        return source
    return "claude"


def get_source_config(source: str):
    """Return source-specific paths and labels."""
    source = normalize_source(source)
    home = Path.home()

    base = {
        "claude": {
            "source": "claude",
            "display_name": "Claude",
            "assistant_name": "Claude",
            "session_dir": home / ".claude" / "projects",
            "cache_dir": home / ".claude" / ".search_cache",
            "default_output_dirs": [
                home / "Desktop" / "Claude logs",
                home / "Documents" / "Claude logs",
                home / "Claude logs",
            ],
            "default_output_fallback": Path.cwd() / "claude-logs",
            "interactive_output_name": "Claude Conversations",
            "conversation_prefix": "claude-conversation",
            "conversation_title": "Claude Conversation Log",
            "assistant_heading": "## 🤖 Claude",
            "assistant_terminal_name": "CLAUDE",
            "no_sessions_message": "No Claude sessions found in ~/.claude/projects/",
            "session_glob": "*.jsonl",
        },
        "copilot": {
            "source": "copilot",
            "display_name": "Copilot",
            "assistant_name": "Copilot",
            "session_dir": home / ".copilot" / "session-state",
            "cache_dir": home / ".copilot" / ".search_cache",
            "default_output_dirs": [
                home / "Desktop" / "Copilot logs",
                home / "Documents" / "Copilot logs",
                home / "Copilot logs",
            ],
            "default_output_fallback": Path.cwd() / "copilot-logs",
            "interactive_output_name": "Copilot Conversations",
            "conversation_prefix": "copilot-conversation",
            "conversation_title": "Copilot Conversation Log",
            "assistant_heading": "## 🤖 Copilot",
            "assistant_terminal_name": "COPILOT",
            "no_sessions_message": "No Copilot sessions found in ~/.copilot/session-state/",
            "session_glob": "events.jsonl",
        },
    }

    return base[source]
