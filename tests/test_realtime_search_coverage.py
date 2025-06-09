#!/usr/bin/env python3
"""
Tests to achieve 100% coverage for realtime_search.py
Focus on untested code paths
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
import sys
import os
from pathlib import Path
import time
from datetime import datetime

sys.path.append(str(Path(__file__).parent.parent))

from realtime_search import (
    SearchState, KeyboardHandler, TerminalDisplay,
    RealTimeSearch, create_smart_searcher
)


class TestKeyboardHandlerCoverage(unittest.TestCase):
    """Test keyboard handler edge cases"""
    
    @patch('sys.platform', 'win32')
    def test_windows_keyboard_init(self):
        """Test Windows keyboard initialization"""
        # Mock msvcrt module for Windows
        mock_msvcrt = MagicMock()
        with patch.dict('sys.modules', {'msvcrt': mock_msvcrt}):
            # Reimport module to get Windows behavior
            import importlib
            import realtime_search
            importlib.reload(realtime_search)
            
            handler = realtime_search.KeyboardHandler()
            # Should not set stdin_fd on Windows
            self.assertFalse(hasattr(handler, 'stdin_fd'))
    
    @patch('sys.platform', 'win32')
    @patch('realtime_search.msvcrt')
    def test_windows_keyboard_special_keys(self, mock_msvcrt):
        """Test Windows special key handling"""
        handler = KeyboardHandler()
        
        # Mock special key sequences
        test_cases = [
            ([b'\x00', b'H'], 'UP'),      # Up arrow
            ([b'\x00', b'P'], 'DOWN'),    # Down arrow
            ([b'\x00', b'K'], 'LEFT'),    # Left arrow
            ([b'\x00', b'M'], 'RIGHT'),   # Right arrow
            ([b'\xe0', b'H'], 'UP'),      # Extended up arrow
            ([b'\x1b'], 'ESC'),           # Escape
            ([b'\r'], 'ENTER'),           # Enter
            ([b'\x08'], 'BACKSPACE'),     # Backspace
        ]
        
        for key_sequence, expected in test_cases:
            with self.subTest(expected=expected):
                mock_msvcrt.kbhit.return_value = True
                mock_msvcrt.getch.side_effect = key_sequence
                
                result = handler.get_key()
                self.assertEqual(result, expected)
                
                # Reset mock
                mock_msvcrt.getch.side_effect = None
    
    @patch('sys.platform', 'win32')
    @patch('realtime_search.msvcrt')
    def test_windows_keyboard_regular_chars(self, mock_msvcrt):
        """Test Windows regular character input"""
        handler = KeyboardHandler()
        
        # Test regular characters
        mock_msvcrt.kbhit.return_value = True
        mock_msvcrt.getch.return_value = b'a'
        
        result = handler.get_key()
        self.assertEqual(result, 'a')
    
    @patch('sys.platform', 'win32')
    @patch('realtime_search.msvcrt')
    def test_windows_keyboard_decode_error(self, mock_msvcrt):
        """Test Windows keyboard decode error handling"""
        handler = KeyboardHandler()
        
        # Invalid UTF-8 sequence
        mock_msvcrt.kbhit.return_value = True
        mock_msvcrt.getch.return_value = b'\xff\xfe'
        
        result = handler.get_key()
        self.assertIsNone(result)
    
    @patch('sys.platform', 'win32')
    @patch('realtime_search.msvcrt')
    def test_windows_keyboard_timeout(self, mock_msvcrt):
        """Test Windows keyboard timeout"""
        handler = KeyboardHandler()
        
        # No key pressed
        mock_msvcrt.kbhit.return_value = False
        
        start = time.time()
        result = handler.get_key(timeout=0.1)
        duration = time.time() - start
        
        self.assertIsNone(result)
        self.assertGreaterEqual(duration, 0.1)
        self.assertLess(duration, 0.2)
    
    @patch('sys.platform', 'linux')
    def test_unix_keyboard_init(self):
        """Test Unix keyboard initialization"""
        with patch('sys.stdin.fileno', return_value=0):
            handler = KeyboardHandler()
            self.assertEqual(handler.stdin_fd, 0)
    
    @patch('sys.platform', 'linux')
    def test_unix_keyboard_context_manager(self):
        """Test Unix keyboard context manager"""
        with patch('sys.stdin.fileno', return_value=0), \
             patch('realtime_search.termios') as mock_termios, \
             patch('realtime_search.tty') as mock_tty:
            
            old_settings = 'old_settings'
            mock_termios.tcgetattr.return_value = old_settings
            
            handler = KeyboardHandler()
            
            # Enter context
            handler.__enter__()
            mock_termios.tcgetattr.assert_called_once_with(0)
            mock_tty.setraw.assert_called_once_with(0)
            
            # Exit context
            handler.__exit__(None, None, None)
            mock_termios.tcsetattr.assert_called_once_with(
                0, mock_termios.TCSADRAIN, old_settings
            )
    
    @patch('sys.platform', 'linux')
    def test_unix_keyboard_special_sequences(self):
        """Test Unix escape sequences"""
        with patch('sys.stdin.fileno', return_value=0), \
             patch('realtime_search.select') as mock_select, \
             patch('sys.stdin') as mock_stdin:
            
            handler = KeyboardHandler()
            
            # Test escape sequences
            test_cases = [
                (['\x1b', '[A'], 'UP'),
                (['\x1b', '[B'], 'DOWN'),
                (['\x1b', '[C'], 'RIGHT'),
                (['\x1b', '[D'], 'LEFT'),
                (['\x1b'], 'ESC'),  # Just escape
                (['\r'], 'ENTER'),
                (['\n'], 'ENTER'),
                (['\x7f'], 'BACKSPACE'),
                (['\x08'], 'BACKSPACE'),
            ]
            
            for sequence, expected in test_cases:
                with self.subTest(expected=expected):
                    # Mock select to indicate data available
                    mock_select.select.return_value = ([sys.stdin], [], [])
                    
                    # Mock stdin reads
                    mock_stdin.read.side_effect = sequence
                    
                    result = handler.get_key()
                    self.assertEqual(result, expected)
                    
                    # Reset mocks
                    mock_stdin.read.side_effect = None
    
    @patch('sys.platform', 'linux')
    def test_unix_keyboard_ctrl_c(self):
        """Test Ctrl+C handling"""
        with patch('sys.stdin.fileno', return_value=0), \
             patch('realtime_search.select') as mock_select, \
             patch('sys.stdin') as mock_stdin:
            
            handler = KeyboardHandler()
            
            mock_select.select.return_value = ([sys.stdin], [], [])
            mock_stdin.read.return_value = '\x03'  # Ctrl+C
            
            with self.assertRaises(KeyboardInterrupt):
                handler.get_key()


class TestTerminalDisplayCoverage(unittest.TestCase):
    """Test terminal display methods"""
    
    def setUp(self):
        self.display = TerminalDisplay()
    
    @patch('sys.platform', 'win32')
    @patch('os.system')
    def test_clear_screen_windows(self, mock_system):
        """Test clear screen on Windows"""
        self.display.clear_screen()
        mock_system.assert_called_once_with('cls')
    
    @patch('sys.platform', 'linux')
    @patch('builtins.print')
    def test_clear_screen_unix(self, mock_print):
        """Test clear screen on Unix"""
        self.display.clear_screen()
        mock_print.assert_called_once_with('\033[2J\033[H', end='')
    
    @patch('builtins.print')
    def test_cursor_operations(self, mock_print):
        """Test cursor movement operations"""
        # Move cursor
        self.display.move_cursor(5, 10)
        mock_print.assert_called_with('\033[5;10H', end='')
        
        # Clear line
        mock_print.reset_mock()
        self.display.clear_line()
        mock_print.assert_called_with('\033[2K', end='')
        
        # Save cursor
        mock_print.reset_mock()
        self.display.save_cursor()
        mock_print.assert_called_with('\033[s', end='')
        
        # Restore cursor
        mock_print.reset_mock()
        self.display.restore_cursor()
        mock_print.assert_called_with('\033[u', end='')
    
    @patch('builtins.print')
    def test_draw_results_with_query_no_match(self, mock_print):
        """Test drawing results when query doesn't match"""
        results = [Mock(
            file_path=Path("/test/file.jsonl"),
            timestamp=datetime.now(),
            context="Some context without the search term",
            speaker="human"
        )]
        
        self.display.draw_results(results, 0, "nomatch")
        
        # Should still display result
        calls = [str(call) for call in mock_print.call_args_list]
        self.assertTrue(any("Some context" in str(call) for call in calls))
    
    @patch('builtins.print')
    @patch('sys.stdout')
    def test_draw_search_box_with_flush(self, mock_stdout, mock_print):
        """Test search box drawing with stdout flush"""
        self.display.last_result_count = 2
        self.display.draw_search_box("test query", 5)
        
        # Verify flush was called
        mock_stdout.flush.assert_called_once()


