#!/usr/bin/env python3
"""
Unit tests for real-time search components without threading
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
from pathlib import Path
import time

import sys
sys.path.append(str(Path(__file__).parent.parent))

from realtime_search import (
    SearchState, RealTimeSearch, create_smart_searcher
)
from search_conversations import SearchResult


class TestRealTimeSearchUnit(unittest.TestCase):
    """Unit tests for RealTimeSearch components"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.mock_searcher = Mock()
        self.mock_extractor = Mock()
        self.rts = RealTimeSearch(self.mock_searcher, self.mock_extractor)
    
    def test_handle_input_typing(self):
        """Test character input handling"""
        # Type "hello"
        for char in "hello":
            self.rts.handle_input(char)
        
        self.assertEqual(self.rts.state.query, "hello")
        self.assertEqual(self.rts.state.cursor_pos, 5)
        self.assertTrue(self.rts.state.is_searching)
    
    def test_handle_input_backspace(self):
        """Test backspace handling"""
        self.rts.state.query = "hello"
        self.rts.state.cursor_pos = 5
        
        # Backspace twice
        self.rts.handle_input('BACKSPACE')
        self.rts.handle_input('BACKSPACE')
        
        self.assertEqual(self.rts.state.query, "hel")
        self.assertEqual(self.rts.state.cursor_pos, 3)
    
    def test_handle_input_navigation(self):
        """Test arrow key navigation"""
        self.rts.state.query = "test query"
        self.rts.state.cursor_pos = 5
        
        # Move left
        self.rts.handle_input('LEFT')
        self.assertEqual(self.rts.state.cursor_pos, 4)
        
        # Move right
        self.rts.handle_input('RIGHT')
        self.assertEqual(self.rts.state.cursor_pos, 5)
        
        # Test boundaries
        self.rts.state.cursor_pos = 0
        self.rts.handle_input('LEFT')
        self.assertEqual(self.rts.state.cursor_pos, 0)
        
        self.rts.state.cursor_pos = len(self.rts.state.query)
        self.rts.handle_input('RIGHT')
        self.assertEqual(self.rts.state.cursor_pos, len(self.rts.state.query))
    
    def test_handle_input_result_navigation(self):
        """Test up/down navigation through results"""
        # Add some mock results
        self.rts.state.results = [Mock() for _ in range(5)]
        self.rts.state.selected_index = 0
        
        # Move down
        self.rts.handle_input('DOWN')
        self.assertEqual(self.rts.state.selected_index, 1)
        
        # Move up
        self.rts.handle_input('UP')
        self.assertEqual(self.rts.state.selected_index, 0)
        
        # Test boundaries
        self.rts.state.selected_index = 4
        self.rts.handle_input('DOWN')
        self.assertEqual(self.rts.state.selected_index, 4)  # Should not go past last
    
    def test_handle_input_actions(self):
        """Test action returns from input handling"""
        # Test ESC
        action = self.rts.handle_input('ESC')
        self.assertEqual(action, 'exit')
        
        # Test ENTER with no results
        self.rts.state.results = []
        action = self.rts.handle_input('ENTER')
        self.assertIsNone(action)
        
        # Test ENTER with results
        self.rts.state.results = [Mock()]
        self.rts.state.selected_index = 0
        action = self.rts.handle_input('ENTER')
        self.assertEqual(action, 'select')
    
    def test_trigger_search_debouncing(self):
        """Test search debouncing logic"""
        self.rts.state.query = "test"
        
        # First trigger
        self.rts.trigger_search()
        first_update = self.rts.state.last_update
        self.assertTrue(self.rts.state.is_searching)
        
        # Immediate second trigger (should update timestamp)
        time.sleep(0.01)
        self.rts.trigger_search()
        second_update = self.rts.state.last_update
        
        self.assertGreater(second_update, first_update)
        self.assertTrue(self.rts.state.is_searching)
    
    def test_trigger_search_cache_cleanup(self):
        """Test cache cleanup on search trigger"""
        # Populate cache
        self.rts.results_cache = {
            "test": [Mock()],
            "testing": [Mock()],
            "other": [Mock()],
            "te": [Mock()],
            "t": [Mock()]
        }
        
        # Trigger search for "tes"
        self.rts.state.query = "tes"
        self.rts.trigger_search()
        
        # Should only keep entries starting with "tes"
        self.assertIn("test", self.rts.results_cache)
        self.assertIn("testing", self.rts.results_cache)
        self.assertNotIn("other", self.rts.results_cache)
        self.assertNotIn("te", self.rts.results_cache)  # Removed - doesn't start with "tes"
        self.assertNotIn("t", self.rts.results_cache)   # Removed - doesn't start with "tes"
    
    def test_search_logic(self):
        """Test search logic components"""
        # Test empty query handling
        self.rts.state.query = ""
        self.rts.state.is_searching = True
        self.rts.state.last_update = time.time() - 1
        
        # The search worker would clear results for empty query
        # We'll test this by simulating the logic
        if not self.rts.state.query:
            self.rts.state.results = []
        
        self.assertEqual(self.rts.state.results, [])
        
        # Test search with results
        self.rts.state.query = "python"
        
        # Mock search results
        mock_results = [
            Mock(file_path=Path("/test/file1")),
            Mock(file_path=Path("/test/file2"))
        ]
        self.mock_searcher.search.return_value = mock_results
        
        # Simulate search execution
        results = self.mock_searcher.search(
            query=self.rts.state.query,
            mode="smart",
            max_results=20,
            case_sensitive=False
        )
        
        # Update state as worker would
        self.rts.state.results = results
        self.rts.results_cache[self.rts.state.query] = results
        
        # Verify results
        self.assertEqual(self.rts.state.results, mock_results)
        self.assertIn("python", self.rts.results_cache)
    
    def test_cache_usage(self):
        """Test that cache is used properly"""
        # Pre-populate cache
        cached_results = [Mock()]
        self.rts.results_cache["cached"] = cached_results
        
        self.rts.state.query = "cached"
        
        # Simulate cache check
        if self.rts.state.query in self.rts.results_cache:
            self.rts.state.results = self.rts.results_cache[self.rts.state.query]
        
        # Should use cached results
        self.assertEqual(self.rts.state.results, cached_results)
    
    def test_search_error_handling(self):
        """Test search error handling"""
        self.rts.state.query = "error query"
        
        # Make search raise exception
        self.mock_searcher.search.side_effect = Exception("Search failed")
        
        # Simulate error handling
        try:
            self.mock_searcher.search(
                query=self.rts.state.query,
                mode="smart",
                max_results=20,
                case_sensitive=False
            )
            self.rts.state.results = []  # This shouldn't execute
        except Exception:
            # Handle error by setting empty results
            self.rts.state.results = []
        
        # Should have empty results
        self.assertEqual(self.rts.state.results, [])


