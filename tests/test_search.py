#!/usr/bin/env python3
"""
Comprehensive test suite for search functionality
"""

import json
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

import sys
sys.path.append(str(Path(__file__).parent.parent))

from search_conversations import ConversationSearcher, SearchResult
from realtime_search import (
    SearchState, KeyboardHandler, TerminalDisplay, 
    RealTimeSearch, create_smart_searcher
)


class TestSearchResult(unittest.TestCase):
    """Test SearchResult dataclass"""
    
    def test_search_result_creation(self):
        """Test creating a SearchResult"""
        result = SearchResult(
            file_path=Path("/test/path"),
            conversation_id="test-id",
            matched_content="test match",
            context="test context",
            speaker="human",
            timestamp=datetime.now(),
            relevance_score=0.95,
            line_number=0
        )
        
        self.assertEqual(result.file_path, Path("/test/path"))
        self.assertEqual(result.speaker, "human")
        self.assertEqual(result.context, "test context")
        self.assertEqual(result.relevance_score, 0.95)
    
    def test_search_result_string_representation(self):
        """Test SearchResult string formatting"""
        result = SearchResult(
            file_path=Path("/test/project/chat.jsonl"),
            conversation_id="test-id",
            matched_content="test message",
            context="This is a test message",
            speaker="assistant",
            timestamp=datetime(2024, 1, 15, 10, 30),
            relevance_score=0.8,
            line_number=5
        )
        
        str_repr = str(result)
        self.assertIn("chat.jsonl", str_repr)  # Filename
        self.assertIn("Assistant", str_repr)  # Title case
        self.assertIn("80%", str_repr)  # Relevance score


class TestConversationSearcher(unittest.TestCase):
    """Test ConversationSearcher functionality"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.test_dir = Path(self.temp_dir) / ".claude" / "projects" / "test"
        self.test_dir.mkdir(parents=True)
        
        # Create test conversation file
        self.test_file = self.test_dir / "chat_test.jsonl"
        self.test_conversations = [
            {
                "type": "user",
                "content": "How do I handle Python errors?",
                "timestamp": "2024-01-15T10:00:00Z"
            },
            {
                "type": "assistant", 
                "content": "To handle errors in Python, use try-except blocks.",
                "timestamp": "2024-01-15T10:01:00Z"
            },
            {
                "type": "user", 
                "content": "Can you show me an example with file operations?",
                "timestamp": "2024-01-15T10:02:00Z"
            }
        ]
        
        with open(self.test_file, 'w') as f:
            for conv in self.test_conversations:
                f.write(json.dumps(conv) + '\n')
        
        self.searcher = ConversationSearcher()
    
    def tearDown(self):
        """Clean up test files"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def test_search_exact_match(self):
        """Test exact string matching"""
        results = self.searcher.search(
            "Python errors",
            search_dir=self.test_dir,
            mode="exact"
        )
        
        self.assertEqual(len(results), 1)
        # Context is highlighted with ** markers and uppercase
        self.assertIn("**PYTHON ERRORS**", results[0].context)
    
    def test_search_smart_mode(self):
        """Test smart search with partial matches"""
        results = self.searcher.search(
            "python error",
            search_dir=self.test_dir,
            mode="smart"
        )
        
        self.assertGreater(len(results), 0)
        # Should find both "Python errors" and "errors in Python"
    
    def test_search_regex_mode(self):
        """Test regex pattern matching"""
        results = self.searcher.search(
            r"try.*except",
            search_dir=self.test_dir,
            mode="regex"
        )
        
        self.assertEqual(len(results), 1)
        self.assertIn("try-except", results[0].context)
    
    def test_search_speaker_filter(self):
        """Test filtering by speaker"""
        # Search human messages only
        human_results = self.searcher.search(
            "example",
            search_dir=self.test_dir,
            speaker_filter="human"
        )
        
        self.assertEqual(len(human_results), 1)
        self.assertEqual(human_results[0].speaker, "human")
        
        # Search assistant messages only
        assistant_results = self.searcher.search(
            "Python",
            search_dir=self.test_dir,
            speaker_filter="assistant"
        )
        
        self.assertEqual(len(assistant_results), 1)
        self.assertEqual(assistant_results[0].speaker, "assistant")
    
    def test_search_date_filter(self):
        """Test filtering by date range"""
        # Set file modification time to match our test data
        import os
        import time
        # Convert datetime to timestamp
        target_time = datetime(2024, 1, 15, 10, 0).timestamp()
        os.utime(self.test_file, (target_time, target_time))
        
        # Search with date filter
        date_from = datetime(2024, 1, 1)
        date_to = datetime(2024, 2, 1)
        
        results = self.searcher.search(
            "Python",
            search_dir=self.test_dir,
            date_from=date_from,
            date_to=date_to
        )
        
        self.assertGreater(len(results), 0)
        for result in results:
            self.assertIsNotNone(result.timestamp)
    
    def test_search_case_sensitivity(self):
        """Test case-sensitive search"""
        # Case-sensitive search
        results_sensitive = self.searcher.search(
            "python",  # lowercase
            search_dir=self.test_dir,
            case_sensitive=True
        )
        
        # Case-insensitive search
        results_insensitive = self.searcher.search(
            "python",
            search_dir=self.test_dir,
            case_sensitive=False
        )
        
        # Should find more results with case-insensitive
        self.assertGreaterEqual(len(results_insensitive), len(results_sensitive))
    
    def test_search_max_results(self):
        """Test limiting search results"""
        results = self.searcher.search(
            "",  # Empty query to match all
            search_dir=self.test_dir,
            max_results=2
        )
        
        self.assertLessEqual(len(results), 2)
    
    def test_empty_search_query(self):
        """Test behavior with empty search query"""
        results = self.searcher.search(
            "",
            search_dir=self.test_dir
        )
        
        # Empty query should return no results (not all messages)
        self.assertEqual(len(results), 0)


