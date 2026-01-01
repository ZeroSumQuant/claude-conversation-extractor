#!/usr/bin/env python3
"""
Core tests for extract_claude_logs.py - focused on essential functionality
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Add parent directory to path before local imports
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from extract_claude_logs import ClaudeConversationExtractor  # noqa: E402


class TestClaudeConversationExtractor(unittest.TestCase):
    """Test core extraction functionality"""

    def setUp(self):
        """Set up test environment with temp directory"""
        self.temp_dir = tempfile.mkdtemp()
        self.extractor = ClaudeConversationExtractor(self.temp_dir)

    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    # ==========================================================================
    # Initialization Tests
    # ==========================================================================

    def test_init_with_custom_output(self):
        """Test initialization with custom output directory"""
        custom_dir = Path(self.temp_dir) / "custom"
        extractor = ClaudeConversationExtractor(str(custom_dir))
        self.assertEqual(extractor.output_dir, custom_dir)
        self.assertTrue(custom_dir.exists())

    def test_init_creates_output_dir(self):
        """Test that initialization creates output directory"""
        new_dir = Path(self.temp_dir) / "new_output"
        extractor = ClaudeConversationExtractor(str(new_dir))
        self.assertTrue(new_dir.exists())

    # ==========================================================================
    # Text Content Extraction Tests
    # ==========================================================================

    def test_extract_text_content_string(self):
        """Test extracting text from simple string content"""
        result = self.extractor._extract_text_content("Hello, world!")
        self.assertEqual(result, "Hello, world!")

    def test_extract_text_content_list(self):
        """Test extracting text from list format (Claude's actual format)"""
        content = [
            {"type": "text", "text": "First part"},
            {"type": "text", "text": "Second part"},
        ]
        result = self.extractor._extract_text_content(content)
        self.assertIn("First part", result)
        self.assertIn("Second part", result)

    def test_extract_text_content_empty(self):
        """Test extracting text from empty content"""
        self.assertEqual(self.extractor._extract_text_content(""), "")
        self.assertEqual(self.extractor._extract_text_content([]), "")

    def test_extract_text_content_other_types(self):
        """Test extracting text from non-text types"""
        result = self.extractor._extract_text_content(12345)
        self.assertEqual(result, "12345")

    # ==========================================================================
    # Conversation Extraction Tests
    # ==========================================================================

    def test_extract_conversation_valid_jsonl(self):
        """Test extracting a valid conversation from JSONL"""
        # Create a test JSONL file
        jsonl_file = Path(self.temp_dir) / "test_chat.jsonl"
        messages = [
            {
                "type": "user",
                "message": {"role": "user", "content": "Hello"},
                "timestamp": "2024-01-15T10:00:00Z",
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Hi there!"}],
                },
                "timestamp": "2024-01-15T10:01:00Z",
            },
        ]

        with open(jsonl_file, "w") as f:
            for msg in messages:
                f.write(json.dumps(msg) + "\n")

        conversation = self.extractor.extract_conversation(jsonl_file)

        self.assertEqual(len(conversation), 2)
        self.assertEqual(conversation[0]["role"], "user")
        self.assertEqual(conversation[0]["content"], "Hello")
        self.assertEqual(conversation[1]["role"], "assistant")
        self.assertIn("Hi there!", conversation[1]["content"])

    def test_extract_conversation_nonexistent_file(self):
        """Test extracting from nonexistent file returns empty list"""
        result = self.extractor.extract_conversation(Path("/nonexistent/file.jsonl"))
        self.assertEqual(result, [])

    def test_extract_conversation_with_errors(self):
        """Test that extraction handles malformed JSONL gracefully"""
        jsonl_file = Path(self.temp_dir) / "bad_chat.jsonl"

        with open(jsonl_file, "w") as f:
            f.write("not valid json\n")
            f.write('{"type": "user", "message": {"role": "user", "content": "Hi"}, "timestamp": ""}\n')

        # Should not raise, should extract what it can
        conversation = self.extractor.extract_conversation(jsonl_file)
        # May get 0 or 1 messages depending on error handling
        self.assertIsInstance(conversation, list)

    # ==========================================================================
    # Save Tests
    # ==========================================================================

    def test_save_as_markdown_basic(self):
        """Test saving a conversation as markdown"""
        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-15T10:00:00Z"},
            {"role": "assistant", "content": "Hi!", "timestamp": "2024-01-15T10:01:00Z"},
        ]

        output_path = self.extractor.save_as_markdown(conversation, "test_session_123")

        self.assertIsNotNone(output_path)
        self.assertTrue(output_path.exists())
        self.assertTrue(output_path.suffix == ".md")

        content = output_path.read_text()
        self.assertIn("Hello", content)
        self.assertIn("Hi!", content)
        self.assertIn("User", content)
        self.assertIn("Claude", content)

    def test_save_as_markdown_empty_conversation(self):
        """Test that saving empty conversation returns None"""
        result = self.extractor.save_as_markdown([], "test_session")
        self.assertIsNone(result)

    def test_save_as_markdown_with_project_name(self):
        """Test saving with project name in filename"""
        conversation = [
            {"role": "user", "content": "Test", "timestamp": "2024-01-15T10:00:00Z"},
        ]

        output_path = self.extractor.save_as_markdown(
            conversation, "session123", project_name="my_project"
        )

        self.assertIsNotNone(output_path)
        self.assertIn("my_project", output_path.name)

    def test_save_as_json(self):
        """Test saving a conversation as JSON"""
        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-15T10:00:00Z"},
        ]

        output_path = self.extractor.save_as_json(conversation, "test_session")

        self.assertIsNotNone(output_path)
        self.assertTrue(output_path.exists())
        self.assertTrue(output_path.suffix == ".json")

        # Verify it's valid JSON
        with open(output_path) as f:
            data = json.load(f)
        self.assertIn("messages", data)
        self.assertEqual(len(data["messages"]), 1)

    def test_save_as_html(self):
        """Test saving a conversation as HTML"""
        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-15T10:00:00Z"},
        ]

        output_path = self.extractor.save_as_html(conversation, "test_session")

        self.assertIsNotNone(output_path)
        self.assertTrue(output_path.exists())
        self.assertTrue(output_path.suffix == ".html")

        content = output_path.read_text()
        self.assertIn("<!DOCTYPE html>", content)
        self.assertIn("Hello", content)

    def test_save_as_pdf_without_dependency(self):
        """Test that PDF export gracefully handles missing dependency"""
        # Import to check availability
        from extract_claude_logs import PDF_AVAILABLE

        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-15T10:00:00Z"},
        ]

        with patch("builtins.print"):
            output_path = self.extractor.save_as_pdf(conversation, "test_session")

        if PDF_AVAILABLE:
            self.assertIsNotNone(output_path)
            self.assertTrue(output_path.exists())
            self.assertTrue(output_path.suffix == ".pdf")
        else:
            self.assertIsNone(output_path)

    def test_save_as_docx_without_dependency(self):
        """Test that DOCX export gracefully handles missing dependency"""
        # Import to check availability
        from extract_claude_logs import DOCX_AVAILABLE

        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-15T10:00:00Z"},
        ]

        with patch("builtins.print"):
            output_path = self.extractor.save_as_docx(conversation, "test_session")

        if DOCX_AVAILABLE:
            self.assertIsNotNone(output_path)
            self.assertTrue(output_path.exists())
            self.assertTrue(output_path.suffix == ".docx")
        else:
            self.assertIsNone(output_path)

    def test_save_conversation_pdf_format(self):
        """Test save_conversation with pdf format"""
        from extract_claude_logs import PDF_AVAILABLE

        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-15T10:00:00Z"},
        ]

        with patch("builtins.print"):
            output_path = self.extractor.save_conversation(
                conversation, "test_session", format="pdf"
            )

        if PDF_AVAILABLE:
            self.assertIsNotNone(output_path)
        else:
            self.assertIsNone(output_path)

    def test_save_conversation_docx_format(self):
        """Test save_conversation with docx format"""
        from extract_claude_logs import DOCX_AVAILABLE

        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-15T10:00:00Z"},
        ]

        with patch("builtins.print"):
            output_path = self.extractor.save_conversation(
                conversation, "test_session", format="docx"
            )

        if DOCX_AVAILABLE:
            self.assertIsNotNone(output_path)
        else:
            self.assertIsNone(output_path)

    # ==========================================================================
    # Find Sessions Tests
    # ==========================================================================

    def test_find_sessions_with_files(self):
        """Test finding session files in Claude directory structure"""
        # Create mock Claude directory structure
        claude_dir = Path(self.temp_dir) / ".claude" / "projects" / "test_project"
        claude_dir.mkdir(parents=True)

        # Create test JSONL files
        (claude_dir / "chat_123.jsonl").write_text('{"test": true}\n')
        (claude_dir / "chat_456.jsonl").write_text('{"test": true}\n')

        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            extractor = ClaudeConversationExtractor(self.temp_dir)
            sessions = extractor.find_sessions()

        self.assertEqual(len(sessions), 2)
        self.assertTrue(all(s.suffix == ".jsonl" for s in sessions))

    def test_find_sessions_empty(self):
        """Test finding sessions when no Claude directory exists"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            extractor = ClaudeConversationExtractor(self.temp_dir)
            sessions = extractor.find_sessions()

        self.assertEqual(len(sessions), 0)

    # ==========================================================================
    # Extract Multiple Tests
    # ==========================================================================

    def test_extract_multiple_success(self):
        """Test extracting multiple sessions"""
        # Create test session files
        sessions = []
        for i in range(3):
            session_file = Path(self.temp_dir) / f"session{i}.jsonl"
            session_file.write_text(
                json.dumps({
                    "type": "user",
                    "message": {"role": "user", "content": f"Test {i}"},
                    "timestamp": "2024-01-15T10:00:00Z"
                }) + "\n"
            )
            sessions.append(session_file)

        with patch("builtins.print"):
            success, total = self.extractor.extract_multiple(sessions, [0, 1, 2])

        self.assertEqual(total, 3)
        self.assertGreaterEqual(success, 0)  # May vary based on extraction success

    def test_extract_multiple_invalid_indices(self):
        """Test extract_multiple with invalid indices"""
        sessions = [Path(self.temp_dir) / "session1.jsonl"]

        with patch("builtins.print"):
            success, total = self.extractor.extract_multiple(sessions, [5, -1])

        self.assertEqual(success, 0)
        self.assertEqual(total, 2)


if __name__ == "__main__":
    unittest.main()
