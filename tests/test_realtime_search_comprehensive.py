#!/usr/bin/env python3
"""
Comprehensive tests for realtime_search.py to achieve 100% coverage
"""

import sys
import threading
import time
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import Mock, patch

# Add parent directory to path before local imports
sys.path.append(str(Path(__file__).parent.parent))

# Local imports after sys.path modification
from realtime_search import (KeyboardHandler, RealTimeSearch, SearchState,  # noqa: E402
                             TerminalDisplay, create_smart_searcher)


class TestSearchStateComprehensive(unittest.TestCase):
    """Comprehensive tests for SearchState"""

    def test_search_state_defaults(self):
        """Test SearchState default values"""
        state = SearchState()
        self.assertEqual(state.query, "")
        self.assertEqual(state.cursor_pos, 0)
        self.assertEqual(state.results, [])
        self.assertEqual(state.selected_index, 0)
        self.assertEqual(state.last_update, 0)
        self.assertFalse(state.is_searching)

    def test_search_state_with_values(self):
        """Test SearchState with custom values"""
        results = [Mock(), Mock()]
        state = SearchState(
            query="test",
            cursor_pos=4,
            results=results,
            selected_index=1,
            last_update=time.time(),
            is_searching=True,
        )
        self.assertEqual(state.query, "test")
        self.assertEqual(state.cursor_pos, 4)
        self.assertEqual(state.results, results)
        self.assertEqual(state.selected_index, 1)
        self.assertTrue(state.is_searching)


class TestKeyboardHandlerComprehensive(unittest.TestCase):
    """Comprehensive tests for KeyboardHandler"""

    @patch("sys.platform", "darwin")
    def test_unix_keyboard_special_keys(self):
        """Test Unix keyboard handler with all special keys"""
        with patch("realtime_search.termios"), patch("realtime_search.tty"), patch(
            "realtime_search.select"
        ) as mock_select, patch("sys.stdin") as mock_stdin:

            handler = KeyboardHandler()

            # Test arrow keys
            test_cases = [
                ([True], ["\x1b", "[", "A"], "UP"),
                ([True], ["\x1b", "[", "B"], "DOWN"),
                ([True], ["\x1b", "[", "C"], "RIGHT"),
                ([True], ["\x1b", "[", "D"], "LEFT"),
                ([True], ["\x1b"], "ESC"),  # ESC alone
                ([True], ["\r"], "ENTER"),
                ([True], ["\n"], "ENTER"),
                ([True], ["\x7f"], "BACKSPACE"),
                ([True], ["\x08"], "BACKSPACE"),
                ([True], ["a"], "a"),  # Regular character
            ]

            for select_return, stdin_chars, expected in test_cases:
                mock_select.select.side_effect = [
                    (
                        select_return if i == 0 else [stdin_chars[i] is not None]
                        for i in range(len(stdin_chars))
                    )
                ]
                mock_stdin.read.side_effect = stdin_chars

                key = handler.get_key(timeout=0.1)
                self.assertEqual(key, expected)

                # Reset mocks
                mock_select.select.reset_mock()
                mock_stdin.read.reset_mock()

    @patch("sys.platform", "darwin")
    def test_unix_keyboard_ctrl_c(self):
        """Test Unix keyboard handler Ctrl+C"""
        with patch("realtime_search.termios"), patch("realtime_search.tty"), patch(
            "realtime_search.select"
        ) as mock_select, patch("sys.stdin") as mock_stdin:

            handler = KeyboardHandler()

            mock_select.select.return_value = ([True], [], [])
            mock_stdin.read.return_value = "\x03"  # Ctrl+C

            with self.assertRaises(KeyboardInterrupt):
                handler.get_key(timeout=0.1)

    @patch("sys.platform", "darwin")
    def test_unix_keyboard_timeout(self):
        """Test Unix keyboard timeout"""
        with patch("realtime_search.termios"), patch("realtime_search.tty"), patch(
            "realtime_search.select"
        ) as mock_select:

            handler = KeyboardHandler()

            # No input available
            mock_select.select.return_value = ([], [], [])

            key = handler.get_key(timeout=0.1)
            self.assertIsNone(key)

    @patch("sys.platform", "win32")
    def test_windows_keyboard_all_keys(self):
        """Test Windows keyboard handler with all key types"""
        with patch("realtime_search.msvcrt") as mock_msvcrt:
            handler = KeyboardHandler()

            # Test timeout (no key pressed)
            mock_msvcrt.kbhit.return_value = False
            key = handler.get_key(timeout=0.01)
            self.assertIsNone(key)

            # Test regular character
            mock_msvcrt.kbhit.return_value = True
            mock_msvcrt.getch.return_value = b"x"
            key = handler.get_key(timeout=0.1)
            self.assertEqual(key, "x")

            # Test special keys
            test_cases = [
                ([b"\xe0", b"K"], "LEFT"),
                ([b"\xe0", b"M"], "RIGHT"),
                ([b"\x00", b"H"], "UP"),
                ([b"\x00", b"P"], "DOWN"),
                ([b"\x1b"], "ESC"),
                ([b"\r"], "ENTER"),
                ([b"\x08"], "BACKSPACE"),
            ]

            for getch_returns, expected in test_cases:
                mock_msvcrt.getch.side_effect = getch_returns
                key = handler.get_key(timeout=0.1)
                self.assertEqual(key, expected)

    @patch("sys.platform", "win32")
    def test_windows_keyboard_decode_error(self):
        """Test Windows keyboard with decode error"""
        with patch("realtime_search.msvcrt") as mock_msvcrt:
            handler = KeyboardHandler()

            mock_msvcrt.kbhit.return_value = True
            mock_msvcrt.getch.return_value = b"\xff\xfe"  # Invalid UTF-8

            key = handler.get_key(timeout=0.1)
            self.assertIsNone(key)