class TestSearchState(unittest.TestCase):
    """Test SearchState dataclass"""
    
    def test_initial_state(self):
        """Test initial state values"""
        state = SearchState()
        
        self.assertEqual(state.query, "")
        self.assertEqual(state.cursor_pos, 0)
        self.assertEqual(state.results, [])
        self.assertEqual(state.selected_index, 0)
        self.assertFalse(state.is_searching)
    
    def test_state_modification(self):
        """Test modifying state values"""
        state = SearchState()
        
        state.query = "test query"
        state.cursor_pos = 5
        state.is_searching = True
        
        self.assertEqual(state.query, "test query")
        self.assertEqual(state.cursor_pos, 5)
        self.assertTrue(state.is_searching)


class TestKeyboardHandler(unittest.TestCase):
    """Test KeyboardHandler functionality"""
    
    @patch('sys.platform', 'darwin')
    def test_context_manager(self):
        """Test KeyboardHandler as context manager"""
        # Mock the Unix-specific modules
        with patch('realtime_search.termios') as mock_termios, \
             patch('realtime_search.tty') as mock_tty:
            
            mock_termios.tcgetattr.return_value = "old_settings"
            
            handler = KeyboardHandler()
            with handler:
                self.assertIsNotNone(handler)
            
            # Verify terminal settings were saved and restored
            mock_termios.tcgetattr.assert_called_once()
            mock_tty.setraw.assert_called_once()
            mock_termios.tcsetattr.assert_called_once()
    
    @patch('sys.platform', 'win32')
    def test_windows_key_detection(self):
        """Test key detection on Windows"""
        with patch('realtime_search.msvcrt') as mock_msvcrt:
            handler = KeyboardHandler()
            
            # Test regular character
            mock_msvcrt.kbhit.return_value = True
            mock_msvcrt.getch.return_value = b'a'
            key = handler.get_key(timeout=0.1)
            self.assertEqual(key, 'a')
            
            # Reset mock for next test
            mock_msvcrt.kbhit.reset_mock()
            mock_msvcrt.getch.reset_mock()
            
            # Test special keys
            mock_msvcrt.kbhit.return_value = True
            mock_msvcrt.getch.side_effect = [b'\xe0', b'H']  # Up arrow
            key = handler.get_key(timeout=0.1)
            self.assertEqual(key, 'UP')


