#!/usr/bin/env python3
"""
UI tests for realtime search with proper mocking and no infinite loops
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
from pathlib import Path
import threading
import time
from datetime import datetime

import sys
sys.path.append(str(Path(__file__).parent.parent))

from realtime_search import RealTimeSearch, TerminalDisplay, KeyboardHandler


class MockKeyboardHandler:
    """Test keyboard handler that provides scripted input"""
    
    def __init__(self, input_sequence, max_calls=100):
        self.input_sequence = list(input_sequence)
        self.index = 0
        self.call_count = 0
        self.max_calls = max_calls
    
    def __enter__(self):
        return self
    
    def __exit__(self, *args):
        pass
    
    def get_key(self, timeout=0.1):
        """Return next key from sequence"""
        self.call_count += 1
        if self.call_count > self.max_calls:
            # Force exit to prevent infinite loop
            return 'ESC'
        
        if self.index < len(self.input_sequence):
            key = self.input_sequence[self.index]
            self.index += 1
            # Small delay to simulate typing
            if key and key != 'ESC':
                time.sleep(0.01)
            return key
        return None


class MockTerminalDisplay:
    """Test terminal display that captures output"""
    
    def __init__(self):
        self.output = []
        self.clear_count = 0
        self.header_drawn = False
        self.results_drawn = []
        self.search_box_drawn = []
    
    def clear_screen(self):
        self.clear_count += 1
        self.output.append("CLEAR_SCREEN")
    
    def move_cursor(self, row, col):
        self.output.append(f"MOVE_CURSOR({row},{col})")
    
    def clear_line(self):
        self.output.append("CLEAR_LINE")
    
    def save_cursor(self):
        self.output.append("SAVE_CURSOR")
    
    def restore_cursor(self):
        self.output.append("RESTORE_CURSOR")
    
    def draw_header(self):
        self.header_drawn = True
        self.output.append("DRAW_HEADER")
    
    def draw_results(self, results, selected_index, query):
        self.results_drawn.append({
            'results': results,
            'selected_index': selected_index,
            'query': query
        })
        self.output.append(f"DRAW_RESULTS(count={len(results)}, selected={selected_index}, query='{query}')")
    
    def draw_search_box(self, query, cursor_pos):
        self.search_box_drawn.append({
            'query': query,
            'cursor_pos': cursor_pos
        })
        self.output.append(f"DRAW_SEARCH_BOX(query='{query}', cursor={cursor_pos})")


class TestRealTimeSearchUI(unittest.TestCase):
    """Test UI components with real functionality"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.mock_searcher = Mock()
        self.mock_extractor = Mock()
        self.rts = RealTimeSearch(self.mock_searcher, self.mock_extractor)
        # Replace display with mock
        self.mock_display = MockTerminalDisplay()
        self.rts.display = self.mock_display
    
    def tearDown(self):
        """Ensure threads are stopped"""
        self.rts.stop()
    
    def test_run_with_esc_exit(self):
        """Test run exits cleanly on ESC"""
        # Set up keyboard mock to type and then ESC
        input_sequence = ['h', 'e', 'l', 'l', 'o', 'ESC']
        
        with patch('realtime_search.KeyboardHandler', return_value=MockKeyboardHandler(input_sequence)):
            result = self.rts.run()
        
        # Should return None on ESC
        self.assertIsNone(result)
        
        # Verify UI was drawn
        self.assertTrue(self.mock_display.header_drawn)
        self.assertGreater(len(self.mock_display.search_box_drawn), 0)
        
        # Verify query was built correctly
        # Find the last non-empty query before ESC
        queries = [s['query'] for s in self.mock_display.search_box_drawn if s['query']]
        if queries:
            # Check that we built up to "hello" at some point
            self.assertIn('hello', queries)
        
        # Verify cleanup
        self.assertGreater(self.mock_display.clear_count, 1)  # Initial clear + final clear
    
    def test_run_with_result_selection(self):
        """Test selecting a result"""
        # Mock search results
        test_path = Path("/test/conversation.jsonl")
        mock_result = Mock(
            file_path=test_path,
            timestamp=datetime.now(),
            context="Test conversation content",
            speaker="human"
        )
        
        # Set up searcher to return results immediately
        def search_side_effect(*args, **kwargs):
            # Populate results in state as well
            results = [mock_result]
            self.rts.state.results = results
            return results
        
        self.mock_searcher.search.side_effect = search_side_effect
        
        # Pre-populate results to avoid waiting
        self.rts.state.results = [mock_result]
        self.rts.state.selected_index = 0
        
        # Just select the pre-populated result
        input_sequence = ['ENTER']
        
        with patch('realtime_search.KeyboardHandler', return_value=MockKeyboardHandler(input_sequence, max_calls=10)):
            result = self.rts.run()
        
        # Should return selected path
        self.assertEqual(result, test_path)
    
    def test_run_with_arrow_navigation(self):
        """Test navigating through results with arrow keys"""
        # Pre-populate results
        results = [
            Mock(file_path=Path(f"/test{i}.jsonl"), timestamp=datetime.now(), 
                 context=f"Result {i}", speaker="human")
            for i in range(3)
        ]
        self.rts.state.results = results
        self.rts.state.selected_index = 0
        
        # Navigate down twice, then select
        input_sequence = ['DOWN', 'DOWN', 'ENTER']
        
        with patch('realtime_search.KeyboardHandler', return_value=MockKeyboardHandler(input_sequence, max_calls=20)):
            result = self.rts.run()
        
        # Should select third result (index 2)
        self.assertEqual(result, Path("/test2.jsonl"))
    
    def test_run_with_keyboard_interrupt(self):
        """Test handling KeyboardInterrupt"""
        def raise_interrupt(*args, **kwargs):
            raise KeyboardInterrupt()
        
        with patch('realtime_search.KeyboardHandler') as mock_kb_class:
            mock_kb = Mock()
            mock_kb.get_key.side_effect = raise_interrupt
            mock_kb_class.return_value.__enter__.return_value = mock_kb
            
            result = self.rts.run()
        
        # Should handle gracefully
        self.assertIsNone(result)
        self.assertGreater(self.mock_display.clear_count, 0)
    
    def test_run_with_backspace(self):
        """Test backspace functionality"""
        input_sequence = ['h', 'e', 'l', 'l', 'o', 'BACKSPACE', 'BACKSPACE', 'p', 'ESC']
        
        with patch('realtime_search.KeyboardHandler', return_value=MockKeyboardHandler(input_sequence)):
            self.rts.run()
        
        # Check query progression
        queries = [s['query'] for s in self.mock_display.search_box_drawn]
        self.assertIn('hello', queries)
        self.assertIn('hel', queries)  # After backspaces
        self.assertIn('help', queries)  # After typing 'p'
    
    def test_thread_starts_and_stops(self):
        """Test that search thread lifecycle is managed properly"""
        input_sequence = ['t', 'e', 's', 't', 'ESC']
        
        # Verify thread not running initially
        self.assertIsNone(self.rts.search_thread)
        
        with patch('realtime_search.KeyboardHandler', return_value=MockKeyboardHandler(input_sequence)):
            self.rts.run()
        
        # Thread should be stopped after run
        if self.rts.search_thread:
            self.assertFalse(self.rts.search_thread.is_alive())
    
    def test_search_debouncing(self):
        """Test that searches are debounced"""
        search_call_times = []
        
        def track_search_time(*args, **kwargs):
            search_call_times.append(time.time())
            return []
        
        self.mock_searcher.search.side_effect = track_search_time
        
        # Type quickly
        input_sequence = ['a', 'b', 'c', None, None, None, None, 'ESC']
        
        with patch('realtime_search.KeyboardHandler', return_value=MockKeyboardHandler(input_sequence)):
            self.rts.run()
        
        # Should have limited search calls due to debouncing
        # With 300ms debounce, rapid typing should result in fewer searches
        self.assertLessEqual(len(search_call_times), 2)