class TestTerminalDisplayComprehensive(unittest.TestCase):
    """Comprehensive tests for TerminalDisplay"""

    def setUp(self):
        """Set up test display"""
        self.display = TerminalDisplay()

    @patch("sys.platform", "win32")
    @patch("os.system")
    def test_clear_screen_windows(self, mock_system):
        """Test clear screen on Windows"""
        self.display.clear_screen()
        mock_system.assert_called_once_with("cls")

    @patch("sys.platform", "darwin")
    @patch("sys.stdout")
    def test_clear_screen_unix(self, mock_stdout):
        """Test clear screen on Unix"""
        self.display.clear_screen()
        # Should print ANSI escape sequence
        mock_stdout.write.assert_called()
        written = "".join(call[0][0] for call in mock_stdout.write.call_args_list)
        self.assertIn("\033[2J\033[H", written)

    @patch("sys.stdout")
    def test_terminal_control_methods(self, mock_stdout):
        """Test all terminal control methods"""
        # Test move cursor
        self.display.move_cursor(10, 20)
        self.assertIn("\033[10;20H", self._get_stdout_content(mock_stdout))

        # Test clear line
        mock_stdout.reset_mock()
        self.display.clear_line()
        self.assertIn("\033[2K", self._get_stdout_content(mock_stdout))

        # Test save cursor
        mock_stdout.reset_mock()
        self.display.save_cursor()
        self.assertIn("\033[s", self._get_stdout_content(mock_stdout))

        # Test restore cursor
        mock_stdout.reset_mock()
        self.display.restore_cursor()
        self.assertIn("\033[u", self._get_stdout_content(mock_stdout))

    def _get_stdout_content(self, mock_stdout):
        """Helper to get stdout content from mock"""
        return "".join(
            call[0][0] for call in mock_stdout.write.call_args_list if call[0][0]
        )

    @patch("sys.stdout")
    def test_draw_results_with_selection(self, mock_stdout):
        """Test drawing results with selection indicator"""
        results = [
            Mock(
                timestamp=datetime.now(),
                file_path=Path("/test/chat1.jsonl"),
                context="Result 1 context",
                speaker="human",
            ),
            Mock(
                timestamp=datetime.now(),
                file_path=Path("/test/chat2.jsonl"),
                context="Result 2 context",
                speaker="assistant",
            ),
        ]

        self.display.draw_results(results, 1, "test")
        output = self._get_stdout_content(mock_stdout)

        # Second result should have selection indicator
        self.assertIn("▸", output)

    @patch("sys.stdout")
    def test_draw_results_max_limit(self, mock_stdout):
        """Test drawing results respects 10 result limit"""
        # Create 15 results
        results = [
            Mock(
                timestamp=datetime.now(),
                file_path=Path(f"/test/chat{i}.jsonl"),
                context=f"Result {i}",
                speaker="human",
            )
            for i in range(15)
        ]

        self.display.draw_results(results, 0, "test")

        # Should only show 10 results
        self.assertEqual(self.display.last_result_count, 10)

    @patch("sys.stdout")
    def test_draw_search_box(self, mock_stdout):
        """Test drawing search input box"""
        self.display.last_result_count = 3
        self.display.draw_search_box("hello world", 5)

        output = self._get_stdout_content(mock_stdout)
        self.assertIn("Search: hello world", output)

        # Check cursor positioning
        final_call = mock_stdout.write.call_args_list[-1][0][0]
        self.assertIn("\033[", final_call)  # ANSI cursor positioning