class TestTerminalDisplay(unittest.TestCase):
    """Test TerminalDisplay functionality"""
    
    def setUp(self):
        """Set up test display"""
        self.display = TerminalDisplay()
    
    @patch('sys.stdout')
    def test_clear_screen(self, mock_stdout):
        """Test screen clearing"""
        with patch('sys.platform', 'darwin'):
            self.display.clear_screen()
            # Should output ANSI clear screen sequence
            mock_stdout.write.assert_called()
    
    @patch('sys.stdout')
    def test_draw_header(self, mock_stdout):
        """Test header drawing"""
        self.display.draw_header()
        # Verify header text was printed
        printed_text = ''.join(call[0][0] for call in mock_stdout.write.call_args_list 
                              if call[0][0])
        self.assertIn("REAL-TIME SEARCH", printed_text)
    
    def test_draw_results_empty(self):
        """Test drawing empty results"""
        with patch('sys.stdout'):
            self.display.draw_results([], 0, "test query")
            # Should display "No results found"
    
    def test_draw_results_with_data(self):
        """Test drawing search results"""
        mock_results = [
            Mock(
                timestamp=datetime.now(),
                file_path=Path("/test/project/chat.jsonl"),
                context="Test result context",
                speaker="human",
                conversation_id="test-id",
                matched_content="Test result"
            )
        ]
        
        with patch('sys.stdout'):
            self.display.draw_results(mock_results, 0, "test")
            # Should display result


class TestRealTimeSearch(unittest.TestCase):
    """Test RealTimeSearch functionality"""
    
    def setUp(self):
        """Set up test search interface"""
        self.mock_searcher = Mock()
        self.mock_extractor = Mock()
        self.rts = RealTimeSearch(self.mock_searcher, self.mock_extractor)
    
    def test_handle_input_escape(self):
        """Test handling ESC key"""
        action = self.rts.handle_input('ESC')
        self.assertEqual(action, 'exit')
    
    def test_handle_input_enter(self):
        """Test handling Enter key with results"""
        self.rts.state.results = [Mock(), Mock()]
        self.rts.state.selected_index = 0
        
        action = self.rts.handle_input('ENTER')
        self.assertEqual(action, 'select')
    
    def test_handle_input_navigation(self):
        """Test arrow key navigation"""
        self.rts.state.results = [Mock(), Mock(), Mock()]
        
        # Test down arrow
        self.rts.handle_input('DOWN')
        self.assertEqual(self.rts.state.selected_index, 1)
        
        # Test up arrow
        self.rts.handle_input('UP')
        self.assertEqual(self.rts.state.selected_index, 0)
    
    def test_handle_input_typing(self):
        """Test character input"""
        self.rts.handle_input('h')
        self.rts.handle_input('e')
        self.rts.handle_input('l')
        self.rts.handle_input('l')
        self.rts.handle_input('o')
        
        self.assertEqual(self.rts.state.query, "hello")
        self.assertEqual(self.rts.state.cursor_pos, 5)
    
    def test_handle_input_backspace(self):
        """Test backspace handling"""
        self.rts.state.query = "test"
        self.rts.state.cursor_pos = 4
        
        self.rts.handle_input('BACKSPACE')
        
        self.assertEqual(self.rts.state.query, "tes")
        self.assertEqual(self.rts.state.cursor_pos, 3)
    
    def test_trigger_search(self):
        """Test search triggering with debounce"""
        self.rts.trigger_search()
        
        self.assertTrue(self.rts.state.is_searching)
        self.assertGreater(self.rts.state.last_update, 0)


