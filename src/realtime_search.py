#!/usr/bin/env python3
"""
Fixed real-time search interface for Claude Conversation Extractor.
Properly handles arrow keys without printing escape sequences.
"""

import os
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import List, Optional

# Platform-specific imports for keyboard handling
if sys.platform == "win32":
    import msvcrt
else:
    import select
    import termios
    import tty


# Constants
TERMINAL_UPDATE_RATE = 0.1
GET_KEY_SLEEP_TIME = 0.01
MAX_PREVIEW_LENGTH = 60
MAX_RESULTS_DISPLAYED = 10
PROJECT_NAME_MAX_LENGTH = 20
DEBOUNCE_DELAY_MS = 300
DEFAULT_MAX_RESULTS = 20
SEARCH_WORKER_POLL_INTERVAL = 0.05
TIMEOUT_WORKER_THREAD = 0.5
HEADER_LINES_COUNT = 4
MAJOR_SEPARATOR_WIDTH = 60
SEARCH_BOX_OFFSET = 3


@dataclass
class SearchState:
    """Maintains the current state of the search interface"""

    query: str = ""
    cursor_pos: int = 0
    results: List = None
    selected_index: int = 0
    last_update: float = 0
    is_searching: bool = False

    def __post_init__(self):
        if self.results is None:
            self.results = []


class KeyboardHandler:
    """Cross-platform keyboard input handler with fixed arrow key support"""

    def __init__(self):
        self.old_settings = None
        if sys.platform != "win32":
            self.stdin_fd = sys.stdin.fileno()

    def __enter__(self):
        """Set up raw input mode"""
        if sys.platform != "win32":
            self.old_settings = termios.tcgetattr(self.stdin_fd)
            tty.setraw(self.stdin_fd)
        return self

    def __exit__(self, *args):
        """Restore terminal settings"""
        if sys.platform != "win32" and self.old_settings:
            termios.tcsetattr(self.stdin_fd, termios.TCSADRAIN, self.old_settings)

    def get_key(self, timeout: float = TERMINAL_UPDATE_RATE) -> Optional[str]:
        """Get a single keypress with timeout - FIXED version"""
        if sys.platform == "win32":
            # Windows implementation
            start_time = time.time()
            while time.time() - start_time < timeout:
                if msvcrt.kbhit():
                    key = msvcrt.getch()
                    # Handle special keys
                    if key in (b"\x00", b"\xe0"):  # Special key prefix
                        key = msvcrt.getch()
                        if key == b"H":  # Up arrow
                            return "UP"
                        elif key == b"P":  # Down arrow
                            return "DOWN"
                        elif key == b"K":  # Left arrow
                            return "LEFT"
                        elif key == b"M":  # Right arrow
                            return "RIGHT"
                    elif key == b"\x1b":  # ESC
                        return "ESC"
                    elif key == b"\r":  # Enter
                        return "ENTER"
                    elif key == b"\x08":  # Backspace
                        return "BACKSPACE"
                    else:
                        try:
                            return key.decode("utf-8")
                        except UnicodeDecodeError:
                            return None
                time.sleep(GET_KEY_SLEEP_TIME)
            return None
        else:
            # Unix/Linux/macOS implementation - FIXED
            if select.select([sys.stdin], [], [], timeout)[0]:
                # Read one character
                char = sys.stdin.read(1)
                
                # Check for escape sequences
                if char == '\x1b':  # ESC character
                    # Check if there are more characters (arrow key sequence)
                    if select.select([sys.stdin], [], [], 0.0)[0]:
                        # Read the rest of the escape sequence
                        seq = []
                        seq.append(sys.stdin.read(1))  # Should be '['
                        
                        # Read the next character
                        if select.select([sys.stdin], [], [], 0.0)[0]:
                            seq.append(sys.stdin.read(1))
                            
                            # Check for arrow keys
                            if seq == ['[', 'A']:
                                return "UP"
                            elif seq == ['[', 'B']:
                                return "DOWN"
                            elif seq == ['[', 'C']:
                                return "RIGHT"
                            elif seq == ['[', 'D']:
                                return "LEFT"
                            else:
                                # Unknown escape sequence - consume any remaining chars
                                while select.select([sys.stdin], [], [], 0.0)[0]:
                                    sys.stdin.read(1)
                                return None
                        return None
                    else:
                        # Just ESC by itself
                        return "ESC"
                        
                elif char == '\r' or char == '\n':
                    return "ENTER"
                elif char == '\x7f' or char == '\x08':
                    return "BACKSPACE"
                elif char == '\x03':  # Ctrl+C
                    raise KeyboardInterrupt
                elif ord(char) >= 32 and ord(char) < 127:  # Printable characters
                    return char
                else:
                    return None
            return None