class TestRealTimeSearchComprehensive(unittest.TestCase):
    """Comprehensive tests for RealTimeSearch"""

    def setUp(self):
        """Set up test search"""
        self.mock_searcher = Mock()
        self.mock_extractor = Mock()
        self.rts = RealTimeSearch(self.mock_searcher, self.mock_extractor)

    def test_search_worker_thread(self):
        """Test search worker thread behavior"""
        # Mock the search to return quickly
        self.mock_searcher.search.return_value = [Mock()]

        # Start the thread
        self.rts.search_thread = threading.Thread(
            target=self.rts.search_worker, daemon=True
        )
        self.rts.search_thread.start()

        try:
            # Trigger a search
            self.rts.state.query = "test query"
            self.rts.trigger_search()

            # Give thread time to process
            time.sleep(0.5)

            # Should have called search
            self.mock_searcher.search.assert_called_with(
                query="test query", mode="smart", max_results=20, case_sensitive=False
            )
        finally:
            # Clean shutdown using new stop method
            self.rts.stop()

    def test_search_worker_with_cache(self):
        """Test search worker uses cache"""
        # Pre-populate cache
        cached_results = [Mock()]
        self.rts.results_cache["cached query"] = cached_results

        # Set up state
        self.rts.state.query = "cached query"
        self.rts.state.is_searching = True
        self.rts.state.last_update = time.time() - 1  # Old enough

        # Process one search request
        processed = self.rts._process_search_request()

        # Should have processed the request
        self.assertTrue(processed)
        # Should use cached results
        self.assertEqual(self.rts.state.results, cached_results)
        self.mock_searcher.search.assert_not_called()

    def test_search_worker_error_handling(self):
        """Test search worker handles errors gracefully"""
        # Make search raise an exception
        self.mock_searcher.search.side_effect = Exception("Search error")

        self.rts.state.query = "error query"
        self.rts.state.is_searching = True
        self.rts.state.last_update = time.time() - 1

        # Should not crash
        processed = self.rts._process_search_request()

        # Should have processed the request
        self.assertTrue(processed)
        # Results should be empty
        self.assertEqual(self.rts.state.results, [])

    def test_handle_input_cursor_movement(self):
        """Test cursor movement handling"""
        self.rts.state.query = "hello"
        self.rts.state.cursor_pos = 3

        # Test left arrow
        self.rts.handle_input("LEFT")
        self.assertEqual(self.rts.state.cursor_pos, 2)

        # Test left at beginning
        self.rts.state.cursor_pos = 0
        self.rts.handle_input("LEFT")
        self.assertEqual(self.rts.state.cursor_pos, 0)

        # Test right arrow
        self.rts.state.cursor_pos = 2
        self.rts.handle_input("RIGHT")
        self.assertEqual(self.rts.state.cursor_pos, 3)

        # Test right at end
        self.rts.state.cursor_pos = 5
        self.rts.handle_input("RIGHT")
        self.assertEqual(self.rts.state.cursor_pos, 5)

    def test_handle_input_backspace_middle(self):
        """Test backspace in middle of text"""
        self.rts.state.query = "hello"
        self.rts.state.cursor_pos = 3

        self.rts.handle_input("BACKSPACE")

        self.assertEqual(self.rts.state.query, "helo")
        self.assertEqual(self.rts.state.cursor_pos, 2)

    def test_handle_input_character_middle(self):
        """Test inserting character in middle of text"""
        self.rts.state.query = "helo"
        self.rts.state.cursor_pos = 2

        self.rts.handle_input("l")

        self.assertEqual(self.rts.state.query, "hello")
        self.assertEqual(self.rts.state.cursor_pos, 3)

    def test_handle_input_control_characters(self):
        """Test ignoring control characters"""
        self.rts.state.query = "test"
        self.rts.state.cursor_pos = 4

        # Control character (ASCII < 32)
        self.rts.handle_input("\x01")  # Ctrl+A

        # Should not change query
        self.assertEqual(self.rts.state.query, "test")

    def test_trigger_search_cache_cleanup(self):
        """Test cache cleanup on search trigger"""
        # Populate cache with various entries
        self.rts.results_cache = {
            "test": [Mock()],
            "testing": [Mock()],
            "other": [Mock()],
            "te": [Mock()],
        }

        self.rts.state.query = "tes"
        self.rts.trigger_search()

        # Should keep entries that start with "tes"
        self.assertNotIn("other", self.rts.results_cache)
        self.assertNotIn("te", self.rts.results_cache)

    @patch("realtime_search.KeyboardHandler")
    @patch("realtime_search.TerminalDisplay")
    def test_run_exception_handling(self, mock_display_class, mock_keyboard_class):
        """Test run method exception handling"""
        mock_keyboard = Mock()
        mock_keyboard_class.return_value.__enter__.return_value = mock_keyboard

        # Make get_key raise exception after a few keys
        mock_keyboard.get_key.side_effect = ["a", "b", Exception("Test error")]

        # Should return None on exception
        result = self.rts.run()
        self.assertIsNone(result)

    def test_handle_input_no_results_for_enter(self):
        """Test pressing Enter with no results"""
        self.rts.state.results = []

        action = self.rts.handle_input("ENTER")

        # Should not return 'select'
        self.assertNotEqual(action, "select")

    def test_handle_input_navigation_limits(self):
        """Test navigation respects result limits"""
        # Set up 3 results
        self.rts.state.results = [Mock(), Mock(), Mock()]
        self.rts.state.selected_index = 2

        # Try to go down past last result
        self.rts.handle_input("DOWN")
        self.assertEqual(self.rts.state.selected_index, 2)

        # Go up to first
        self.rts.state.selected_index = 0
        self.rts.handle_input("UP")
        self.assertEqual(self.rts.state.selected_index, 0)


