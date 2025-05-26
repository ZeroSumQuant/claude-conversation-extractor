"""Tests for Claude Conversation Extractor"""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from extract_claude_logs import ClaudeConversationExtractor  # noqa: E402


class TestClaudeConversationExtractor(unittest.TestCase):
    """Test suite for the Claude Conversation Extractor"""

    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.extractor = ClaudeConversationExtractor(output_dir=self.temp_dir)

    def tearDown(self):
        """Clean up test fixtures"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_initialization(self):
        """Test extractor initialization"""
        self.assertEqual(self.extractor.output_dir, Path(self.temp_dir))
        self.assertTrue(self.extractor.claude_dir.name == "projects")

    def test_extract_text_content_string(self):
        """Test extracting text from string content"""
        content = "Hello, world!"
        result = self.extractor._extract_text_content(content)
        self.assertEqual(result, "Hello, world!")

    def test_extract_text_content_list(self):
        """Test extracting text from list content"""
        content = [
            {"type": "text", "text": "First part"},
            {"type": "text", "text": "Second part"},
            {"type": "other", "text": "Should ignore"}
        ]
        result = self.extractor._extract_text_content(content)
        self.assertEqual(result, "First part\nSecond part")

    def test_extract_text_content_other(self):
        """Test extracting text from other content types"""
        content = {"some": "dict"}
        result = self.extractor._extract_text_content(content)
        self.assertEqual(result, "{'some': 'dict'}")

    def test_save_as_markdown_empty_conversation(self):
        """Test saving empty conversation returns None"""
        result = self.extractor.save_as_markdown([], "test-session")
        self.assertIsNone(result)

    def test_save_as_markdown_with_conversation(self):
        """Test saving conversation to markdown"""
        conversation = [
            {
                "role": "user",
                "content": "Hello Claude",
                "timestamp": "2025-05-25T10:00:00Z"
            },
            {
                "role": "assistant",
                "content": "Hello! How can I help?",
                "timestamp": "2025-05-25T10:00:01Z"
            }
        ]

        result = self.extractor.save_as_markdown(conversation, "test-session-id")

        self.assertIsNotNone(result)
        self.assertTrue(result.exists())
        self.assertTrue(result.name.startswith("claude-conversation-"))
        self.assertTrue(result.name.endswith(".md"))

        # Check content
        content = result.read_text()
        self.assertIn("# Claude Conversation Log", content)
        self.assertIn("Session ID: test-session-id", content)
        self.assertIn("## 👤 User", content)
        self.assertIn("Hello Claude", content)
        self.assertIn("## 🤖 Claude", content)
        self.assertIn("Hello! How can I help?", content)

    def test_extract_conversation_valid_jsonl(self):
        """Test extracting conversation from valid JSONL"""
        # Create a temporary JSONL file
        jsonl_file = Path(self.temp_dir) / "test.jsonl"

        entries = [
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": "Test message"
                },
                "timestamp": "2025-05-25T10:00:00Z"
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Test response"}]
                },
                "timestamp": "2025-05-25T10:00:01Z"
            }
        ]

        with open(jsonl_file, 'w') as f:
            for entry in entries:
                f.write(json.dumps(entry) + '\n')

        conversation = self.extractor.extract_conversation(jsonl_file)

        self.assertEqual(len(conversation), 2)
        self.assertEqual(conversation[0]['role'], 'user')
        self.assertEqual(conversation[0]['content'], 'Test message')
        self.assertEqual(conversation[1]['role'], 'assistant')
        self.assertEqual(conversation[1]['content'], 'Test response')

    def test_extract_conversation_invalid_file(self):
        """Test extracting conversation from non-existent file"""
        fake_path = Path(self.temp_dir) / "non_existent.jsonl"
        conversation = self.extractor.extract_conversation(fake_path)
        self.assertEqual(conversation, [])

    @patch('extract_claude_logs.Path.rglob')
    def test_find_sessions(self, mock_rglob):
        """Test finding session files"""
        # Mock some session files
        mock_files = [
            MagicMock(stat=MagicMock(return_value=MagicMock(st_mtime=1000))),
            MagicMock(stat=MagicMock(return_value=MagicMock(st_mtime=2000))),
            MagicMock(stat=MagicMock(return_value=MagicMock(st_mtime=1500))),
        ]
        mock_rglob.return_value = mock_files

        sessions = self.extractor.find_sessions()

        # Should be sorted by modification time, newest first
        self.assertEqual(len(sessions), 3)
        self.assertEqual(sessions[0].stat().st_mtime, 2000)
        self.assertEqual(sessions[1].stat().st_mtime, 1500)
        self.assertEqual(sessions[2].stat().st_mtime, 1000)


if __name__ == '__main__':
    unittest.main()