class TerminalDisplay:
    """Manages terminal display for real-time search"""

    def __init__(self):
        self.last_result_count = 0
        self.header_lines = HEADER_LINES_COUNT  # Lines used by header

    def clear_screen(self):
        """Clear the terminal screen"""
        if sys.platform == "win32":
            os.system("cls")
        else:
            print("\033[2J\033[H", end="")

    def move_cursor(self, row: int, col: int):
        """Move cursor to specific position"""
        print(f"\033[{row};{col}H", end="", flush=True)

    def clear_line(self):
        """Clear current line"""
        print("\033[2K", end="", flush=True)

    def save_cursor(self):
        """Save current cursor position"""
        print("\033[s", end="", flush=True)

    def restore_cursor(self):
        """Restore saved cursor position"""
        print("\033[u", end="", flush=True)

    def draw_header(self):
        """Draw the search interface header"""
        self.move_cursor(1, 1)
        print("🔍 REAL-TIME SEARCH")
        print("=" * MAJOR_SEPARATOR_WIDTH)
        print("Type to search • ↑↓ to select • Enter to open • ESC to exit")
        print("─" * MAJOR_SEPARATOR_WIDTH)

    def draw_results(self, results: List, selected_index: int, query: str):
        """Draw search results with highlighting"""
        # Clear previous results
        for i in range(self.last_result_count + 1):
            self.move_cursor(self.header_lines + i + 1, 1)
            self.clear_line()

        if not results:
            self.move_cursor(self.header_lines + 1, 1)
            if query:
                print(f"No results found for '{query}'")
            else:
                print("Start typing to search...")
        else:
            # Display results
            for i, result in enumerate(results[:MAX_RESULTS_DISPLAYED]):  # Show max MAX_RESULTS_DISPLAYED results
                self.move_cursor(self.header_lines + i + 1, 1)

                # Format result display
                if i == selected_index:
                    print("▸ ", end="")  # Selection indicator
                else:
                    print("  ", end="")

                # Show result info
                date_str = result.timestamp.strftime("%Y-%m-%d")
                project = Path(result.file_path).parent.name[:PROJECT_NAME_MAX_LENGTH]

                # Highlight matching text
                preview = result.context[:MAX_PREVIEW_LENGTH].replace("\n", " ")
                if query.lower() in preview.lower():
                    # Simple highlighting - could be improved
                    idx = preview.lower().find(query.lower())
                    preview = (
                        preview[:idx]
                        + f"\033[93m{preview[idx:idx + len(query)]}\033[0m"
                        + preview[idx + len(query) :]
                    )

                print(f"📄 {date_str} | {project} | {preview}...")

        self.last_result_count = len(results[:MAX_RESULTS_DISPLAYED])

    def draw_search_box(self, query: str, cursor_pos: int):
        """Draw the search input box"""
        # Position at bottom of results
        row = self.header_lines + self.last_result_count + SEARCH_BOX_OFFSET
        self.move_cursor(row, 1)
        self.clear_line()
        print("─" * MAJOR_SEPARATOR_WIDTH)

        self.move_cursor(row + 1, 1)
        self.clear_line()
        print(f"Search: {query}", end="")

        # Position cursor
        self.move_cursor(row + 1, 9 + cursor_pos)
        sys.stdout.flush()