class TestCreateSmartSearcherComprehensive(unittest.TestCase):
    """Comprehensive tests for create_smart_searcher"""

    def test_smart_search_with_regex_pattern(self):
        """Test smart search detects regex patterns"""
        mock_searcher = Mock()

        # Set up different results for different modes
        def search_side_effect(query, mode=None, **kwargs):
            if mode == "exact":
                return []
            elif mode == "regex":
                return [Mock(file_path=Path("/regex/result"))]
            elif mode == "smart":
                return [Mock(file_path=Path("/smart/result"))]
            return []

        mock_searcher.search = Mock(side_effect=search_side_effect)
        mock_searcher.nlp = None

        smart_searcher = create_smart_searcher(mock_searcher)

        # Search with regex pattern
        results = smart_searcher.search("test.*pattern")

        # Should include regex results
        paths = [r.file_path for r in results]
        self.assertIn(Path("/regex/result"), paths)

    def test_smart_search_with_semantic(self):
        """Test smart search with semantic search available"""
        mock_searcher = Mock()
        mock_searcher.nlp = Mock()  # Has NLP

        def search_side_effect(query, mode=None, **kwargs):
            if mode == "semantic":
                return [
                    Mock(file_path=Path("/semantic/result"), timestamp=datetime.now())
                ]
            return []

        mock_searcher.search = Mock(side_effect=search_side_effect)

        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("find similar concepts")

        # Should include semantic results
        self.assertEqual(len(results), 1)

    def test_smart_search_deduplication(self):
        """Test smart search deduplicates results"""
        mock_searcher = Mock()

        # Return same file from different modes
        same_file = Path("/duplicate/result")

        def search_side_effect(query, mode=None, **kwargs):
            return [Mock(file_path=same_file, timestamp=datetime.now())]

        mock_searcher.search = Mock(side_effect=search_side_effect)
        mock_searcher.nlp = None

        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test")

        # Should only have one result despite multiple modes returning it
        self.assertEqual(len(results), 1)

    def test_smart_search_respects_max_results(self):
        """Test smart search respects max_results parameter"""
        mock_searcher = Mock()

        # Return many results
        def search_side_effect(query, mode=None, **kwargs):
            return [
                Mock(file_path=Path(f"/{mode}/{i}"), timestamp=datetime.now())
                for i in range(10)
            ]

        mock_searcher.search = Mock(side_effect=search_side_effect)
        mock_searcher.nlp = None

        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test", max_results=5)

        # Should limit to 5 results
        self.assertEqual(len(results), 5)


if __name__ == "__main__":
    unittest.main()