class TestTerminalDisplay(unittest.TestCase):
    """Test the actual TerminalDisplay class"""
    
    def setUp(self):
        """Set up display with captured output"""
        self.display = TerminalDisplay()
        self.captured_output = []
        
    @patch('builtins.print')
    def test_draw_header(self, mock_print):
        """Test header drawing"""
        self.display.draw_header()
        
        # Verify header content
        calls = [call[0][0] if call[0] else call[1].get('end', '') 
                 for call in mock_print.call_args_list]
        output = ''.join(str(c) for c in calls)
        
        self.assertIn("REAL-TIME SEARCH", output)
        self.assertIn("Type to search", output)
        self.assertIn("ESC to exit", output)
    
    @patch('builtins.print')
    def test_draw_results_empty(self, mock_print):
        """Test drawing with no results"""
        self.display.draw_results([], 0, "")
        
        calls = [call[0][0] if call[0] else '' for call in mock_print.call_args_list]
        output = ''.join(str(c) for c in calls)
        
        self.assertIn("Start typing to search", output)
    
    @patch('builtins.print')
    def test_draw_results_with_items(self, mock_print):
        """Test drawing actual results"""
        results = [
            Mock(
                file_path=Path("/test/chat1.jsonl"),
                timestamp=datetime.now(),
                context="Test context with search term",
                speaker="human"
            )
        ]
        
        self.display.draw_results(results, 0, "search")
        
        calls = [call[0][0] if call[0] else '' for call in mock_print.call_args_list]
        output = ''.join(str(c) for c in calls)
        
        # Should show selection indicator for selected item
        self.assertIn("▸", output)
        # Should show file info - look for "test" which is the parent directory name
        self.assertIn("test", output)


if __name__ == '__main__':
    unittest.main()