class TestSmartSearcher(unittest.TestCase):
    """Test smart searcher enhancement"""
    
    def test_create_smart_searcher(self):
        """Test creating enhanced smart searcher"""
        mock_searcher = Mock()
        original_search = Mock(return_value=[])
        mock_searcher.search = original_search
        mock_searcher.nlp = None
        
        smart_searcher = create_smart_searcher(mock_searcher)
        
        # Test that smart search replaces original search
        self.assertNotEqual(smart_searcher.search, original_search)
        
        # Test that smart search works
        results = smart_searcher.search("test query")
        self.assertIsInstance(results, list)
    
    def test_smart_search_combines_results(self):
        """Test that smart search combines results from different modes"""
        mock_searcher = Mock()
        
        # Mock different results for different modes
        def mock_search(query, mode=None, **kwargs):
            if mode == "exact":
                return [Mock(file_path=Path("/exact/result"))]
            elif mode == "smart":
                return [Mock(file_path=Path("/smart/result"))]
            elif mode == "regex":
                return [Mock(file_path=Path("/regex/result"))]
            return []
        
        mock_searcher.search = mock_search
        mock_searcher.nlp = None
        
        smart_searcher = create_smart_searcher(mock_searcher)
        results = smart_searcher.search("test.*query")
        
        # Should have results from multiple modes
        self.assertGreater(len(results), 1)


class TestIntegration(unittest.TestCase):
    """Integration tests for the complete search system"""
    
    def setUp(self):
        """Set up integration test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.test_dir = Path(self.temp_dir) / ".claude" / "projects"
        self.test_dir.mkdir(parents=True)
        
        # Create multiple test conversations
        for i in range(3):
            project_dir = self.test_dir / f"project_{i}"
            project_dir.mkdir()
            
            chat_file = project_dir / f"chat_{i}.jsonl"
            conversations = [
                {
                    "type": "user",
                    "content": f"Question about Python project {i}",
                    "timestamp": f"2024-01-{15+i}T10:00:00Z"
                },
                {
                    "type": "assistant",
                    "content": f"Here's the answer for project {i}",
                    "timestamp": f"2024-01-{15+i}T10:01:00Z"
                }
            ]
            
            with open(chat_file, 'w') as f:
                for conv in conversations:
                    f.write(json.dumps(conv) + '\n')
    
    def tearDown(self):
        """Clean up test environment"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def test_end_to_end_search(self):
        """Test complete search workflow"""
        searcher = ConversationSearcher()
        
        # Search across all projects
        results = searcher.search(
            "Python project",
            search_dir=self.test_dir,
            mode="smart"
        )
        
        # Should find results from all projects
        self.assertEqual(len(results), 3)
        
        # Results should be from different files
        file_paths = {r.file_path for r in results}
        self.assertEqual(len(file_paths), 3)
    
    @patch('realtime_search.threading.Thread')
    @patch('realtime_search.KeyboardHandler')
    @patch('realtime_search.TerminalDisplay')
    def test_realtime_search_integration(self, mock_display, mock_keyboard, mock_thread):
        """Test real-time search with mocked terminal"""
        # Skip the search thread for testing
        mock_thread_instance = Mock()
        mock_thread.return_value = mock_thread_instance
        
        searcher = Mock()
        extractor = Mock()
        
        # Pre-populate results
        test_result = SearchResult(
            file_path=Path("/test/file"),
            conversation_id="test-id",
            matched_content="Python test",
            context="Python test",
            speaker="human",
            timestamp=datetime.now(),
            relevance_score=1.0,
            line_number=0
        )
        
        # Mock keyboard input - just escape to exit
        mock_kb_instance = Mock()
        mock_keyboard.return_value.__enter__.return_value = mock_kb_instance
        mock_kb_instance.get_key.side_effect = ['ESC']
        
        rts = RealTimeSearch(searcher, extractor)
        # Pre-populate state with results
        rts.state.results = [test_result]
        
        selected = rts.run()
        
        # Should return None (escaped)
        self.assertIsNone(selected)


if __name__ == '__main__':
    unittest.main()