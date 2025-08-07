#!/usr/bin/env python3
"""Interactive terminal UI for Claude Conversation Extractor"""

import os
import platform
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from extract_claude_logs import ClaudeConversationExtractor
from realtime_search import RealTimeSearch, create_smart_searcher
from search_conversations import ConversationSearcher


class InteractiveUI:
    """Interactive terminal UI for easier conversation extraction"""

    def __init__(self, output_dir: Optional[str] = None):
        self.output_dir = output_dir
        self.extractor = ClaudeConversationExtractor(output_dir)
        self.searcher = ConversationSearcher()
        self.sessions: List[Path] = []
        self.terminal_width = shutil.get_terminal_size().columns
        self.detailed_mode = False
        self.export_format = "markdown"

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
        for i, session_path in enumerate(self.sessions[:20], 1):  # Show max 20
            project = session_path.parent.name
            modified = datetime.fromtimestamp(session_path.stat().st_mtime)
            size_kb = session_path.stat().st_size / 1024

            date_str = modified.strftime("%Y-%m-%d %H:%M")
            print(f"  {i:2d}. [{date_str}] {project[:30]:<30} ({size_kb:.1f} KB)")

        if len(self.sessions) > 20:
            print(f"\n  ... and {len(self.sessions) - 20} more conversations")

        print("\n" + "=" * 60)
        print("\nOptions:")
        print("  A. Extract ALL conversations")
        print("  R. Extract 5 most RECENT")
        print("  S. SELECT specific conversations (e.g., 1,3,5)")
        print("  F. FIND conversations (real-time search)")
        print("  D. Extract with DETAILED transcript (tool calls & responses)")
        print("  E. EXPORT in different format (JSON/HTML)")
        print("  T. Show conversation STATISTICS")
        print("  N. Launch NEW high-performance Rust TUI")
        print("  Q. QUIT")

        while True:
            choice = input("\nYour choice: ").strip().upper()

            if choice == "Q":
                return []
            elif choice == "A":
                return list(range(len(self.sessions)))
            elif choice == "R":
                return list(range(min(5, len(self.sessions))))
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
            elif choice == "D":
                # Detailed export with tool calls
                selection = input("Enter conversation numbers for detailed export (e.g., 1,3,5): ").strip()
                try:
                    indices = [int(x.strip()) - 1 for x in selection.split(",")]
                    if all(0 <= i < len(self.sessions) for i in indices):
                        # Mark these for detailed export
                        self.detailed_mode = True
                        return indices
                    else:
                        print("❌ Invalid selection. Please use valid numbers.")
                except ValueError:
                    print("❌ Invalid format. Use comma-separated numbers.")
            elif choice == "E":
                # Export format selection
                print("\nSelect export format:")
                print("  1. Markdown (default)")
                print("  2. JSON")
                print("  3. HTML")
                format_choice = input("Choice (1-3): ").strip()
                format_map = {"1": "markdown", "2": "json", "3": "html"}
                if format_choice in format_map:
                    self.export_format = format_map[format_choice]
                    selection = input("Enter conversation numbers to export (e.g., 1,3,5): ").strip()
                    try:
                        indices = [int(x.strip()) - 1 for x in selection.split(",")]
                        if all(0 <= i < len(self.sessions) for i in indices):
                            return indices
                        else:
                            print("❌ Invalid selection.")
                    except ValueError:
                        print("❌ Invalid format.")
                else:
                    print("❌ Invalid format choice.")
            elif choice == "T":
                # Show statistics
                self.show_statistics()
                input("\nPress Enter to continue...")
                return self.show_sessions_menu()  # Return to menu
            elif choice == "N":
                # Launch Rust TUI
                self.launch_rust_tui()
                # After TUI exits, redisplay menu
                return self.show_sessions_menu()
            else:
                print("❌ Invalid choice. Please try again.")

    def show_progress(self, current: int, total: int, message: str = ""):
        """Display a simple progress bar"""
        bar_width = 40
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
            # Find the index of the selected file
            try:
                index = self.sessions.index(selected_file)
                return [index]
            except ValueError:
                print("\n❌ Error: Selected file not found in sessions list")
                input("\nPress Enter to continue...")
                return []

        return []

    def extract_conversations(self, indices: List[int], output_dir: Path) -> int:
        """Extract selected conversations with progress display"""
        print(f"\n📤 Extracting {len(indices)} conversations...\n")

        # Update the extractor's output directory
        self.extractor.output_dir = output_dir

        # Use the extractor's method with detailed and format options
        success_count, total_count = self.extractor.extract_multiple(
            self.sessions, indices, detailed=self.detailed_mode, format=self.export_format
        )

        print(
            f"\n\n✅ Successfully extracted {success_count}/{total_count} conversations!"
        )
        return success_count

    def launch_rust_tui(self):
        """Launch the high-performance Rust TUI"""
        print("\n🚀 Launching high-performance Rust TUI...")
        
        # Find the TUI binary
        script_dir = Path(__file__).parent
        tui_binary = script_dir / "rust_tui" / "target" / "release" / "claude-tui"
        
        if not tui_binary.exists():
            # Try debug build
            tui_binary = script_dir / "rust_tui" / "target" / "debug" / "claude-tui"
        
        if not tui_binary.exists():
            print("\n❌ Rust TUI not built. Building now...")
            # Try to build it
            rust_dir = script_dir / "rust_tui"
            if rust_dir.exists():
                try:
                    subprocess.run(["cargo", "build", "--release"], 
                                 cwd=rust_dir, check=True)
                    tui_binary = rust_dir / "target" / "release" / "claude-tui"
                except subprocess.CalledProcessError:
                    print("❌ Failed to build Rust TUI")
                    print("Please run: cd rust_tui && cargo build --release")
                    input("\nPress Enter to continue...")
                    return
            else:
                print("❌ Rust TUI directory not found")
                input("\nPress Enter to continue...")
                return
        
        # Launch the TUI
        try:
            subprocess.run([str(tui_binary)], check=False)
        except Exception as e:
            print(f"❌ Error launching TUI: {e}")
            input("\nPress Enter to continue...")
    
    def show_statistics(self):
        """Display conversation statistics"""
        print("\n📊 Analyzing conversations...")
        
        from conversation_stats import ConversationAnalyzer
        
        analyzer = ConversationAnalyzer()
        
        # Analyze all conversations
        all_conversations = []
        for i, session_path in enumerate(self.sessions[:20]):  # Limit to 20 for performance
            conversation = self.extractor.extract_conversation(session_path)
            if conversation:
                all_conversations.append((conversation, session_path.stem))
                self.show_progress(i + 1, min(20, len(self.sessions)), "conversations analyzed")
        
        print()  # New line after progress
        
        if all_conversations:
            # Generate aggregate statistics
            agg_stats = analyzer.analyze_multiple(all_conversations)
            
            # Display statistics
            print("\n" + "=" * 60)
            print("📊 CONVERSATION STATISTICS")
            print("=" * 60)
            print(f"\n📁 Total Conversations: {agg_stats.total_conversations}")
            print(f"💬 Total Messages: {agg_stats.total_messages:,}")
            print(f"  - User Messages: {agg_stats.total_user_messages:,}")
            print(f"  - Assistant Messages: {agg_stats.total_assistant_messages:,}")
            print(f"\n📝 Text Analysis:")
            print(f"  - Total Words: {agg_stats.total_words:,}")
            print(f"  - Estimated Tokens: {agg_stats.estimated_total_tokens:,}")
            print(f"  - Reading Time: {agg_stats.estimated_total_reading_hours:.1f} hours")
            print(f"\n⏰ Time Analysis:")
            if agg_stats.most_active_day:
                print(f"  - Most Active Day: {agg_stats.most_active_day}")
            if agg_stats.most_active_hour is not None:
                print(f"  - Most Active Hour: {agg_stats.most_active_hour}:00")
            print(f"\n📏 Conversation Lengths:")
            print(f"  - Average: {agg_stats.average_conversation_length:.1f} messages")
            print(f"  - Longest: {agg_stats.longest_conversation[1]} messages")
            print(f"  - Shortest: {agg_stats.shortest_conversation[1]} messages")
            
            if agg_stats.common_topics:
                print(f"\n🔤 Top Topics:")
                for topic, count in agg_stats.common_topics[:5]:
                    print(f"  - {topic}: {count} mentions")
            
            # Save to file
            stats_file = self.extractor.output_dir / "conversation_statistics.json"
            analyzer.save_aggregate_stats(agg_stats, stats_file)
            print(f"\n💾 Full statistics saved to: {stats_file}")
        else:
            print("❌ No conversations found to analyze")

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
