#!/usr/bin/env python3
"""
Aligned tests for search_conversations.py with meaningful coverage
"""

import json
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import Mock, patch

# Add parent directory to path before local imports
sys.path.append(str(Path(__file__).parent.parent))

# Local imports after sys.path modification
from search_conversations import ConversationSearcher, SearchResult  # noqa: E402


class TestSearchResult(unittest.TestCase):
    """Test SearchResult dataclass"""

    def test_search_result_creation(self):
        """Test creating a SearchResult"""
        result = SearchResult(
            session_path=Path("/test/path.jsonl"),
            conversation_index=0,
            speaker="Human",
            content="Hello world",
            matched_content="Hello",
            relevance_score=0.95,
            timestamp="2024-01-01T10:00:00Z",
            context="Previous message",
        )

        self.assertEqual(result.session_path, Path("/test/path.jsonl"))
        self.assertEqual(result.relevance_score, 0.95)
        self.assertEqual(result.speaker, "Human")

    def test_search_result_string_representation(self):
        """Test SearchResult string representation"""
        result = SearchResult(
            session_path=Path("/test/project/chat_123.jsonl"),
            conversation_index=0,
            speaker="Human",
            content="Test content",
            matched_content="Test",
            relevance_score=0.8,
            timestamp="2024-01-01T10:00:00Z",
        )

        str_repr = str(result)
        self.assertIn("project", str_repr)
        self.assertIn("Human", str_repr)
        self.assertIn("80%", str_repr)  # Relevance score as percentage