class TestRealTimeSearchCoverage(unittest.TestCase):
    """Test RealTimeSearch edge cases"""
    
    def setUp(self):
        self.mock_searcher = Mock()
        self.mock_extractor = Mock()
        self.rts = RealTimeSearch(self.mock_searcher, self.mock_extractor)
    
    def test_search_worker_exception_in_search(self):
        """Test exception handling in search worker"""
        # Set up state for search
        self.rts.state.query = "test"
        self.rts.state.is_searching = True
        self.rts.state.last_update = time.time() - 1
        
        # Make search raise exception
        self.rts.searcher.search.side_effect = Exception("Search failed")
        
        # Process request
        result = self.rts._process_search_request()
        
        self.assertTrue(result)
        self.assertEqual(self.rts.state.results, [])
    
    def test_stop_with_no_thread(self):
        """Test stop when no thread exists"""
        self.rts.search_thread = None
        # Should not raise exception
        self.rts.stop()
    
    def test_stop_with_dead_thread(self):
        """Test stop when thread is not alive"""
        mock_thread = Mock()
        mock_thread.is_alive.return_value = False
        self.rts.search_thread = mock_thread
        
        self.rts.stop()
        
        # Should not try to stop dead thread
        mock_thread.join.assert_not_called()


class TestSmartSearcherCoverage(unittest.TestCase):
    """Test smart searcher edge cases"""
    
    def test_create_smart_searcher_with_semantic_exception(self):
        """Test semantic search exception handling"""
        mock_searcher = Mock()
        mock_searcher.nlp = Mock()  # Has NLP
        
        # Make semantic search fail
        def search_side_effect(query, mode=None, **kwargs):
            if mode == "semantic":
                raise Exception("Semantic search failed")
            return []
        
        mock_searcher.search.side_effect = search_side_effect
        
        smart_searcher = create_smart_searcher(mock_searcher)
        
        # Should not crash
        results = smart_searcher.search("test query")
        self.assertIsInstance(results, list)
    
    def test_smart_searcher_sorting_with_no_timestamp(self):
        """Test sorting when results have no timestamp"""
        mock_searcher = Mock()
        
        # Results without timestamp attribute
        mock_results = [
            Mock(spec=['file_path']),  # No timestamp
            Mock(timestamp=None),       # None timestamp
        ]
        mock_searcher.search.return_value = mock_results
        
        smart_searcher = create_smart_searcher(mock_searcher)
        
        # Should not crash when sorting
        results = smart_searcher.search("test")
        self.assertEqual(len(results), 2)
    
    def test_smart_searcher_invalid_regex_pattern(self):
        """Test handling of invalid regex patterns"""
        mock_searcher = Mock()
        
        def search_side_effect(query, mode=None, **kwargs):
            if mode == "regex":
                raise Exception("Invalid regex")
            return [Mock(file_path=Path(f"/test/{mode}.txt"))]
        
        mock_searcher.search.side_effect = search_side_effect
        
        smart_searcher = create_smart_searcher(mock_searcher)
        
        # Search with regex-like pattern
        results = smart_searcher.search("[invalid(")
        
        # Should still get results from other modes
        self.assertGreater(len(results), 0)
    
    def test_smart_searcher_sorting_fallback(self):
        """Test sorting fallback when timestamp comparison fails"""
        mock_searcher = Mock()
        
        # Create results that will fail timestamp sorting
        class BadTimestamp:
            def __lt__(self, other):
                raise TypeError("Cannot compare")
        
        mock_results = [
            Mock(file_path=Path("/a.txt"), timestamp=BadTimestamp(), relevance_score=0.5),
            Mock(file_path=Path("/b.txt"), timestamp=BadTimestamp(), relevance_score=0.8),
        ]
        
        mock_searcher.search.return_value = mock_results
        
        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test")
        
        # Should fall back to relevance score sorting
        self.assertEqual(results[0].relevance_score, 0.8)
        self.assertEqual(results[1].relevance_score, 0.5)
    
    def test_smart_searcher_sorting_final_fallback(self):
        """Test final sorting fallback when all sorting fails"""
        mock_searcher = Mock()
        
        # Create results that will fail all sorting
        class BadComparison:
            def __lt__(self, other):
                raise TypeError("Cannot compare")
        
        mock_results = [
            Mock(file_path=Path("/a.txt"), timestamp=BadComparison()),
            Mock(file_path=Path("/b.txt"), timestamp=BadComparison()),
        ]
        # Remove relevance_score to test final fallback
        for r in mock_results:
            if hasattr(r, 'relevance_score'):
                delattr(r, 'relevance_score')
        
        mock_searcher.search.return_value = mock_results
        
        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test")
        
        # Should maintain original order
        self.assertEqual(len(results), 2)


if __name__ == '__main__':
    unittest.main()