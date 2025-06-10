#!/usr/bin/env python3
"""
Integration tests for search functionality using sample conversations
"""

import os
import sys
import unittest
from datetime import datetime, timedelta
from pathlib import Path

# Add parent directories to path before local imports
sys.path.append(str(Path(__file__).parent.parent))
sys.path.append(str(Path(__file__).parent))

# Local imports after sys.path modification
from fixtures.sample_conversations import (ConversationFixtures,  # noqa: E402
                                           cleanup_test_environment)
from search_conversations import ConversationSearcher  # noqa: E402


class TestSearchIntegration(unittest.TestCase):
    """Integration tests for search with real sample data"""

    @classmethod
    def setUpClass(cls):
        """Create test environment once for all tests"""
        cls.temp_dir, cls.test_files = ConversationFixtures.create_test_environment()
        cls.search_dir = Path(cls.temp_dir) / ".claude" / "projects"

    @classmethod
    def tearDownClass(cls):
        """Clean up test environment"""
        cleanup_test_environment(cls.temp_dir)

    def setUp(self):
        """Set up each test"""
        self.searcher = ConversationSearcher()
        self.expected_results = ConversationFixtures.get_expected_search_results()

    def test_exact_matches(self):
        """Test exact string matching"""
        test_cases = [
            ("Python errors", ["python_errors"]),
            ("PostgreSQL database", ["database_connection"]),
        ]

        for query, expected_ids in test_cases:
            with self.subTest(query=query):
                results = self.searcher.search(
                    query=query, search_dir=self.search_dir, mode="exact"
                )

                # Extract conversation IDs from file paths
                found_ids = [r.file_path.stem.replace("chat_", "") for r in results]

                # Check if expected conversations were found
                for expected_id in expected_ids:
                    self.assertIn(
                        expected_id,
                        found_ids,
                        f"Expected to find '{expected_id}' for query '{query}'",
                    )

    def test_smart_search(self):
        """Test smart search with partial matches"""
        test_cases = [
            ("python", ["python_errors", "file_operations", "api_requests"]),
            ("error", ["python_errors"]),
            ("file", ["file_operations"]),
            ("API", ["api_requests"]),
        ]

        for query, expected_ids in test_cases:
            with self.subTest(query=query):
                results = self.searcher.search(
                    query=query, search_dir=self.search_dir, mode="smart"
                )

                found_ids = [r.file_path.stem.replace("chat_", "") for r in results]

                # Smart search might find additional matches, so we check minimum set
                for expected_id in expected_ids:
                    self.assertIn(
                        expected_id,
                        found_ids,
                        f"Expected to find '{expected_id}' for query '{query}'",
                    )

    def test_regex_search(self):
        """Test regex pattern matching"""
        test_cases = [
            (r"except \w+Error", ["python_errors"]),
            (r"@[a-zA-Z0-9.-]+", ["regex_patterns"]),
            (r"requests\.\w+", ["api_requests"]),
        ]

        for pattern, expected_ids in test_cases:
            with self.subTest(pattern=pattern):
                results = self.searcher.search(
                    query=pattern, search_dir=self.search_dir, mode="regex"
                )

                found_ids = [r.file_path.stem.replace("chat_", "") for r in results]

                for expected_id in expected_ids:
                    self.assertIn(
                        expected_id,
                        found_ids,
                        f"Expected to find '{expected_id}' for pattern '{pattern}'",
                    )

    def test_case_sensitivity(self):
        """Test case-sensitive vs case-insensitive search"""
        # Case-insensitive (default)
        results_insensitive = self.searcher.search(
            query="PYTHON", search_dir=self.search_dir, case_sensitive=False
        )

        # Case-sensitive
        results_sensitive = self.searcher.search(
            query="PYTHON", search_dir=self.search_dir, case_sensitive=True
        )

        # Case-insensitive should find matches
        self.assertGreater(len(results_insensitive), 0)
        # Case-sensitive should find no matches (our samples use "Python")
        self.assertEqual(len(results_sensitive), 0)

    def test_speaker_filter(self):
        """Test filtering by speaker"""
        # Search for "Python" in human messages only
        human_results = self.searcher.search(
            query="Python", search_dir=self.search_dir, speaker_filter="human"
        )

        # Search for "Python" in assistant messages only
        assistant_results = self.searcher.search(
            query="Python", search_dir=self.search_dir, speaker_filter="assistant"
        )

        # Both should find results
        self.assertGreater(len(human_results), 0)
        self.assertGreater(len(assistant_results), 0)

        # Verify speaker filter worked
        for result in human_results:
            self.assertEqual(result.speaker, "human")

        for result in assistant_results:
            self.assertEqual(result.speaker, "assistant")

    def test_date_filter(self):
        """Test date range filtering"""
        # Set specific modification times for our test files
        base_date = datetime(2024, 1, 15)
        for i, test_file in enumerate(self.test_files):
            # Set files to different dates
            file_time = (base_date + timedelta(days=i)).timestamp()
            os.utime(test_file, (file_time, file_time))

        # Search within date range
        date_from = datetime(2024, 1, 16)
        date_to = datetime(2024, 1, 18)

        results = self.searcher.search(
            query="",  # Empty query to test just date filtering
            search_dir=self.search_dir,
            date_from=date_from,
            date_to=date_to,
        )

        # Due to empty query handling, let's search for something common
        results = self.searcher.search(
            query="the",
            search_dir=self.search_dir,
            date_from=date_from,
            date_to=date_to,
        )

        # Should only find conversations within date range
        for result in results:
            file_mtime = datetime.fromtimestamp(result.file_path.stat().st_mtime)
            self.assertGreaterEqual(file_mtime.date(), date_from.date())
            self.assertLessEqual(file_mtime.date(), date_to.date())

    def test_max_results_limit(self):
        """Test that max_results parameter is respected"""
        # Search for common word to get many results
        results = self.searcher.search(
            query="the", search_dir=self.search_dir, max_results=2
        )

        # Should respect the limit
        self.assertLessEqual(len(results), 2)

    def test_no_results(self):
        """Test search with no matching results"""
        results = self.searcher.search(
            query="javascript rust golang", search_dir=self.search_dir
        )

        self.assertEqual(len(results), 0)

    def test_result_relevance_scoring(self):
        """Test that results are sorted by relevance"""
        results = self.searcher.search(
            query="Python errors", search_dir=self.search_dir
        )

        if len(results) > 1:
            # Check that results are sorted by relevance score (descending)
            for i in range(len(results) - 1):
                self.assertGreaterEqual(
                    results[i].relevance_score,
                    results[i + 1].relevance_score,
                    "Results should be sorted by relevance score",
                )

    def test_search_result_content(self):
        """Test that SearchResult objects contain expected data"""
        results = self.searcher.search(
            query="Python", search_dir=self.search_dir, max_results=1
        )

        self.assertGreater(len(results), 0)
        result = results[0]

        # Verify all required fields are present
        self.assertIsNotNone(result.file_path)
        self.assertIsNotNone(result.conversation_id)
        self.assertIsNotNone(result.matched_content)
        self.assertIsNotNone(result.context)
        self.assertIn(result.speaker, ["human", "assistant"])
        self.assertIsInstance(result.relevance_score, float)
        self.assertGreaterEqual(result.relevance_score, 0.0)
        self.assertLessEqual(result.relevance_score, 1.0)

    def test_context_extraction(self):
        """Test that context is properly extracted around matches"""
        results = self.searcher.search(
            query="try-except", search_dir=self.search_dir, mode="smart"
        )

        if results:
            result = results[0]
            # Context should contain the match
            self.assertTrue(
                "try" in result.context.lower() or "except" in result.context.lower()
            )
            # Context should be a reasonable length
            self.assertGreater(len(result.context), 20)
            self.assertLess(len(result.context), 500)


class TestSearchPerformance(unittest.TestCase):
    """Performance tests for search functionality"""

    def setUp(self):
        """Create a larger test dataset"""
        self.temp_dir, self.test_files = ConversationFixtures.create_test_environment()
        self.search_dir = Path(self.temp_dir) / ".claude" / "projects"
        self.searcher = ConversationSearcher()

    def tearDown(self):
        """Clean up test environment"""
        cleanup_test_environment(self.temp_dir)

    def test_search_performance(self):
        """Test that search completes in reasonable time"""
        import time

        # Time a search operation
        start_time = time.time()
        results = self.searcher.search(query="Python", search_dir=self.search_dir)
        end_time = time.time()

        # Search should complete quickly (under 1 second for small dataset)
        search_time = end_time - start_time
        self.assertLess(
            search_time, 1.0, f"Search took {search_time:.2f}s, expected < 1s"
        )

        # Should find some results
        self.assertGreater(len(results), 0)


if __name__ == "__main__":
    unittest.main()