class RealTimeSearch:
    """Main real-time search interface with fixed arrow key handling"""

    def __init__(self, searcher, extractor):
        self.searcher = searcher
        self.extractor = extractor
        self.display = TerminalDisplay()
        self.state = SearchState()
        self.search_thread = None
        self.search_lock = threading.Lock()
        self.results_cache = {}
        self.debounce_delay = DEBOUNCE_DELAY_MS / 1000  # Convert to seconds
        self.stop_event = threading.Event()  # For clean thread shutdown

    def _process_search_request(self):
        """Process a single search request (extracted for testing)"""
        with self.search_lock:
            if not self.state.is_searching:
                return False

            # Check debounce
            if time.time() - self.state.last_update < self.debounce_delay:
                return False

            query = self.state.query
            self.state.is_searching = False

        if not query:
            with self.search_lock:
                self.state.results = []
            return True

        # Check cache
        if query in self.results_cache:
            with self.search_lock:
                self.state.results = self.results_cache[query]
            return True

        # Perform search
        try:
            # Allow search_dir to be set on instance for testing
            search_kwargs = {
                "query": query,
                "mode": "smart",
                "max_results": DEFAULT_MAX_RESULTS,
                "case_sensitive": False,
            }
            if hasattr(self, "search_dir") and self.search_dir:
                search_kwargs["search_dir"] = self.search_dir

            results = self.searcher.search(**search_kwargs)

            # Cache results
            self.results_cache[query] = results

            with self.search_lock:
                self.state.results = results
                self.state.selected_index = 0
        except Exception:
            # Handle search errors gracefully
            with self.search_lock:
                self.state.results = []

        return True

    def search_worker(self):
        """Background thread for searching"""
        while not self.stop_event.is_set():
            # Wait for search request
            time.sleep(SEARCH_WORKER_POLL_INTERVAL)
            self._process_search_request()

        # Thread cleanup
        self.stop_event.clear()

    def handle_input(self, key: str) -> Optional[str]:
        """Handle keyboard input and return action if needed"""
        if not key:
            return None
            
        if key == "ESC":
            return "exit"

        elif key == "ENTER":
            if self.state.results and 0 <= self.state.selected_index < len(
                self.state.results
            ):
                return "select"

        elif key == "UP":
            if self.state.results:
                self.state.selected_index = max(0, self.state.selected_index - 1)
                return "redraw"  # Signal to redraw

        elif key == "DOWN":
            if self.state.results:
                self.state.selected_index = min(
                    len(self.state.results[:MAX_RESULTS_DISPLAYED]) - 1, self.state.selected_index + 1
                )
                return "redraw"  # Signal to redraw

        elif key == "LEFT":
            self.state.cursor_pos = max(0, self.state.cursor_pos - 1)
            return "redraw"

        elif key == "RIGHT":
            self.state.cursor_pos = min(
                len(self.state.query), self.state.cursor_pos + 1
            )
            return "redraw"

        elif key == "BACKSPACE":
            if self.state.cursor_pos > 0:
                self.state.query = (
                    self.state.query[: self.state.cursor_pos - 1]
                    + self.state.query[self.state.cursor_pos :]
                )
                self.state.cursor_pos -= 1
                self.trigger_search()
                return "redraw"

        elif key and len(key) == 1 and ord(key) >= 32 and ord(key) < 127:  # Printable character
            self.state.query = (
                self.state.query[: self.state.cursor_pos]
                + key
                + self.state.query[self.state.cursor_pos :]
            )
            self.state.cursor_pos += 1
            self.trigger_search()
            return "redraw"

        return None

    def trigger_search(self):
        """Trigger a new search with debouncing"""
        with self.search_lock:
            self.state.last_update = time.time()
            self.state.is_searching = True
            # Clear cache for partial matches
            keys_to_remove = [
                k
                for k in self.results_cache.keys()
                if not k.startswith(self.state.query)
            ]
            for k in keys_to_remove:
                del self.results_cache[k]

    def stop(self):
        """Stop the search worker thread cleanly"""
        if self.search_thread and self.search_thread.is_alive():
            self.stop_event.set()
            self.search_thread.join(timeout=TIMEOUT_WORKER_THREAD)

    def run(self) -> Optional[Path]:
        """Run the real-time search interface"""
        # Start search worker thread
        self.search_thread = threading.Thread(target=self.search_worker, daemon=True)
        self.search_thread.start()

        try:
            self.display.clear_screen()
            self.display.draw_header()

            with KeyboardHandler() as keyboard:
                # Initial draw
                self.display.draw_results(
                    self.state.results[:MAX_RESULTS_DISPLAYED],
                    self.state.selected_index,
                    self.state.query,
                )
                self.display.draw_search_box(
                    self.state.query, self.state.cursor_pos
                )
                
                while True:
                    # Get keyboard input
                    key = keyboard.get_key(timeout=TERMINAL_UPDATE_RATE)
                    
                    if key:
                        action = self.handle_input(key)

                        if action == "exit":
                            return None
                        elif action == "select":
                            selected_result = self.state.results[
                                self.state.selected_index
                            ]
                            return selected_result.file_path
                        elif action == "redraw" or action is None:
                            # Redraw the interface
                            self.display.draw_results(
                                self.state.results[:MAX_RESULTS_DISPLAYED],
                                self.state.selected_index,
                                self.state.query,
                            )
                            self.display.draw_search_box(
                                self.state.query, self.state.cursor_pos
                            )
                    else:
                        # Check if results have changed (from search thread)
                        # and redraw if needed
                        pass

        except KeyboardInterrupt:
            return None
        finally:
            # Clean up
            self.stop()  # Stop the search thread
            self.display.clear_screen()


