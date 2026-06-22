#!/usr/bin/env python3
"""
Focused tests for GitHub Copilot CLI session support.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Add parent directory to path before local imports
sys.path.append(str(Path(__file__).parent.parent))

from extract_claude_logs import ClaudeConversationExtractor, main  # noqa: E402
from search_conversations import ConversationSearcher  # noqa: E402


class TestCopilotSupport(unittest.TestCase):
    """Test extraction and search for Copilot CLI sessions."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.home = Path(self.temp_dir)
        self.output_dir = self.home / "exports"
        self.session_dir = (
            self.home
            / ".copilot"
            / "session-state"
            / "11111111-2222-3333-4444-555555555555"
        )
        self.session_dir.mkdir(parents=True)
        self.events_file = self.session_dir / "events.jsonl"

        events = [
            {
                "type": "session.start",
                "timestamp": "2026-06-21T10:00:00Z",
                "data": {
                    "sessionId": self.session_dir.name,
                    "context": {"cwd": "/tmp/demo-repo"},
                },
            },
            {
                "type": "user.message",
                "timestamp": "2026-06-21T10:01:00Z",
                "data": {"content": "Search for this Copilot session"},
            },
            {
                "type": "assistant.message",
                "timestamp": "2026-06-21T10:01:02Z",
                "data": {
                    "content": "I found the requested session.",
                    "reasoningText": "Summarized the session content.",
                },
            },
            {
                "type": "tool.execution_start",
                "timestamp": "2026-06-21T10:01:03Z",
                "data": {"toolName": "view", "arguments": {"path": "README.md"}},
            },
            {
                "type": "tool.execution_complete",
                "timestamp": "2026-06-21T10:01:04Z",
                "data": {"success": True, "result": {"output": "file content"}},
            },
        ]

        self.events_file.write_text(
            "\n".join(json.dumps(event) for event in events), encoding="utf-8"
        )

    def tearDown(self):
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_copilot_default_output_directory(self):
        """Copilot mode should default to a Copilot logs destination."""
        with patch("pathlib.Path.home", return_value=self.home):
            extractor = ClaudeConversationExtractor(source="copilot")

        self.assertEqual(extractor.output_dir, self.home / "Desktop" / "Copilot logs")

    def test_find_copilot_sessions(self):
        """Copilot mode should find events.jsonl session files."""
        with patch("pathlib.Path.home", return_value=self.home):
            extractor = ClaudeConversationExtractor(self.output_dir, source="copilot")
            sessions = extractor.find_sessions()

        self.assertEqual(sessions, [self.events_file])

    def test_extract_copilot_conversation(self):
        """Copilot mode should extract user and assistant messages."""
        with patch("pathlib.Path.home", return_value=self.home):
            extractor = ClaudeConversationExtractor(self.output_dir, source="copilot")
            conversation = extractor.extract_conversation(
                self.events_file, detailed=True, thinking=True
            )

        self.assertEqual(len(conversation), 4)
        self.assertEqual(conversation[0]["role"], "user")
        self.assertEqual(conversation[0]["content"], "Search for this Copilot session")
        self.assertEqual(conversation[1]["role"], "assistant")
        self.assertIn("I found the requested session.", conversation[1]["content"])
        self.assertIn("💭 Thinking:", conversation[1]["content"])
        self.assertEqual(conversation[2]["role"], "tool_use")
        self.assertEqual(conversation[3]["role"], "tool_result")

    def test_save_copilot_markdown_uses_copilot_branding(self):
        """Copilot exports should use Copilot titles and filename prefixes."""
        with patch("pathlib.Path.home", return_value=self.home):
            extractor = ClaudeConversationExtractor(self.output_dir, source="copilot")
            conversation = extractor.extract_conversation(self.events_file)
            output = extractor.save_as_markdown(conversation, self.session_dir.name)

        self.assertTrue(output.name.startswith("copilot-conversation-"))
        content = output.read_text(encoding="utf-8")
        self.assertIn("# Copilot Conversation Log", content)
        self.assertIn("## 🤖 Copilot", content)

    def test_search_copilot_sessions(self):
        """ConversationSearcher should search Copilot event streams."""
        with patch("pathlib.Path.home", return_value=self.home):
            searcher = ConversationSearcher(source="copilot")
            results = searcher.search("requested session", mode="exact")

        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].conversation_id, self.session_dir.name)
        self.assertEqual(results[0].speaker, "assistant")

    def test_main_copilot_flag_uses_copilot_source(self):
        """The --copilot flag should instantiate the extractor in Copilot mode."""
        with patch("sys.argv", ["extract_claude_logs.py", "--copilot", "--list"]):
            with patch("extract_claude_logs.ClaudeConversationExtractor") as mock_class:
                mock_class.return_value.list_recent_sessions.return_value = []
                main()

        mock_class.assert_called_once_with(None, source="copilot")


if __name__ == "__main__":
    unittest.main()
