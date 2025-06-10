#!/usr/bin/env python3
"""
Comprehensive tests for extract_claude_logs.py to achieve 100% coverage
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Add parent directory to path before local imports
sys.path.append(str(Path(__file__).parent.parent))

# Local imports after sys.path modification
from extract_claude_logs import ClaudeConversationExtractor, main  # noqa: E402


class TestClaudeConversationExtractorComprehensive(unittest.TestCase):
    """Comprehensive tests for ClaudeConversationExtractor"""

    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.extractor = ClaudeConversationExtractor(self.temp_dir)

        # Create test Claude directory structure
        self.claude_dir = Path(self.temp_dir) / ".claude" / "projects"
        self.claude_dir.mkdir(parents=True)

    def tearDown(self):
        """Clean up test environment"""
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_init_with_custom_output(self):
        """Test initialization with custom output directory"""
        custom_dir = Path(self.temp_dir) / "custom"
        extractor = ClaudeConversationExtractor(str(custom_dir))
        self.assertEqual(extractor.output_dir, custom_dir)

    def test_init_with_none_output(self):
        """Test initialization with None output directory"""
        with patch("extract_claude_logs.Path.home", return_value=Path(self.temp_dir)):
            extractor = ClaudeConversationExtractor(None)
            # Should use Desktop or Documents
            self.assertTrue(
                "Desktop" in str(extractor.output_dir)
                or "Documents" in str(extractor.output_dir)
            )

    def test_find_sessions_empty(self):
        """Test finding sessions when none exist"""
        with patch("extract_claude_logs.Path.home", return_value=Path(self.temp_dir)):
            sessions = self.extractor.find_sessions()
            self.assertEqual(sessions, [])

    def test_find_sessions_with_files(self):
        """Test finding sessions with JSONL files"""
        # Create test JSONL files
        project_dir = self.claude_dir / "test_project"
        project_dir.mkdir()

        chat_file1 = project_dir / "chat_123.jsonl"
        chat_file2 = project_dir / "chat_456.jsonl"
        chat_file1.write_text("{}")
        chat_file2.write_text("{}")

        with patch("extract_claude_logs.Path.home", return_value=Path(self.temp_dir)):
            sessions = self.extractor.find_sessions()
            self.assertEqual(len(sessions), 2)

    def test_extract_text_content_string(self):
        """Test extracting text from string content"""
        content = "Simple text content"
        result = self.extractor._extract_text_content(content)
        self.assertEqual(result, content)

    def test_extract_text_content_list(self):
        """Test extracting text from list content"""
        content = [
            {"type": "text", "text": "Part 1"},
            {"type": "text", "text": "Part 2"},
            {"type": "image", "data": "..."},  # Should be ignored
        ]
        result = self.extractor._extract_text_content(content)
        self.assertEqual(result, "Part 1\n\nPart 2")

    def test_extract_text_content_empty(self):
        """Test extracting text from empty content"""
        self.assertEqual(self.extractor._extract_text_content([]), "")
        self.assertEqual(self.extractor._extract_text_content(""), "")
        self.assertEqual(self.extractor._extract_text_content(None), "")

    def test_save_as_markdown_basic(self):
        """Test saving conversation as markdown"""
        conversation = [
            {"role": "user", "content": "Hello", "timestamp": "2024-01-01T10:00:00Z"},
            {
                "role": "assistant",
                "content": "Hi there!",
                "timestamp": "2024-01-01T10:01:00Z",
            },
        ]

        output_path = self.extractor.save_as_markdown(conversation, "test_session")

        self.assertTrue(output_path.exists())
        content = output_path.read_text()
        self.assertIn("Hello", content)
        self.assertIn("Hi there!", content)
        self.assertIn("User", content)
        self.assertIn("Claude", content)

    def test_save_as_markdown_with_code(self):
        """Test saving conversation with code blocks"""
        conversation = [
            {"role": "user", "content": "Write Python hello world", "timestamp": ""},
            {
                "role": "assistant",
                "content": "```python\nprint('Hello, World!')\n```",
                "timestamp": "",
            },
        ]

        output_path = self.extractor.save_as_markdown(conversation, "code_session")
        content = output_path.read_text()

        # Should preserve code blocks
        self.assertIn("```python", content)
        self.assertIn("print('Hello, World!')", content)

    def test_list_sessions(self):
        """Test listing sessions with details"""
        # Create test file
        project_dir = self.claude_dir / "test_project"
        project_dir.mkdir()
        chat_file = project_dir / "chat_test.jsonl"
        chat_file.write_text('{"type": "test"}')

        with patch("extract_claude_logs.Path.home", return_value=Path(self.temp_dir)):
            with patch("builtins.print") as mock_print:
                sessions = self.extractor.list_sessions(limit=5)

                # Should print session details
                self.assertTrue(
                    any(
                        "test_project" in str(call)
                        for call in mock_print.call_args_list
                    )
                )
                self.assertEqual(len(sessions), 1)

    def test_extract_multiple_success(self):
        """Test extracting multiple sessions"""
        # Create test sessions
        sessions = [
            Path(self.temp_dir) / "session1.jsonl",
            Path(self.temp_dir) / "session2.jsonl",
        ]

        for session in sessions:
            session.write_text(
                json.dumps(
                    {
                        "type": "user",
                        "message": {"role": "user", "content": "Test"},
                        "timestamp": "2024-01-01T10:00:00Z",
                    }
                )
            )

        with patch("builtins.print"):
            success, total = self.extractor.extract_multiple(sessions, [0, 1])

        self.assertEqual(success, 2)
        self.assertEqual(total, 2)

    def test_extract_multiple_with_invalid_index(self):
        """Test extracting with invalid indices"""
        sessions = [Path(self.temp_dir) / "session.jsonl"]

        with patch("builtins.print"):
            success, total = self.extractor.extract_multiple(
                sessions, [5]
            )  # Invalid index

        self.assertEqual(success, 0)
        self.assertEqual(total, 1)

    def test_extract_recent(self):
        """Test extracting recent conversations"""
        # Mock find_sessions to return test sessions
        mock_sessions = [Path(self.temp_dir) / f"session{i}.jsonl" for i in range(10)]

        with patch.object(self.extractor, "find_sessions", return_value=mock_sessions):
            with patch.object(
                self.extractor, "extract_multiple", return_value=(3, 3)
            ) as mock_extract:
                self.extractor.extract_recent(3)

                # Should extract first 3 sessions
                mock_extract.assert_called_once()
                args = mock_extract.call_args[0]
                self.assertEqual(args[1], [0, 1, 2])

    def test_extract_all(self):
        """Test extracting all conversations"""
        mock_sessions = [Path(self.temp_dir) / f"session{i}.jsonl" for i in range(5)]

        with patch.object(self.extractor, "find_sessions", return_value=mock_sessions):
            with patch.object(
                self.extractor, "extract_multiple", return_value=(5, 5)
            ) as mock_extract:
                self.extractor.extract_all()

                # Should extract all sessions
                mock_extract.assert_called_once()
                args = mock_extract.call_args[0]
                self.assertEqual(args[1], list(range(5)))

    def test_main_list_command(self):
        """Test main function with --list"""
        with patch("sys.argv", ["extract_claude_logs.py", "--list"]):
            with patch.object(ClaudeConversationExtractor, "list_sessions"):
                main()

    def test_main_extract_single(self):
        """Test main function with --extract"""
        with patch("sys.argv", ["extract_claude_logs.py", "--extract", "1"]):
            with patch.object(
                ClaudeConversationExtractor,
                "find_sessions",
                return_value=[Path("test.jsonl")],
            ):
                with patch.object(ClaudeConversationExtractor, "extract_multiple"):
                    main()

    def test_main_extract_multiple_comma(self):
        """Test main function with comma-separated indices"""
        with patch("sys.argv", ["extract_claude_logs.py", "--extract", "1,2,3"]):
            with patch.object(
                ClaudeConversationExtractor,
                "find_sessions",
                return_value=[Path(f"test{i}.jsonl") for i in range(5)],
            ):
                with patch.object(
                    ClaudeConversationExtractor, "extract_multiple"
                ) as mock_extract:
                    main()
                    # Should extract indices 0, 1, 2 (1-based to 0-based)
                    args = mock_extract.call_args[0]
                    self.assertEqual(args[1], [0, 1, 2])

    def test_main_recent(self):
        """Test main function with --recent"""
        with patch("sys.argv", ["extract_claude_logs.py", "--recent", "5"]):
            with patch.object(
                ClaudeConversationExtractor, "extract_recent"
            ) as mock_recent:
                main()
                mock_recent.assert_called_once_with(5)

    def test_main_all(self):
        """Test main function with --all"""
        with patch("sys.argv", ["extract_claude_logs.py", "--all"]):
            with patch.object(ClaudeConversationExtractor, "extract_all") as mock_all:
                main()
                mock_all.assert_called_once()

    def test_main_interactive(self):
        """Test main function with --interactive"""
        with patch("sys.argv", ["extract_claude_logs.py", "--interactive"]):
            with patch("extract_claude_logs.InteractiveUI") as mock_ui:
                main()
                mock_ui.assert_called_once()
                mock_ui.return_value.run.assert_called_once()

    def test_main_export(self):
        """Test main function with --export"""
        with patch("sys.argv", ["extract_claude_logs.py", "--export", "logs"]):
            with patch("extract_claude_logs.InteractiveUI") as mock_ui:
                main()
                mock_ui.assert_called_once_with("logs")

    def test_main_search(self):
        """Test main function with --search"""
        with patch("sys.argv", ["extract_claude_logs.py", "--search", "test query"]):
            with patch("extract_claude_logs.ConversationSearcher") as mock_searcher:
                with patch("builtins.print"):
                    main()
                    mock_searcher.return_value.search.assert_called_once()

    def test_main_search_with_filters(self):
        """Test main function with search filters"""
        with patch(
            "sys.argv",
            [
                "extract_claude_logs.py",
                "--search",
                "test",
                "--search-speaker",
                "human",
                "--search-date-from",
                "2024-01-01",
                "--case-sensitive",
            ],
        ):
            with patch("extract_claude_logs.ConversationSearcher") as mock_searcher:
                with patch("builtins.print"):
                    main()

                    # Check search was called with correct parameters
                    search_call = mock_searcher.return_value.search.call_args
                    self.assertEqual(search_call[1]["speaker_filter"], "human")
                    self.assertTrue(search_call[1]["case_sensitive"])

    def test_main_no_args(self):
        """Test main function with no arguments (should show help)"""
        with patch("sys.argv", ["extract_claude_logs.py"]):
            with patch("argparse.ArgumentParser.print_help") as mock_help:
                with patch("sys.exit"):
                    main()
                    mock_help.assert_called_once()

    def test_extract_conversation_with_errors(self):
        """Test extract_conversation with file read errors"""
        bad_file = Path(self.temp_dir) / "bad.jsonl"
        bad_file.write_text("not json\n{bad json}\n")

        with patch("builtins.print"):
            conversation = self.extractor.extract_conversation(bad_file)
            # Should return empty conversation on error
            self.assertEqual(conversation, [])

    def test_output_dir_fallback(self):
        """Test output directory fallback when Desktop/Documents don't exist"""
        with patch("extract_claude_logs.Path.home", return_value=Path(self.temp_dir)):
            with patch("extract_claude_logs.Path.exists", return_value=False):
                with patch(
                    "extract_claude_logs.Path.cwd", return_value=Path(self.temp_dir)
                ):
                    extractor = ClaudeConversationExtractor(None)
                    # Should fall back to current directory
                    self.assertIn("Claude logs", str(extractor.output_dir))


if __name__ == "__main__":
    unittest.main()
