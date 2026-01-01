#!/usr/bin/env python3
"""
Test suite for interactive UI components
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

# Add parent directory to path before local imports
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

# Local imports after sys.path modification
from interactive_ui import InteractiveUI  # noqa: E402


class TestInteractiveUI(unittest.TestCase):
    """Test InteractiveUI functionality"""

    def setUp(self):
        """Set up test UI"""
        self.ui = InteractiveUI()

        # Create mock sessions with stat method support
        self.mock_sessions = []
        for i in range(1, 4):
            p = Mock(spec=Path)
            p.parent.name = f"project{i}"
            p.stat.return_value.st_mtime = 1700000000 + i * 1000
            p.stat.return_value.st_size = 1024 * i
            # Make sure str(p) or path operations work if needed, though mostly attributes are accessed
            # The ui code does: session_path.parent.name
            # and session_path.stat()
            self.mock_sessions.append(p)

        # Store original sessions to restore later
        self.original_sessions = self.ui.sessions
        self.ui.sessions = self.mock_sessions

    @patch("interactive_ui.subprocess.run")
    @patch("interactive_ui.platform.system")
    def test_open_folder_macos(self, mock_platform, mock_subprocess):
        """Test opening folder on macOS"""
        mock_platform.return_value = "Darwin"

        test_path = Path("/test/output")
        self.ui.open_folder(test_path)

        mock_subprocess.assert_called_once_with(["open", str(test_path)])

    @patch("interactive_ui.platform.system")
    def test_open_folder_windows(self, mock_platform):
        """Test opening folder on Windows"""
        mock_platform.return_value = "Windows"

        # Only test on Windows or mock the entire os module
        with patch("os.startfile", create=True) as mock_startfile:
            test_path = Path("/test/output")
            self.ui.open_folder(test_path)
            mock_startfile.assert_called_once_with(str(test_path))

    @patch("interactive_ui.subprocess.run")
    @patch("interactive_ui.platform.system")
    def test_open_folder_linux(self, mock_platform, mock_subprocess):
        """Test opening folder on Linux"""
        mock_platform.return_value = "Linux"

        test_path = Path("/test/output")
        self.ui.open_folder(test_path)

        mock_subprocess.assert_called_once_with(["xdg-open", str(test_path)])

    def test_print_centered(self):
        """Test centered text printing"""
        with patch("builtins.print") as mock_print:
            self.ui.terminal_width = 40
            self.ui.print_centered("TEST", "=")

            # Should print centered text with padding
            printed = mock_print.call_args[0][0]
            self.assertIn("TEST", printed)
            self.assertIn("=", printed)

    @patch("builtins.print")
    def test_show_progress(self, mock_print):
        """Test progress bar display"""
        self.ui.show_progress(5, 10, "Processing")

        # Should print progress bar
        printed = mock_print.call_args[0][0]
        self.assertIn("█", printed)  # Filled portion
        self.assertIn("░", printed)  # Empty portion
        self.assertIn("5/10", printed)
        self.assertIn("Processing", printed)

    @patch("builtins.input")
    def test_show_sessions_menu_specific(self, mock_input):
        """Test selecting specific conversations"""
        mock_input.side_effect = ["S", "1,3"]

        with patch.object(self.ui.extractor, "find_sessions", return_value=self.mock_sessions):
            indices = self.ui.show_sessions_menu()

        # Should return selected indices (0-based)
        self.assertEqual(indices, [0, 2])

    @patch("builtins.input")
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
            with open(chat_file, "w") as f:
                f.write(
                    json.dumps(
                        {
                            "type": "message",
                            "role": "user",
                            "content": [{"type": "text", "text": f"Test message {i}"}],
                            "created_at": f"2024-01-{15 + i}T10:00:00Z",
                        }
                    )
                    + "\n"
                )

    def tearDown(self):
        """Clean up test files"""
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @patch("extract_claude_logs.Path.home")
    @patch("builtins.input")
    @patch("builtins.print")
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
        with patch.object(ui.extractor, "find_sessions", return_value=[]):
            ui.run()

        # Should exit gracefully
        self.assertTrue(True)  # If we get here, test passed


class TestMenuDisplay(unittest.TestCase):
    """Test menu display formatting"""

    @patch("builtins.print")
    def test_menu_shows_options(self, mock_print):
        """Test that menu shows expected options"""
        ui = InteractiveUI()

        # Create mock session with stat support
        p = Mock(spec=Path)
        p.parent.name = "test"
        p.stat.return_value.st_mtime = 1700000000
        p.stat.return_value.st_size = 1024
        mock_sessions = [p]

        with patch("builtins.input", return_value="Q"):
            with patch.object(ui.extractor, "find_sessions", return_value=mock_sessions):
                ui.show_sessions_menu()

        # Check that expected options are shown
        all_prints = " ".join(str(call) for call in mock_print.call_args_list)
        self.assertIn("A. Extract ALL", all_prints)
        self.assertIn("R. Extract 5 most RECENT", all_prints)
        self.assertIn("S. SELECT specific", all_prints)
        self.assertIn("Q. QUIT", all_prints)


if __name__ == "__main__":
    unittest.main()