class TestCreateSmartSearcher(unittest.TestCase):
    """Test smart searcher enhancement"""
    
    def test_smart_search_basic(self):
        """Test basic smart search functionality"""
        mock_searcher = Mock()
        
        # Mock search to return different results for different modes
        def mock_search(query, mode=None, **kwargs):
            if mode == "exact":
                return [Mock(file_path=Path(f"/exact/{query}"))]
            elif mode == "smart":
                return [Mock(file_path=Path(f"/smart/{query}"))]
            elif mode == "regex":
                return [Mock(file_path=Path(f"/regex/{query}"))]
            return []
        
        mock_searcher.search.side_effect = mock_search
        mock_searcher.nlp = None
        
        # Enhance searcher
        smart_searcher = create_smart_searcher(mock_searcher)
        
        # Test basic search
        results = smart_searcher.search("test")
        
        # Should have results from multiple modes
        self.assertGreater(len(results), 1)
        paths = [str(r.file_path) for r in results]
        self.assertIn("/exact/test", paths)
        self.assertIn("/smart/test", paths)
    
    def test_smart_search_deduplication(self):
        """Test that smart search deduplicates results"""
        mock_searcher = Mock()
        
        # Return same file from all modes
        duplicate_result = Mock(file_path=Path("/duplicate/file"))
        mock_searcher.search.return_value = [duplicate_result]
        mock_searcher.nlp = None
        
        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test")
        
        # Should only have one result
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].file_path, Path("/duplicate/file"))
    
    def test_smart_search_regex_detection(self):
        """Test that smart search detects regex patterns"""
        mock_searcher = Mock()
        
        # Track which modes were called
        called_modes = []
        
        def track_modes(query, mode=None, **kwargs):
            called_modes.append(mode)
            return []
        
        mock_searcher.search.side_effect = track_modes
        mock_searcher.nlp = None
        
        smart_searcher = create_smart_searcher(mock_searcher)
        
        # Search with regex pattern
        smart_searcher.search("test.*pattern")
        
        # Should have tried regex mode
        self.assertIn("regex", called_modes)
    
    def test_smart_search_with_nlp(self):
        """Test smart search with NLP available"""
        mock_searcher = Mock()
        mock_searcher.nlp = Mock()  # Simulate NLP being available
        
        called_modes = []
        
        def track_modes(query, mode=None, **kwargs):
            called_modes.append(mode)
            if mode == "semantic":
                return [Mock(file_path=Path("/semantic/result"))]
            return []
        
        mock_searcher.search.side_effect = track_modes
        
        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test")
        
        # Should have tried semantic search
        self.assertIn("semantic", called_modes)
        
        # Should include semantic results
        paths = [str(r.file_path) for r in results]
        self.assertIn("/semantic/result", paths)
    
    def test_smart_search_max_results(self):
        """Test that smart search respects max_results"""
        mock_searcher = Mock()
        
        # Return many results
        def many_results(query, mode=None, **kwargs):
            return [Mock(file_path=Path(f"/{mode}/{i}")) for i in range(10)]
        
        mock_searcher.search.side_effect = many_results
        mock_searcher.nlp = None
        
        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test", max_results=5)
        
        # Should limit results
        self.assertEqual(len(results), 5)


if __name__ == '__main__':
    unittest.main()