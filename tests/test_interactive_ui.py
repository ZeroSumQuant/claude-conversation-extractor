#!/usr/bin/env python3
"""
Test suite for interactive UI components
"""

import unittest
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import tempfile
import json

import sys
sys.path.append(str(Path(__file__).parent.parent))

from interactive_ui import InteractiveUI
from search_conversations import SearchResult
from datetime import datetime


class TestInteractiveUI(unittest.TestCase):
    """Test InteractiveUI functionality"""
    
    def setUp(self):
        """Set up test UI"""
        self.ui = InteractiveUI()
        
        # Create mock sessions
        self.mock_sessions = [
            Path("/test/.claude/projects/project1/chat_1.jsonl"),
            Path("/test/.claude/projects/project2/chat_2.jsonl"),
            Path("/test/.claude/projects/project3/chat_3.jsonl")
        ]
        # Store original sessions to restore later
        self.original_sessions = self.ui.sessions
        self.ui.sessions = self.mock_sessions
    
    @patch('interactive_ui.RealTimeSearch')
    @patch('interactive_ui.create_smart_searcher')
    def test_search_conversations_with_result(self, mock_create_smart, mock_rts_class):
        """Test search conversations when user selects a result"""
        # Mock the smart searcher
        mock_smart_searcher = Mock()
        mock_create_smart.return_value = mock_smart_searcher
        
        # Mock RealTimeSearch instance
        mock_rts = Mock()
        mock_rts_class.return_value = mock_rts
        
        # Mock that user selected the second file
        mock_rts.run.return_value = Path("/test/.claude/projects/project2/chat_2.jsonl")
        
        # Run search
        indices = self.ui.search_conversations()
        
        # Should return index [1] (second file)
        self.assertEqual(indices, [1])
        
        # Verify smart searcher was created
        mock_create_smart.assert_called_once_with(self.ui.searcher)
        
        # Verify RealTimeSearch was created and run
        mock_rts_class.assert_called_once_with(mock_smart_searcher, self.ui.extractor)
        mock_rts.run.assert_called_once()
    
    @patch('interactive_ui.RealTimeSearch')
    @patch('interactive_ui.create_smart_searcher')
    def test_search_conversations_cancelled(self, mock_create_smart, mock_rts_class):
        """Test search conversations when user cancels"""
        # Mock the smart searcher
        mock_smart_searcher = Mock()
        mock_create_smart.return_value = mock_smart_searcher
        
        # Mock RealTimeSearch instance
        mock_rts = Mock()
        mock_rts_class.return_value = mock_rts
        
        # Mock that user cancelled (returns None)
        mock_rts.run.return_value = None
        
        # Run search
        indices = self.ui.search_conversations()
        
        # Should return empty list
        self.assertEqual(indices, [])
    
    @patch('interactive_ui.RealTimeSearch')
    @patch('interactive_ui.create_smart_searcher')
    @patch('builtins.input')
    @patch('builtins.print')
    def test_search_conversations_file_not_found(self, mock_print, mock_input, 
                                                mock_create_smart, mock_rts_class):
        """Test search conversations when selected file is not in sessions"""
        # Mock the smart searcher
        mock_smart_searcher = Mock()
        mock_create_smart.return_value = mock_smart_searcher
        
        # Mock RealTimeSearch instance
        mock_rts = Mock()
        mock_rts_class.return_value = mock_rts
        
        # Mock that user selected a file not in sessions list
        mock_rts.run.return_value = Path("/test/.claude/projects/unknown/chat_x.jsonl")
        
        # Run search
        indices = self.ui.search_conversations()
        
        # Should return empty list
        self.assertEqual(indices, [])
        
        # Should show error message
        error_calls = [call for call in mock_print.call_args_list 
                      if "Error: Selected file not found" in str(call)]
        self.assertTrue(len(error_calls) > 0)
    
    @patch('interactive_ui.subprocess.run')
    @patch('interactive_ui.platform.system')
    def test_open_folder_macos(self, mock_platform, mock_subprocess):
        """Test opening folder on macOS"""
        mock_platform.return_value = "Darwin"
        
        test_path = Path("/test/output")
        self.ui.open_folder(test_path)
        
        mock_subprocess.assert_called_once_with(["open", str(test_path)])
    
    @patch('interactive_ui.platform.system')
    def test_open_folder_windows(self, mock_platform):
        """Test opening folder on Windows"""
        mock_platform.return_value = "Windows"
        
        # Only test on Windows or mock the entire os module
        with patch('os.startfile', create=True) as mock_startfile:
            test_path = Path("/test/output")
            self.ui.open_folder(test_path)
            mock_startfile.assert_called_once_with(str(test_path))
    
    @patch('interactive_ui.subprocess.run')
    @patch('interactive_ui.platform.system')
    def test_open_folder_linux(self, mock_platform, mock_subprocess):
        """Test opening folder on Linux"""
        mock_platform.return_value = "Linux"
        
        test_path = Path("/test/output")
        self.ui.open_folder(test_path)
        
        mock_subprocess.assert_called_once_with(["xdg-open", str(test_path)])
    
    def test_print_centered(self):
        """Test centered text printing"""
        with patch('builtins.print') as mock_print:
            self.ui.terminal_width = 40
            self.ui.print_centered("TEST", "=")
            
            # Should print centered text with padding
            printed = mock_print.call_args[0][0]
            self.assertIn("TEST", printed)
            self.assertIn("=", printed)
    
    @patch('builtins.print')
    def test_show_progress(self, mock_print):
        """Test progress bar display"""
        self.ui.show_progress(5, 10, "Processing")
        
        # Should print progress bar
        printed = mock_print.call_args[0][0]
        self.assertIn("█", printed)  # Filled portion
        self.assertIn("░", printed)  # Empty portion
        self.assertIn("5/10", printed)
        self.assertIn("Processing", printed)
    
    @patch('builtins.input')
    def test_show_sessions_menu_all(self, mock_input):
        """Test selecting all conversations"""
        # Mock the extractor's find_sessions method
        with patch.object(self.ui.extractor, 'find_sessions', return_value=self.mock_sessions):
            mock_input.return_value = "A"
            
            indices = self.ui.show_sessions_menu()
            
            # Should return all indices for our mock sessions
            self.assertEqual(indices, [0, 1, 2])
    
    @patch('builtins.input')
    def test_show_sessions_menu_recent(self, mock_input):
        """Test selecting recent conversations"""
        # Mock the extractor's find_sessions method
        with patch.object(self.ui.extractor, 'find_sessions', return_value=self.mock_sessions):
            mock_input.return_value = "R"
            
            indices = self.ui.show_sessions_menu()
            
            # Should return first 5 (or all if less)
            self.assertEqual(indices, [0, 1, 2])
    
    @patch('builtins.input')
    def test_show_sessions_menu_specific(self, mock_input):
        """Test selecting specific conversations"""
        mock_input.side_effect = ["S", "1,3"]
        
        indices = self.ui.show_sessions_menu()
        
        # Should return selected indices (0-based)
        self.assertEqual(indices, [0, 2])
    
    @patch('builtins.input')
    @patch('interactive_ui.InteractiveUI.search_conversations')
    def test_show_sessions_menu_find(self, mock_search, mock_input):
        """Test selecting find option"""
        mock_input.return_value = "F"
        mock_search.return_value = [1]
        
        indices = self.ui.show_sessions_menu()
        
        # Should call search and return its result
        mock_search.assert_called_once()
        self.assertEqual(indices, [1])
    
    @patch('builtins.input')
    def test_show_sessions_menu_quit(self, mock_input):
        """Test quitting from menu"""
        mock_input.return_value = "Q"
        
        indices = self.ui.show_sessions_menu()
        
        # Should return empty list
        self.assertEqual(indices, [])


