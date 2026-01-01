#!/usr/bin/env python3
"""
Tests for search_conversations.py - aligned with actual API
"""

import json
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

# Add parent directory to path before local imports
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from search_conversations import ConversationSearcher, SearchResult  # noqa: E402


class TestSearchResult(unittest.TestCase):
    """Test SearchResult dataclass"""

    def test_search_result_creation(self):
        """Test creating a SearchResult with correct API"""
        result = SearchResult(
            file_path=Path("/test/path.jsonl"),
            conversation_id="conv_123",
            matched_content="Hello",
            context="Previous message context",
            speaker="human",
            relevance_score=0.95,
            timestamp=datetime(2024, 1, 1, 10, 0, 0),
            line_number=5,
        )

        self.assertEqual(result.file_path, Path("/test/path.jsonl"))
        self.assertEqual(result.relevance_score, 0.95)
        self.assertEqual(result.speaker, "human")
        self.assertEqual(result.conversation_id, "conv_123")
        self.assertEqual(result.line_number, 5)

    def test_search_result_string_representation(self):
        """Test SearchResult string representation"""
        result = SearchResult(
            file_path=Path("/test/project/chat_123.jsonl"),
            conversation_id="conv_456",
            matched_content="Test",
            context="Test content for display",
            speaker="human",
            relevance_score=0.8,
            timestamp=datetime(2024, 1, 1, 10, 0, 0),
        )

        str_repr = str(result)
        # Check that string representation contains expected info
        self.assertIn("chat_123.jsonl", str_repr)
        self.assertIn("Human", str_repr)  # Speaker title-cased
        self.assertIn("80%", str_repr)  # Relevance score as percentage

    def test_search_result_defaults(self):
        """Test SearchResult with default values"""
        result = SearchResult(
            file_path=Path("/test/path.jsonl"),
            conversation_id="conv_123",
            matched_content="Hello",
            context="Context",
            speaker="assistant",
        )

        self.assertIsNone(result.timestamp)
        self.assertEqual(result.relevance_score, 0.0)
        self.assertEqual(result.line_number, 0)


class TestConversationSearcher(unittest.TestCase):
    """Test ConversationSearcher functionality"""

    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.searcher = ConversationSearcher()
        self.create_test_conversations()

    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def create_test_conversations(self):
        """Create test conversation files"""
        # Project 1: Python discussion
        project1 = Path(self.temp_dir) / ".claude" / "projects" / "python_project"
        project1.mkdir(parents=True)

        conv1 = [
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": "How do I use Python decorators?",
                },
                "timestamp": "2024-01-01T10:00:00Z",
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "text",
                            "text": "Python decorators are a way to modify functions.",
                        }
                    ],
                },
                "timestamp": "2024-01-01T10:01:00Z",
            },
        ]

        with open(project1 / "chat_001.jsonl", "w") as f:
            for msg in conv1:
                f.write(json.dumps(msg) + "\n")

        # Project 2: JavaScript discussion
        project2 = Path(self.temp_dir) / ".claude" / "projects" / "js_project"
        project2.mkdir(parents=True)

        conv2 = [
            {
                "type": "user",
                "message": {"role": "user", "content": "Explain JavaScript promises"},
                "timestamp": "2024-01-02T10:00:00Z",
            }
        ]

        with open(project2 / "chat_002.jsonl", "w") as f:
            for msg in conv2:
                f.write(json.dumps(msg) + "\n")

    def test_searcher_initialization(self):
        """Test searcher initializes correctly"""
        searcher = ConversationSearcher()
        self.assertIsNotNone(searcher)

    def test_search_returns_list(self):
        """Test search returns a list"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("Python", mode="exact")
            self.assertIsInstance(results, list)

    def test_search_exact_match(self):
        """Test exact string matching"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("Python decorators", mode="exact")
            self.assertGreater(len(results), 0)
            # Results should have correct structure
            for result in results:
                self.assertIsInstance(result, SearchResult)
                self.assertIsInstance(result.file_path, Path)

    def test_search_no_matches(self):
        """Test search with no matches"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("nonexistent12345query")
            self.assertEqual(len(results), 0)

    def test_search_max_results(self):
        """Test limiting number of results"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("", max_results=1)
            self.assertLessEqual(len(results), 1)

    def test_search_case_insensitive(self):
        """Test case-insensitive search"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results1 = self.searcher.search("python", case_sensitive=False)
            results2 = self.searcher.search("PYTHON", case_sensitive=False)
            # Should find same number of results regardless of case
            self.assertEqual(len(results1), len(results2))

    def test_extract_content_string(self):
        """Test content extraction from string"""
        content = self.searcher._extract_content(
            {"message": {"content": "Simple string"}}
        )
        self.assertEqual(content, "Simple string")

    def test_extract_content_list(self):
        """Test content extraction from list format"""
        entry = {
            "message": {
                "content": [
                    {"type": "text", "text": "Part 1"},
                    {"type": "text", "text": "Part 2"},
                ]
            }
        }
        content = self.searcher._extract_content(entry)
        self.assertIn("Part 1", content)
        self.assertIn("Part 2", content)

    def test_search_handles_corrupted_files(self):
        """Test search handles corrupted JSONL files gracefully"""
        # Create corrupted file
        bad_project = Path(self.temp_dir) / ".claude" / "projects" / "bad_project"
        bad_project.mkdir(parents=True)

        with open(bad_project / "chat_bad.jsonl", "w") as f:
            f.write("not json\n")
            f.write('{"invalid": json}\n')

        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            # Should not crash, just skip bad files
            results = self.searcher.search("test")
            self.assertIsNotNone(results)


class TestSearchIntegration(unittest.TestCase):
    """Integration tests for search functionality"""

    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.searcher = ConversationSearcher()

    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_end_to_end_search_workflow(self):
        """Test complete search workflow"""
        # Create realistic conversation
        project = Path(self.temp_dir) / ".claude" / "projects" / "test_project"
        project.mkdir(parents=True)

        conversation = [
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": "How do I handle errors in Python?",
                },
                "timestamp": datetime.now().isoformat(),
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "text",
                            "text": "You can use try-except blocks for error handling.",
                        }
                    ],
                },
                "timestamp": datetime.now().isoformat(),
            },
        ]

        with open(project / "chat_test.jsonl", "w") as f:
            for msg in conversation:
                f.write(json.dumps(msg) + "\n")

        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            # Search for error handling
            results = self.searcher.search("error handling", mode="smart")

            self.assertGreater(len(results), 0)

            # Verify results have expected structure
            first = results[0]
            self.assertIsInstance(first.file_path, Path)
            self.assertIn("test_project", str(first.file_path))


if __name__ == "__main__":
    unittest.main()
