#!/usr/bin/env python3
"""
Real-time search interface for Claude Conversation Extractor.
Provides live search results as the user types.
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


@dataclass
class SearchState:
    """Maintains the current state of the search interface"""

    query: str = ""
    cursor_pos: int = 0
    results: List = None
    selected_index: int = 0
    last_update: float = 0
    is_searching: bool = False
    needs_redraw: bool = True  # Track when UI needs updating
    last_drawn_query: str = ""  # Track what was last drawn
    last_drawn_results_count: int = -1  # Track last result count

    def __post_init__(self):
        if self.results is None:
            self.results = []


class KeyboardHandler:
    """Cross-platform keyboard input handler"""

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

    def get_key(self, timeout: float = 0.1) -> Optional[str]:
        """Get a single keypress with timeout"""
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
                time.sleep(0.01)
            return None
        else:
            # Unix/Linux/macOS implementation
            if select.select([sys.stdin], [], [], timeout)[0]:
                key = sys.stdin.read(1)

                # Handle escape sequences
                if key == "\x1b":
                    if select.select([sys.stdin], [], [], 0.1)[0]:
                        seq = sys.stdin.read(2)
                        if seq == "[A":
                            return "UP"
                        elif seq == "[B":
                            return "DOWN"
                        elif seq == "[C":
                            return "RIGHT"
                        elif seq == "[D":
                            return "LEFT"
                    return "ESC"
                elif key == "\r" or key == "\n":
                    return "ENTER"
                elif key == "\x7f" or key == "\x08":
                    return "BACKSPACE"
                elif key == "\x03":  # Ctrl+C
                    raise KeyboardInterrupt
                else:
                    return key
            return None


class TerminalDisplay:
    """Manages terminal display for real-time search"""

    def __init__(self):
        self.last_result_count = 0
        self.header_lines = 3  # Reduced header lines
        self._last_size_check = 0  # Track when we last checked terminal size
        self._get_terminal_size()  # Initialize terminal dimensions

    def clear_screen(self):
        """Clear the terminal screen"""
        if sys.platform == "win32":
            os.system("cls")
        else:
            print("\033[2J\033[H", end="")

    def move_cursor(self, row: int, col: int):
        """Move cursor to specific position"""
        print(f"\033[{row};{col}H", end="")

    def clear_line(self):
        """Clear current line"""
        print("\033[2K", end="")

    def save_cursor(self):
        """Save current cursor position"""
        print("\033[s", end="")

    def restore_cursor(self):
        """Restore saved cursor position"""
        print("\033[u", end="")

    def _get_terminal_size(self):
        """Get current terminal dimensions with caching"""
        import shutil
        # Only check terminal size once per second to avoid syscall overhead
        current_time = time.time()
        if current_time - self._last_size_check > 1.0:
            self.cols, self.rows = shutil.get_terminal_size((80, 24))
            self._last_size_check = current_time
        return self.cols, self.rows

    def set_color(self, color_code: str):
        """Set text color using ANSI codes"""
        print(color_code, end="")

    def reset_color(self):
        """Reset text formatting"""
        print("\033[0m", end="")

    def draw_header(self):
        """Draw the search interface header"""
        self._get_terminal_size()
        self.move_cursor(1, 1)

        # Draw top border
        print(f"┌─ Claude Conversation Search {'─' * (self.cols - 31)}┐", end="")
        self.move_cursor(2, 1)
        print(f"│ ↑↓ Navigate • Enter Select • ESC Exit{' ' * (self.cols - 41)}│", end="")
        self.move_cursor(3, 1)
        print(f"├{'─' * (self.cols - 2)}┤", end="")

    def draw_results(self, results: List, selected_index: int, query: str):
        """Draw search results with highlighting"""
        self._get_terminal_size()

        # Calculate available space for results
        available_lines = self.rows - self.header_lines - 6  # Reserve space for search box
        max_results = min(len(results), available_lines // 3) if results else 0  # 3 lines per result

        # Clear previous results area - ensure we clear at least one line for messages
        lines_to_clear = max(self.last_result_count * 3 + 2, 2)
        for i in range(lines_to_clear):
            self.move_cursor(self.header_lines + i + 1, 1)
            self.clear_line()

        if not results:
            self.move_cursor(self.header_lines + 1, 1)
            self.clear_line()
            if query:
                print(f"│ No results found for '{query}'{' ' * (self.cols - len(query) - 25)}│", end="")
            else:
                print(f"│ Start typing to search...{' ' * (self.cols - 29)}│", end="")
        else:
            # Display results
            for i, result in enumerate(results[:max_results]):
                row_start = self.header_lines + (i * 3) + 1
                self._draw_single_result(result, i == selected_index, query, row_start)

        self.last_result_count = min(len(results), max_results)
        sys.stdout.flush()  # Ensure output is displayed immediately

    def _draw_single_result(self, result, is_selected: bool, query: str, start_row: int):
        """Draw a single result with proper highlighting"""
        # Apply selection highlighting
        if is_selected:
            self.set_color("\033[7m")  # Inverse colors

        # Line 1: Empty line for spacing
        self.move_cursor(start_row, 1)
        self.clear_line()
        print(f"│{' ' * (self.cols - 2)}│", end="")

        # Line 2: Metadata
        self.move_cursor(start_row + 1, 1)
        self.clear_line()
        date_str = result.timestamp.strftime("%Y-%m-%d") if result.timestamp else "Unknown"
        project = Path(result.file_path).parent.name[:30]
        score = f"{result.relevance_score:.0%}"

        metadata = f" 📄 {date_str} | {project} | {score} match"
        print(f"│{metadata:<{self.cols - 2}}│", end="")

        # Line 3: Preview
        self.move_cursor(start_row + 2, 1)
        preview = self._format_preview(result.context, query, self.cols - 6)
        print(f"│   {preview:<{self.cols - 5}}│", end="")

        if is_selected:
            self.reset_color()
        
        sys.stdout.flush()

    def _format_preview(self, text: str, query: str, max_width: int) -> str:
        """Format preview text with query highlighting"""
        # Clean up text
        text = ' '.join(text.split())[:200]  # Normalize whitespace

        # Truncate if needed
        if len(text) > max_width:
            text = text[:max_width - 3] + "..."

        # Highlight query terms
        if query:
            import re
            # Case-insensitive highlighting
            pattern = re.compile(re.escape(query), re.IGNORECASE)
            # Find all matches first
            matches = list(pattern.finditer(text))

            # Replace from end to beginning to preserve indices
            for match in reversed(matches):
                start, end = match.span()
                highlighted = f"\033[93m{text[start:end]}\033[0m"
                text = text[:start] + highlighted + text[end:]

        return text

    def draw_search_box(self, query: str, cursor_pos: int, result_count: int = 0,
                        total_results: int = 0):
        """Draw the search input box at the bottom like Claude interface"""
        self._get_terminal_size()

        # Ensure we have enough space for the search box
        if self.rows < 6:
            return  # Terminal too small to draw search box

        # Draw status bar
        self.move_cursor(max(1, self.rows - 3), 1)
        self.clear_line()
        print(f"├{'─' * (self.cols - 2)}┤", end="")

        # Show result count
        self.move_cursor(max(2, self.rows - 2), 1)
        self.clear_line()
        if total_results > 0:
            status = f"Showing {min(result_count, total_results)} of {total_results} results"
            print(f"│ {status:<{self.cols - 3}}│", end="")
        else:
            print(f"│{' ' * (self.cols - 2)}│", end="")

        # Draw search box border and input
        self.move_cursor(max(3, self.rows - 1), 1)
        self.clear_line()
        print(f"├{'─' * (self.cols - 2)}┤", end="")

        self.move_cursor(max(4, self.rows), 1)
        self.clear_line()
        # Ensure query fits in the available space
        max_query_width = self.cols - 13  # Account for "│ Search: " and "│"
        display_query = query
        if len(query) > max_query_width:
            # Show the end of the query if it's too long
            display_query = "..." + query[-(max_query_width - 3):]

        search_line = f"│ Search: {display_query}"
        print(f"{search_line:<{self.cols - 1}}│", end="")

        # Position cursor correctly
        # Calculate actual cursor position considering truncation
        if len(query) > max_query_width:
            visual_cursor_pos = min(cursor_pos - (len(query) - max_query_width) + 3,
                                    len(display_query))
        else:
            visual_cursor_pos = cursor_pos

        self.move_cursor(max(4, self.rows), 11 + visual_cursor_pos)
        sys.stdout.flush()


class RealTimeSearch:
    """Main real-time search interface"""

    def __init__(self, searcher, extractor):
        self.searcher = searcher
        self.extractor = extractor
        self.display = TerminalDisplay()
        self.state = SearchState()
        self.search_thread = None
        self.search_lock = threading.Lock()
        self.results_cache = {}
        self.debounce_delay = 0.3  # 300ms debounce
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
                self.state.needs_redraw = True  # Trigger redraw
            return True

        # Check cache
        if query in self.results_cache:
            with self.search_lock:
                self.state.results = self.results_cache[query]
                self.state.needs_redraw = True  # Trigger redraw
            return True

        # Perform search
        try:
            # Allow search_dir to be set on instance for testing
            search_kwargs = {
                "query": query,
                "mode": "smart",
                "max_results": 20,
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
                self.state.needs_redraw = True  # Trigger redraw
        except Exception:
            # Handle search errors gracefully
            with self.search_lock:
                self.state.results = []
                self.state.needs_redraw = True  # Trigger redraw

        return True

    def search_worker(self):
        """Background thread for searching"""
        while not self.stop_event.is_set():
            # Wait for search request
            time.sleep(0.05)
            self._process_search_request()

        # Thread cleanup
        self.stop_event.clear()

    def handle_input(self, key: str) -> Optional[str]:
        """Handle keyboard input and return action if needed"""
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

        elif key == "DOWN":
            if self.state.results:
                # Calculate max visible results based on terminal size
                max_visible = (self.display.rows - self.display.header_lines - 6) // 3
                self.state.selected_index = min(
                    min(len(self.state.results), max_visible) - 1,
                    self.state.selected_index + 1
                )

        elif key == "LEFT":
            self.state.cursor_pos = max(0, self.state.cursor_pos - 1)

        elif key == "RIGHT":
            self.state.cursor_pos = min(
                len(self.state.query), self.state.cursor_pos + 1
            )

        elif key == "BACKSPACE":
            if self.state.cursor_pos > 0:
                self.state.query = (
                    self.state.query[: self.state.cursor_pos - 1]
                    + self.state.query[self.state.cursor_pos :]
                )
                self.state.cursor_pos -= 1
                self.trigger_search()

        elif key and len(key) == 1 and ord(key) >= 32:  # Printable character
            self.state.query = (
                self.state.query[: self.state.cursor_pos]
                + key
                + self.state.query[self.state.cursor_pos :]
            )
            self.state.cursor_pos += 1
            self.trigger_search()

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
            self.search_thread.join(timeout=0.5)

    def run(self) -> Optional[Path]:
        """Run the real-time search interface"""
        # Start search worker thread
        self.search_thread = threading.Thread(target=self.search_worker, daemon=True)
        self.search_thread.start()

        try:
            self.display.clear_screen()
            self.display.draw_header()
            
            # Force initial draw
            self.state.needs_redraw = True

            with KeyboardHandler() as keyboard:
                while True:
                    # Only redraw if state has changed
                    if (self.state.needs_redraw or 
                        self.state.query != self.state.last_drawn_query or
                        len(self.state.results) != self.state.last_drawn_results_count):
                        
                        # Draw current state
                        self.display.draw_results(
                            self.state.results,
                            self.state.selected_index,
                            self.state.query,
                        )
                        self.display.draw_search_box(
                            self.state.query,
                            self.state.cursor_pos,
                            len(self.state.results),
                            len(self.state.results)
                        )
                        
                        # Update tracking variables
                        self.state.last_drawn_query = self.state.query
                        self.state.last_drawn_results_count = len(self.state.results)
                        self.state.needs_redraw = False

                    # Get keyboard input
                    key = keyboard.get_key(timeout=0.1)
                    if key:
                        action = self.handle_input(key)
                        self.state.needs_redraw = True  # Any input requires redraw

                        if action == "exit":
                            return None
                        elif action == "select":
                            selected_result = self.state.results[
                                self.state.selected_index
                            ]
                            return selected_result.file_path

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
        max_results = kwargs.get("max_results", 20)
        return results[:max_results]

    # Replace the search method
    searcher.search = smart_search
    return searcher