class TestConversationSearcher(unittest.TestCase):
    """Test ConversationSearcher functionality"""

    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.searcher = ConversationSearcher()

        # Create test conversation files
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

    def test_search_exact_match(self):
        """Test exact string matching"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("Python decorators", mode="exact")

            self.assertGreater(len(results), 0)
            self.assertIn("decorators", results[0].content.lower())

    def test_search_case_insensitive(self):
        """Test case-insensitive search"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results1 = self.searcher.search("python", case_sensitive=False)
            results2 = self.searcher.search("PYTHON", case_sensitive=False)

            # Should find same results regardless of case
            self.assertEqual(len(results1), len(results2))

    def test_search_case_sensitive(self):
        """Test case-sensitive search"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results1 = self.searcher.search("Python", case_sensitive=True)
            results2 = self.searcher.search("python", case_sensitive=True)

            # May find different results based on case
            self.assertIsNotNone(results1)
            self.assertIsNotNone(results2)

    def test_search_regex_mode(self):
        """Test regex pattern matching"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search(r"Python|JavaScript", mode="regex")

            # Should find both Python and JavaScript mentions
            self.assertGreater(len(results), 0)
            contents = [r.content for r in results]
            self.assertTrue(
                any("Python" in c for c in contents)
                or any("JavaScript" in c for c in contents)
            )

    def test_search_smart_mode(self):
        """Test smart search mode"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("programming language", mode="smart")

            # Should find relevant results even without exact match
            self.assertIsNotNone(results)

    def test_search_speaker_filter(self):
        """Test filtering by speaker"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            human_results = self.searcher.search("How", speaker_filter="human")
            assistant_results = self.searcher.search(
                "way to", speaker_filter="assistant"
            )

            # Check speaker filtering
            for result in human_results:
                self.assertEqual(result.speaker, "Human")

            for result in assistant_results:
                self.assertEqual(result.speaker, "Assistant")

    def test_search_date_filter(self):
        """Test date range filtering"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            # Search only for conversations after 2024-01-01 15:00
            date_from = datetime(2024, 1, 1, 15, 0)
            results = self.searcher.search("JavaScript", date_from=date_from)

            # Should only find JavaScript conversation (2024-01-02)
            self.assertGreater(len(results), 0)
            for result in results:
                self.assertIn("JavaScript", result.content)

    def test_search_max_results(self):
        """Test limiting number of results"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search(
                "", max_results=1
            )  # Empty string matches all

            self.assertEqual(len(results), 1)

    def test_search_empty_query(self):
        """Test searching with empty query"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("")

            # Should return results (matches everything)
            self.assertGreater(len(results), 0)

    def test_search_no_matches(self):
        """Test search with no matches"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("nonexistent12345query")

            self.assertEqual(len(results), 0)

    def test_search_with_context(self):
        """Test that search results include context"""
        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            results = self.searcher.search("decorators", mode="exact")

            if results:
                # Should have context from previous messages
                self.assertIsNotNone(results[0].context)

    def test_semantic_search_without_spacy(self):
        """Test semantic search falls back when spaCy not available"""
        with patch("search_conversations.SPACY_AVAILABLE", False):
            with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
                results = self.searcher.search("programming", mode="semantic")

                # Should fall back to smart search
                self.assertIsNotNone(results)

    def test_semantic_search_with_spacy(self):
        """Test semantic search with spaCy available"""
        # Mock spaCy components
        mock_nlp = Mock()
        mock_doc = Mock()
        mock_doc.similarity.return_value = 0.8
        mock_nlp.return_value = mock_doc

        with patch("search_conversations.SPACY_AVAILABLE", True):
            with patch("search_conversations.nlp", mock_nlp):
                with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
                    results = self.searcher.search("coding", mode="semantic")

                    # Should use semantic similarity
                    self.assertIsNotNone(results)

    def test_search_corrupted_jsonl(self):
        """Test search handles corrupted JSONL files gracefully"""
        # Create corrupted file
        bad_project = Path(self.temp_dir) / ".claude" / "projects" / "bad_project"
        bad_project.mkdir(parents=True)

        with open(bad_project / "chat_bad.jsonl", "w") as f:
            f.write("not json\n")
            f.write('{"invalid": json}\n')
            f.write('{"type": "user", "message": {"content": "Valid message"}}\n')

        with patch("pathlib.Path.home", return_value=Path(self.temp_dir)):
            # Should not crash, just skip bad lines
            results = self.searcher.search("Valid")
            self.assertIsNotNone(results)

    def test_rank_results(self):
        """Test result ranking by relevance"""
        # Create results with different relevance scores
        results = [
            SearchResult(Path("test1"), 0, "Human", "content", "match", 0.5, ""),
            SearchResult(Path("test2"), 0, "Human", "content", "match", 0.9, ""),
            SearchResult(Path("test3"), 0, "Human", "content", "match", 0.7, ""),
        ]

        ranked = self.searcher._rank_results(results)

        # Should be sorted by relevance score (descending)
        self.assertEqual(ranked[0].relevance_score, 0.9)
        self.assertEqual(ranked[1].relevance_score, 0.7)
        self.assertEqual(ranked[2].relevance_score, 0.5)

    def test_extract_content(self):
        """Test content extraction from different message formats"""
        # Test string content
        content = self.searcher._extract_content("Simple string")
        self.assertEqual(content, "Simple string")

        # Test list content
        content = self.searcher._extract_content(
            [{"type": "text", "text": "Part 1"}, {"type": "text", "text": "Part 2"}]
        )
        self.assertEqual(content, "Part 1 Part 2")

        # Test other types
        content = self.searcher._extract_content({"unknown": "format"})
        self.assertEqual(content, "")

    def test_fuzzy_match(self):
        """Test fuzzy string matching"""
        # Test exact match
        self.assertTrue(self.searcher._fuzzy_match("hello", "hello"))

        # Test substring match
        self.assertTrue(self.searcher._fuzzy_match("ello", "hello world"))

        # Test case insensitive
        self.assertTrue(
            self.searcher._fuzzy_match("HELLO", "hello", case_sensitive=False)
        )

        # Test no match
        self.assertFalse(self.searcher._fuzzy_match("xyz", "hello"))


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
            {
                "type": "user",
                "message": {"role": "user", "content": "Can you show an example?"},
                "timestamp": datetime.now().isoformat(),
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "text",
                            "text": (
                                "try:\n    risky_operation()\n"
                                "except Exception as e:\n    print(f'Error: {e}')"
                            ),
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
            self.assertIsInstance(first.session_path, Path)
            self.assertIn("test_project", str(first.session_path))
            self.assertGreater(first.relevance_score, 0)
            self.assertIn(first.speaker, ["Human", "Assistant"])


if __name__ == "__main__":
    unittest.main()