class TestInteractiveUIIntegration(unittest.TestCase):
    """Integration tests for interactive UI with real files"""
    
    def setUp(self):
        """Set up test environment"""
        self.temp_dir = tempfile.mkdtemp()
        self.claude_dir = Path(self.temp_dir) / ".claude" / "projects"
        self.claude_dir.mkdir(parents=True)
        
        # Create test conversation files
        for i in range(3):
            project_dir = self.claude_dir / f"project_{i}"
            project_dir.mkdir()
            
            chat_file = project_dir / f"chat_{i}.jsonl"
            with open(chat_file, 'w') as f:
                f.write(json.dumps({
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "text", "text": f"Test message {i}"}],
                    "created_at": f"2024-01-{15+i}T10:00:00Z"
                }) + '\n')
    
    def tearDown(self):
        """Clean up test files"""
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    @patch('extract_claude_logs.Path.home')
    @patch('builtins.input')
    @patch('builtins.print')
    def test_full_workflow(self, mock_print, mock_input, mock_home):
        """Test complete UI workflow"""
        mock_home.return_value = Path(self.temp_dir)
        
        # Mock user inputs
        mock_input.side_effect = [
            "1",  # Select first suggested location
            "Q",  # Quit from sessions menu
        ]
        
        ui = InteractiveUI()
        
        # Mock the extractor to avoid real file searches
        with patch.object(ui.extractor, 'find_sessions', return_value=[]):
            ui.run()
        
        # Should exit gracefully
        self.assertTrue(True)  # If we get here, test passed


class TestMenuDisplay(unittest.TestCase):
    """Test menu display formatting"""
    
    @patch('builtins.print')
    def test_menu_shows_realtime_search(self, mock_print):
        """Test that menu shows real-time search option"""
        ui = InteractiveUI()
        ui.sessions = [Path("/test/chat.jsonl")]
        
        with patch('builtins.input', return_value="Q"):
            ui.show_sessions_menu()
        
        # Check that real-time search is mentioned
        all_prints = ' '.join(str(call) for call in mock_print.call_args_list)
        self.assertIn("real-time search", all_prints.lower())
        self.assertIn("F. FIND", all_prints)


if __name__ == '__main__':
    unittest.main()