def create_smart_searcher(searcher):
    """Enhance the searcher with smart search capabilities"""
    original_search = searcher.search

    def smart_search(query: str, **kwargs):
        """Smart search that automatically uses the best search mode"""
        # Remove mode parameter if provided
        kwargs.pop("mode", None)

        # Try different search strategies
        results = []

        # 1. First try exact match (fast)
        exact_results = original_search(query, mode="exact", **kwargs)
        results.extend(exact_results)

        # 2. If query looks like regex, try regex search
        if any(c in query for c in r".*+?[]{}()^$|\\"):
            try:
                regex_results = original_search(query, mode="regex", **kwargs)
                # Add results not already found
                existing_paths = {r.file_path for r in results}
                for r in regex_results:
                    if r.file_path not in existing_paths:
                        results.append(r)
            except Exception:
                pass  # Invalid regex, skip

        # 3. Smart search for partial matches
        smart_results = original_search(query, mode="smart", **kwargs)
        existing_paths = {r.file_path for r in results}
        for r in smart_results:
            if r.file_path not in existing_paths:
                results.append(r)

        # 4. If semantic search is available, use it for better matches
        if hasattr(searcher, "nlp") and searcher.nlp:
            try:
                semantic_results = original_search(query, mode="semantic", **kwargs)
                existing_paths = {r.file_path for r in results}
                for r in semantic_results:
                    if r.file_path not in existing_paths:
                        results.append(r)
            except Exception:
                pass  # Semantic search failed

        # Sort by relevance (timestamp for now, could be improved)
        try:
            results.sort(
                key=lambda x: x.timestamp if x.timestamp else datetime.min, reverse=True
            )
        except (AttributeError, TypeError):
            # If timestamp comparison fails, sort by relevance score
            try:
                results.sort(
                    key=lambda x: getattr(x, "relevance_score", 0), reverse=True
                )
            except Exception:
                pass  # Keep original order if sorting fails

        # Limit results
        max_results = kwargs.get("max_results", DEFAULT_MAX_RESULTS)
        return results[:max_results]

    # Replace the search method
    searcher.search = smart_search
    return searcher


def main():
    """Main entry point for running real-time search directly."""
    from extract_claude_logs import ClaudeConversationExtractor
    from search_conversations import ConversationSearcher
    
    # Initialize components
    extractor = ClaudeConversationExtractor()
    searcher = ConversationSearcher()
    smart_searcher = create_smart_searcher(searcher)
    
    # Create and run real-time search
    rts = RealTimeSearch(smart_searcher, extractor)
    selected_file = rts.run()
    
    if selected_file:
        print(f"\n✅ Selected: {selected_file}")
        # Could optionally extract here
    else:
        print("\n👋 Search cancelled")


if __name__ == "__main__":
    main()