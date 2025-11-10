#!/usr/bin/env python3
"""Interactive terminal UI for Claude Conversation Extractor"""

import os
import platform
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Optional

# Handle both package and direct execution imports
try:
    from .extract_claude_logs import ClaudeConversationExtractor
    from .realtime_search import RealTimeSearch, create_smart_searcher
    from .search_conversations import ConversationSearcher
except ImportError:
    # Fallback for direct execution or when not installed as package
    from extract_claude_logs import ClaudeConversationExtractor
    from realtime_search import RealTimeSearch, create_smart_searcher
    from search_conversations import ConversationSearcher


# Constants
SESSION_DISPLAY_LIMIT = 20
PROJECT_LENGTH = 30
MAJOR_SEPARATOR_WIDTH = 60
PROGRESS_BAR_WIDTH = 40
RECENT_SESSIONS_LIMIT = 5


class InteractiveUI:
    """Interactive terminal UI for easier conversation extraction"""

    def __init__(self, output_dir: Optional[str] = None):
        self.output_dir = output_dir
        self.extractor = ClaudeConversationExtractor(output_dir)
        self.searcher = ConversationSearcher()
        self.sessions: List[Path] = []
        self.terminal_width = shutil.get_terminal_size().columns

    def clear_screen(self):
        """Clear the terminal screen"""
        # Use ANSI escape codes for cross-platform compatibility
        print("\033[2J\033[H", end="")

    def print_banner(self):
        """Print a cool ASCII banner"""
        # Bright magenta color
        MAGENTA = "\033[95m"
        RESET = "\033[0m"
        BOLD = "\033[1m"

        banner = f"""{MAGENTA}{BOLD}

 ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗
██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝
██║     ██║     ███████║██║   ██║██║  ██║█████╗
██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝
╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗
 ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
███████╗██╗  ██╗████████╗██████╗  █████╗  ██████╗████████╗
██╔════╝╚██╗██╔╝╚══██╔══╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
█████╗   ╚███╔╝    ██║   ██████╔╝███████║██║        ██║
██╔══╝   ██╔██╗    ██║   ██╔══██╗██╔══██║██║        ██║
███████╗██╔╝ ██╗   ██║   ██║  ██║██║  ██║╚██████╗   ██║
╚══════╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝

{RESET}"""
        print(banner)

    def print_centered(self, text: str, char: str = "="):
        """Print text centered with decorative characters"""
        padding = (self.terminal_width - len(text) - 2) // 2
        print(f"{char * padding} {text} {char * padding}")

    def get_folder_selection(self) -> Optional[Path]:
        """Simple folder selection dialog"""
        self.clear_screen()
        self.print_banner()
        print("\n📁 Where would you like to save your conversations?\n")

        # Suggest common locations
        home = Path.home()
        suggestions = [
            home / "Desktop" / "Claude Conversations",
            home / "Documents" / "Claude Conversations",
            home / "Downloads" / "Claude Conversations",
            Path.cwd() / "Claude Conversations",
        ]

        print("Suggested locations:")
        for i, path in enumerate(suggestions, 1):
            print(f"  {i}. {path}")

        print("\n  C. Custom location")
        print("  Q. Quit")

        while True:
            choice = input("\nSelect an option (1-4, C, or Q): ").strip().upper()

            if choice == "Q":
                return None
            elif choice == "C":
                custom_path = input("\nEnter custom path: ").strip()
                if custom_path:
                    return Path(custom_path).expanduser()
            elif choice.isdigit() and 1 <= int(choice) <= len(suggestions):
                return suggestions[int(choice) - 1]
            else:
                print("❌ Invalid choice. Please try again.")

    def show_sessions_menu(self) -> List[int]:
        """Display sessions and let user select which to extract"""
        self.clear_screen()
        self.print_banner()

        # Get all sessions
        print("\n🔍 Finding your Claude conversations...")
        self.sessions = self.extractor.find_sessions()

        if not self.sessions:
            print("\n❌ No Claude conversations found!")
            print("Make sure you've used Claude Code at least once.")
            input("\nPress Enter to exit...")
            return []

        print(f"\n✅ Found {len(self.sessions)} conversations!\n")

        # Display sessions
        for i, session_path in enumerate(self.sessions[:SESSION_DISPLAY_LIMIT], 1):  # Show max SESSION_DISPLAY_LIMIT
            project = session_path.parent.name
            modified = datetime.fromtimestamp(session_path.stat().st_mtime)
            size_kb = session_path.stat().st_size / 1024

            date_str = modified.strftime("%Y-%m-%d %H:%M")
            print(f"  {i:2d}. [{date_str}] {project[:PROJECT_LENGTH]:<{PROJECT_LENGTH}} ({size_kb:.1f} KB)")

        if len(self.sessions) > SESSION_DISPLAY_LIMIT:
            print(f"\n  ... and {len(self.sessions) - SESSION_DISPLAY_LIMIT} more conversations")

        print("\n" + "=" * MAJOR_SEPARATOR_WIDTH)
        print("\nOptions:")
        print("  A. Extract ALL conversations")
        print("  R. Extract 5 most RECENT")
        print("  S. SELECT specific conversations (e.g., 1,3,5)")
        print("  F. SEARCH conversations (real-time search)")
        print("  Q. QUIT")

        while True:
            choice = input("\nYour choice: ").strip().upper()

            if choice == "Q":
                return []
            elif choice == "A":
                return list(range(len(self.sessions)))
            elif choice == "R":
                return list(range(min(RECENT_SESSIONS_LIMIT, len(self.sessions))))
            elif choice == "S":
                selection = input("Enter conversation numbers (e.g., 1,3,5): ").strip()
                try:
                    indices = [int(x.strip()) - 1 for x in selection.split(",")]
                    # Validate indices
                    if all(0 <= i < len(self.sessions) for i in indices):
                        return indices
                    else:
                        print("❌ Invalid selection. Please use valid numbers.")
                except ValueError:
                    print("❌ Invalid format. Use comma-separated numbers.")
            elif choice == "F":
                # Search functionality
                search_results = self.search_conversations()
                if search_results:
                    return search_results
            else:
                print("❌ Invalid choice. Please try again.")

    def show_progress(self, current: int, total: int, message: str = ""):
        """Display a simple progress bar"""
        bar_width = PROGRESS_BAR_WIDTH
        progress = current / total if total > 0 else 0
        filled = int(bar_width * progress)
        bar = "█" * filled + "░" * (bar_width - filled)

        print(f"\r[{bar}] {current}/{total} {message}", end="", flush=True)

    def search_conversations(self) -> List[int]:
        """Launch real-time search interface"""
        # Enhance searcher with smart search
        smart_searcher = create_smart_searcher(self.searcher)

        # Create and run real-time search
        rts = RealTimeSearch(smart_searcher, self.extractor)
        selected_file = rts.run()

        if selected_file:
            # View the selected conversation
            self.extractor.display_conversation(Path(selected_file))
            
            # Ask if user wants to extract it
            extract_choice = input("\n📤 Extract this conversation? (y/N): ").strip().lower()
            if extract_choice == 'y':
                try:
                    index = self.sessions.index(Path(selected_file))
                    return [index]
                except ValueError:
                    print("\n❌ Error: Selected file not found in sessions list")
                    input("\nPress Enter to continue...")
            
            # Return empty to go back to menu
            return []

        return []

    def extract_conversations(self, indices: List[int], output_dir: Path) -> int:
        """Extract selected conversations with progress display"""
        print(f"\n📤 Extracting {len(indices)} conversations...\n")

        # Update the extractor's output directory
        self.extractor.output_dir = output_dir

        # Use the extractor's method
        success_count, total_count = self.extractor.extract_multiple(
            self.sessions, indices
        )

        print(
            f"\n\n✅ Successfully extracted {success_count}/{total_count} conversations!"
        )
        return success_count

    def open_folder(self, path: Path):
        """Open the output folder in the system file explorer"""
        try:
            if platform.system() == "Windows":
                os.startfile(str(path))
            elif platform.system() == "Darwin":  # macOS
                subprocess.run(["open", str(path)])
            else:  # Linux
                subprocess.run(["xdg-open", str(path)])
        except Exception:
            pass  # Silently fail if we can't open the folder

    def run(self):
        """Main interactive UI flow"""
        try:
            # Get output folder
            output_dir = self.get_folder_selection()
            if not output_dir:
                print("\n👋 Goodbye!")
                return

            # Get session selection
            selected_indices = self.show_sessions_menu()
            if not selected_indices:
                print("\n👋 Goodbye!")
                return

            # Create output directory if needed
            output_dir.mkdir(parents=True, exist_ok=True)

            # Extract conversations
            success_count = self.extract_conversations(selected_indices, output_dir)

            if success_count > 0:
                print(f"\n📁 Files saved to: {output_dir}")

                # Offer to open the folder
                open_choice = input("\n🗂️  Open output folder? (Y/n): ").strip().lower()
                if open_choice != "n":
                    self.open_folder(output_dir)

            else:
                print("\n❌ No conversations were extracted.")

            input("\n✨ Press Enter to exit...")

        except KeyboardInterrupt:
            print("\n\n👋 Goodbye!")
        except Exception as e:
            print(f"\n❌ Error: {e}")
            input("\nPress Enter to exit...")


def main():
    """Entry point for interactive UI"""
    ui = InteractiveUI()
    ui.run()


if __name__ == "__main__":
    main()
