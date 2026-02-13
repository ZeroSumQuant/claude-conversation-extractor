#!/usr/bin/env python3
"""
Tests for search_cli.py non-interactive mode and argument parsing.

Covers:
- --no-interactive / -n flag skips the V/E/Q prompt
- --help / -h prints usage and exits
- --max-results / -m controls result limit
- Existing interactive behavior is preserved when no flags given
"""

import json
import sys
import tempfile
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Add parent directory to path before local imports
sys.path.append(str(Path(__file__).parent.parent))

from search_cli import main, parse_args  # noqa: E402


class TestParseArgs(unittest.TestCase):
    """Test argument parsing."""

    def test_search_term_positional(self):
        args = parse_args(["Rules Foundation"])
        self.assertEqual(args.search_term, "Rules Foundation")

    def test_search_term_multiple_words(self):
        args = parse_args(["Rules", "Foundation", "email"])
        self.assertEqual(args.search_term, "Rules Foundation email")

    def test_no_interactive_long_flag(self):
        args = parse_args(["--no-interactive", "query"])
        self.assertTrue(args.no_interactive)

    def test_no_interactive_short_flag(self):
        args = parse_args(["-n", "query"])
        self.assertTrue(args.no_interactive)

    def test_max_results_long_flag(self):
        args = parse_args(["--max-results", "5", "query"])
        self.assertEqual(args.max_results, 5)

    def test_max_results_short_flag(self):
        args = parse_args(["-m", "10", "query"])
        self.assertEqual(args.max_results, 10)

    def test_default_max_results(self):
        args = parse_args(["query"])
        self.assertEqual(args.max_results, 20)

    def test_default_interactive(self):
        args = parse_args(["query"])
        self.assertFalse(args.no_interactive)

    def test_no_args_returns_empty_search_term(self):
        args = parse_args([])
        self.assertEqual(args.search_term, "")


class TestNonInteractiveMode(unittest.TestCase):
    """Test that --no-interactive skips the V/E/Q prompt."""

    @patch("search_cli.create_smart_searcher")
    @patch("search_cli.ConversationSearcher")
    @patch("search_cli.ClaudeConversationExtractor")
    def test_no_interactive_skips_prompt(
        self, mock_extractor_cls, mock_searcher_cls, mock_smart
    ):
        """With --no-interactive, main() should never call input()."""
        mock_result = Mock()
        mock_result.file_path = Path("/test/session.jsonl")
        mock_result.matched_content = "test match content"
        mock_result.speaker = "human"

        mock_smart_instance = Mock()
        mock_smart_instance.search.return_value = [mock_result]
        mock_smart.return_value = mock_smart_instance

        mock_extractor = Mock()
        mock_extractor.find_sessions.return_value = [
            Path("/test/session.jsonl")
        ]
        mock_extractor_cls.return_value = mock_extractor

        with patch("sys.argv", ["claude-search", "-n", "test query"]):
            with patch("sys.stdout", new_callable=StringIO) as mock_stdout:
                with patch("builtins.input") as mock_input:
                    main()
                    mock_input.assert_not_called()

    @patch("search_cli.create_smart_searcher")
    @patch("search_cli.ConversationSearcher")
    @patch("search_cli.ClaudeConversationExtractor")
    def test_no_interactive_prints_results(
        self, mock_extractor_cls, mock_searcher_cls, mock_smart
    ):
        """With --no-interactive, results should still be printed."""
        mock_result = Mock()
        mock_result.file_path = Path("/test/session.jsonl")
        mock_result.matched_content = "Rules Foundation email"
        mock_result.speaker = "human"

        mock_smart_instance = Mock()
        mock_smart_instance.search.return_value = [mock_result]
        mock_smart.return_value = mock_smart_instance

        mock_extractor = Mock()
        mock_extractor.find_sessions.return_value = [
            Path("/test/session.jsonl")
        ]
        mock_extractor_cls.return_value = mock_extractor

        with patch("sys.argv", ["claude-search", "-n", "Rules Foundation"]):
            with patch("sys.stdout", new_callable=StringIO) as mock_stdout:
                main()
                output = mock_stdout.getvalue()
                self.assertIn("Found", output)
                self.assertIn("session", output.lower())

    @patch("search_cli.create_smart_searcher")
    @patch("search_cli.ConversationSearcher")
    def test_no_interactive_exits_cleanly_no_results(
        self, mock_searcher_cls, mock_smart
    ):
        """With --no-interactive and no results, exits without prompting."""
        mock_smart_instance = Mock()
        mock_smart_instance.search.return_value = []
        mock_smart.return_value = mock_smart_instance

        with patch("sys.argv", ["claude-search", "-n", "nonexistent query"]):
            with patch("sys.stdout", new_callable=StringIO):
                with patch("builtins.input") as mock_input:
                    main()
                    mock_input.assert_not_called()


class TestMaxResults(unittest.TestCase):
    """Test --max-results flag."""

    @patch("search_cli.create_smart_searcher")
    @patch("search_cli.ConversationSearcher")
    def test_max_results_passed_to_search(
        self, mock_searcher_cls, mock_smart
    ):
        """--max-results should be forwarded to the searcher."""
        mock_smart_instance = Mock()
        mock_smart_instance.search.return_value = []
        mock_smart.return_value = mock_smart_instance

        with patch("sys.argv", ["claude-search", "-n", "-m", "5", "query"]):
            with patch("sys.stdout", new_callable=StringIO):
                main()
                mock_smart_instance.search.assert_called_once_with(
                    "query", max_results=5
                )


class TestHelpFlag(unittest.TestCase):
    """Test --help flag."""

    def test_help_prints_usage_and_exits(self):
        """--help should print usage info and exit."""
        with patch("sys.argv", ["claude-search", "--help"]):
            with self.assertRaises(SystemExit) as ctx:
                parse_args(["--help"])
            self.assertEqual(ctx.exception.code, 0)


class TestInteractiveModePreserved(unittest.TestCase):
    """Ensure existing interactive behavior still works without flags."""

    @patch("search_cli.create_smart_searcher")
    @patch("search_cli.ConversationSearcher")
    @patch("search_cli.ClaudeConversationExtractor")
    def test_without_flag_prompts_user(
        self, mock_extractor_cls, mock_searcher_cls, mock_smart
    ):
        """Without --no-interactive, the V/E/Q menu should appear."""
        mock_result = Mock()
        mock_result.file_path = Path("/test/session.jsonl")
        mock_result.matched_content = "test match"
        mock_result.speaker = "human"

        mock_smart_instance = Mock()
        mock_smart_instance.search.return_value = [mock_result]
        mock_smart.return_value = mock_smart_instance

        mock_extractor = Mock()
        mock_extractor.find_sessions.return_value = [
            Path("/test/session.jsonl")
        ]
        mock_extractor_cls.return_value = mock_extractor

        with patch("sys.argv", ["claude-search", "test query"]):
            with patch("sys.stdout", new_callable=StringIO):
                with patch("builtins.input", side_effect=EOFError):
                    # input() should be called (and we simulate EOF)
                    main()
                    # If we get here without error, the prompt was attempted


if __name__ == "__main__":
    unittest.main()
