#!/usr/bin/env python3
"""
Tests for threading and UI components of realtime search
These tests are designed to avoid infinite loops by using proper mocking
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
import threading
import time
from pathlib import Path

import sys
sys.path.append(str(Path(__file__).parent.parent))

from realtime_search import RealTimeSearch


class TestRealTimeSearchThreading(unittest.TestCase):
    """Test threading behavior without hanging"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.mock_searcher = Mock()
        self.mock_extractor = Mock()
        self.rts = RealTimeSearch(self.mock_searcher, self.mock_extractor)
    
    def test_process_search_request_no_search(self):
        """Test when no search is pending"""
        self.rts.state.is_searching = False
        
        result = self.rts._process_search_request()
        
        self.assertFalse(result)
        self.mock_searcher.search.assert_not_called()
    
    def test_process_search_request_debounce(self):
        """Test debounce prevents immediate search"""
        self.rts.state.is_searching = True
        self.rts.state.query = "test"
        self.rts.state.last_update = time.time()  # Just updated
        
        result = self.rts._process_search_request()
        
        self.assertFalse(result)  # Should not process due to debounce
        self.mock_searcher.search.assert_not_called()
    
    def test_process_search_request_empty_query(self):
        """Test empty query clears results"""
        self.rts.state.is_searching = True
        self.rts.state.query = ""
        self.rts.state.last_update = time.time() - 1  # Old enough
        self.rts.state.results = [Mock()]  # Has existing results
        
        result = self.rts._process_search_request()
        
        self.assertTrue(result)
        self.assertEqual(self.rts.state.results, [])
        self.mock_searcher.search.assert_not_called()
    
    def test_process_search_request_cached(self):
        """Test cached results are used"""
        cached_results = [Mock()]
        self.rts.results_cache["cached"] = cached_results
        self.rts.state.is_searching = True
        self.rts.state.query = "cached"
        self.rts.state.last_update = time.time() - 1
        
        result = self.rts._process_search_request()
        
        self.assertTrue(result)
        self.assertEqual(self.rts.state.results, cached_results)
        self.mock_searcher.search.assert_not_called()
    
    def test_process_search_request_new_search(self):
        """Test new search is performed"""
        search_results = [Mock()]
        self.mock_searcher.search.return_value = search_results
        self.rts.state.is_searching = True
        self.rts.state.query = "new query"
        self.rts.state.last_update = time.time() - 1
        
        result = self.rts._process_search_request()
        
        self.assertTrue(result)
        self.assertEqual(self.rts.state.results, search_results)
        self.mock_searcher.search.assert_called_once_with(
            query="new query",
            mode="smart",
            max_results=20,
            case_sensitive=False
        )
        self.assertIn("new query", self.rts.results_cache)
    
    def test_process_search_request_error(self):
        """Test search error handling"""
        self.mock_searcher.search.side_effect = Exception("Search failed")
        self.rts.state.is_searching = True
        self.rts.state.query = "error query"
        self.rts.state.last_update = time.time() - 1
        
        result = self.rts._process_search_request()
        
        self.assertTrue(result)
        self.assertEqual(self.rts.state.results, [])
    
    def test_thread_lifecycle(self):
        """Test thread starts and stops properly"""
        # Start thread
        thread = threading.Thread(target=self.rts.search_worker, daemon=True)
        thread.start()
        
        # Verify thread is running
        self.assertTrue(thread.is_alive())
        
        # Thread should stop when main program exits (daemon=True)
        # No need to explicitly stop it in tests


class TestRealTimeSearchUI(unittest.TestCase):
    """Test UI components with proper mocking"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.mock_searcher = Mock()
        self.mock_extractor = Mock()
        self.rts = RealTimeSearch(self.mock_searcher, self.mock_extractor)
    
    @patch('realtime_search.threading.Thread')
    @patch('realtime_search.KeyboardHandler')
    @patch.object(RealTimeSearch, 'display')
    def test_run_exit_key(self, mock_display, mock_keyboard_class, mock_thread_class):
        """Test run exits on ESC key"""
        # Set up mocks
        mock_keyboard = Mock()
        mock_keyboard_class.return_value.__enter__.return_value = mock_keyboard
        mock_keyboard.get_key.side_effect = ['a', 'b', 'c', 'ESC']  # Type abc then ESC
        
        # Mock thread to prevent actual thread start
        mock_thread = Mock()
        mock_thread_class.return_value = mock_thread
        
        # Run should exit on ESC
        result = self.rts.run()
        
        self.assertIsNone(result)
        mock_thread.start.assert_called_once()
        mock_display.clear_screen.assert_called()
    
    @patch('realtime_search.threading.Thread')
    @patch('realtime_search.KeyboardHandler')
    @patch('realtime_search.TerminalDisplay')
    def test_run_select_result(self, mock_display_class, mock_keyboard_class, mock_thread_class):
        """Test run returns selected file path"""
        # Set up mocks
        mock_display = Mock()
        mock_display_class.return_value = mock_display
        
        mock_keyboard = Mock()
        mock_keyboard_class.return_value.__enter__.return_value = mock_keyboard
        
        # Set up results
        test_path = Path("/test/file.jsonl")
        mock_result = Mock(file_path=test_path)
        self.rts.state.results = [mock_result]
        self.rts.state.selected_index = 0
        
        # Simulate typing and selecting
        mock_keyboard.get_key.side_effect = ['t', 'e', 's', 't', 'ENTER']
        
        # Mock thread
        mock_thread = Mock()
        mock_thread_class.return_value = mock_thread
        
        # Run should return selected path
        result = self.rts.run()
        
        self.assertEqual(result, test_path)
    
    @patch('realtime_search.threading.Thread')
    @patch('realtime_search.KeyboardHandler')
    @patch('realtime_search.TerminalDisplay')
    def test_run_keyboard_interrupt(self, mock_display_class, mock_keyboard_class, mock_thread_class):
        """Test run handles KeyboardInterrupt"""
        # Set up mocks
        mock_display = Mock()
        mock_display_class.return_value = mock_display
        
        mock_keyboard = Mock()
        mock_keyboard_class.return_value.__enter__.return_value = mock_keyboard
        mock_keyboard.get_key.side_effect = KeyboardInterrupt()
        
        # Mock thread
        mock_thread = Mock()
        mock_thread_class.return_value = mock_thread
        
        # Should handle interrupt gracefully
        result = self.rts.run()
        
        self.assertIsNone(result)
        mock_display.clear_screen.assert_called()
    
    @patch('realtime_search.threading.Thread')
    @patch('realtime_search.KeyboardHandler')
    @patch('realtime_search.TerminalDisplay')
    def test_run_exception_cleanup(self, mock_display_class, mock_keyboard_class, mock_thread_class):
        """Test run cleans up on exception"""
        # Set up mocks
        mock_display = Mock()
        mock_display_class.return_value = mock_display
        
        mock_keyboard = Mock()
        mock_keyboard_class.return_value.__enter__.return_value = mock_keyboard
        mock_keyboard.get_key.side_effect = Exception("Test error")
        
        # Mock thread
        mock_thread = Mock()
        mock_thread_class.return_value = mock_thread
        
        # Should handle exception and clean up
        with self.assertRaises(Exception):
            self.rts.run()
        
        # Cleanup should still happen
        mock_display.clear_screen.assert_called()


if __name__ == '__main__':
    unittest.main()