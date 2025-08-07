#!/usr/bin/env python3
"""
Extract clean conversation logs from Claude Code's internal JSONL files

This tool parses the undocumented JSONL format used by Claude Code to store
conversations locally in ~/.claude/projects/ and exports them as clean,
readable markdown files.
"""

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Import detailed export functionality
try:
    from detailed_export import DetailedTranscriptExtractor
    DETAILED_EXPORT_AVAILABLE = True
except ImportError:
    DETAILED_EXPORT_AVAILABLE = False

# Import export format handlers
try:
    from export_formats import ExportManager
    EXPORT_FORMATS_AVAILABLE = True
except ImportError:
    EXPORT_FORMATS_AVAILABLE = False

# Import statistics analyzer
try:
    from conversation_stats import ConversationAnalyzer
    STATS_AVAILABLE = True
except ImportError:
    STATS_AVAILABLE = False


class ClaudeConversationExtractor:
    """Extract and convert Claude Code conversations from JSONL to markdown."""

    def __init__(self, output_dir: Optional[Path] = None):
        """Initialize the extractor with Claude's directory and output location."""
        self.claude_dir = Path.home() / ".claude" / "projects"
        self.export_manager = None

        if output_dir:
            self.output_dir = Path(output_dir)
            self.output_dir.mkdir(parents=True, exist_ok=True)
        else:
            # Try multiple possible output directories
            possible_dirs = [
                Path.home() / "Desktop" / "Claude logs",
                Path.home() / "Documents" / "Claude logs",
                Path.home() / "Claude logs",
                Path.cwd() / "claude-logs",
            ]

            # Use the first directory we can create
            for dir_path in possible_dirs:
                try:
                    dir_path.mkdir(parents=True, exist_ok=True)
                    # Test if we can write to it
                    test_file = dir_path / ".test"
                    test_file.touch()
                    test_file.unlink()
                    self.output_dir = dir_path
                    break
                except Exception:
                    continue
            else:
                # Fallback to current directory
                self.output_dir = Path.cwd() / "claude-logs"
                self.output_dir.mkdir(exist_ok=True)

        print(f"📁 Saving logs to: {self.output_dir}")
        
        # Initialize export manager if available
        if EXPORT_FORMATS_AVAILABLE:
            self.export_manager = ExportManager(self.output_dir)

    def find_sessions(self, project_path: Optional[str] = None) -> List[Path]:
        """Find all JSONL session files, sorted by most recent first."""
        if project_path:
            search_dir = self.claude_dir / project_path
        else:
            search_dir = self.claude_dir

        sessions = []
        if search_dir.exists():
            for jsonl_file in search_dir.rglob("*.jsonl"):
                sessions.append(jsonl_file)
        return sorted(sessions, key=lambda x: x.stat().st_mtime, reverse=True)

    def extract_conversation(self, jsonl_path: Path) -> List[Dict[str, str]]:
        """Extract conversation messages from a JSONL file."""
        conversation = []

        try:
            with open(jsonl_path, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())

                        # Extract user messages
                        if entry.get("type") == "user" and "message" in entry:
                            msg = entry["message"]
                            if isinstance(msg, dict) and msg.get("role") == "user":
                                content = msg.get("content", "")
                                text = self._extract_text_content(content)

                                if text and text.strip():
                                    conversation.append(
                                        {
                                            "role": "user",
                                            "content": text,
                                            "timestamp": entry.get("timestamp", ""),
                                        }
                                    )

                        # Extract assistant messages
                        elif entry.get("type") == "assistant" and "message" in entry:
                            msg = entry["message"]
                            if isinstance(msg, dict) and msg.get("role") == "assistant":
                                content = msg.get("content", [])
                                text = self._extract_text_content(content)

                                if text and text.strip():
                                    conversation.append(
                                        {
                                            "role": "assistant",
                                            "content": text,
                                            "timestamp": entry.get("timestamp", ""),
                                        }
                                    )

                    except json.JSONDecodeError:
                        continue
                    except Exception:
                        # Silently skip problematic entries
                        continue

        except Exception as e:
            print(f"❌ Error reading file {jsonl_path}: {e}")

        return conversation

    def _extract_text_content(self, content) -> str:
        """Extract text from various content formats Claude uses."""
        if isinstance(content, str):
            return content
        elif isinstance(content, list):
            # Extract text from content array
            text_parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text_parts.append(item.get("text", ""))
            return "\n".join(text_parts)
        else:
            return str(content)

    def save_as_markdown(
        self, conversation: List[Dict[str, str]], session_id: str
    ) -> Optional[Path]:
        """Save conversation as clean markdown file."""
        if not conversation:
            return None

        # Get timestamp from first message
        first_timestamp = conversation[0].get("timestamp", "")
        if first_timestamp:
            try:
                # Parse ISO timestamp
                dt = datetime.fromisoformat(first_timestamp.replace("Z", "+00:00"))
                date_str = dt.strftime("%Y-%m-%d")
                time_str = dt.strftime("%H:%M:%S")
            except Exception:
                date_str = datetime.now().strftime("%Y-%m-%d")
                time_str = ""
        else:
            date_str = datetime.now().strftime("%Y-%m-%d")
            time_str = ""

        filename = f"claude-conversation-{date_str}-{session_id[:8]}.md"
        output_path = self.output_dir / filename

        with open(output_path, "w", encoding="utf-8") as f:
            f.write("# Claude Conversation Log\n\n")
            f.write(f"Session ID: {session_id}\n")
            f.write(f"Date: {date_str}")
            if time_str:
                f.write(f" {time_str}")
            f.write("\n\n---\n\n")

            for msg in conversation:
                if msg["role"] == "user":
                    f.write("## 👤 User\n\n")
                    f.write(f"{msg['content']}\n\n")
                else:
                    f.write("## 🤖 Claude\n\n")
                    f.write(f"{msg['content']}\n\n")
                f.write("---\n\n")

        return output_path
    
    def save_with_format(self, conversation: List[Dict[str, str]], session_id: str,
                        format: str = "markdown") -> Optional[Path]:
        """
        Save conversation in specified format.
        
        Args:
            conversation: List of message dictionaries
            session_id: Session identifier
            format: Export format (markdown, json, html)
            
        Returns:
            Path to saved file or None if failed
        """
        if not conversation:
            return None
        
        if not EXPORT_FORMATS_AVAILABLE or not self.export_manager:
            # Fallback to markdown if export formats not available
            return self.save_as_markdown(conversation, session_id)
        
        try:
            # Build metadata
            metadata = {
                "date": datetime.now().strftime("%Y-%m-%d %H:%M"),
                "message_count": len(conversation),
                "project": self.claude_dir.name
            }
            
            # Export using the manager
            return self.export_manager.export(conversation, session_id, format, metadata)
            
        except Exception as e:
            print(f"❌ Error exporting as {format}: {e}")
            # Fallback to markdown
            return self.save_as_markdown(conversation, session_id)
    
    def extract_detailed_transcript(self, jsonl_path: Path) -> Optional[Path]:
        """
        Extract detailed transcript including tool calls and responses.
        
        Args:
            jsonl_path: Path to JSONL file
            
        Returns:
            Path to saved detailed transcript or None if not available
        """
        if not DETAILED_EXPORT_AVAILABLE:
            print("⚠️  Detailed export module not available")
            return None
        
        try:
            extractor = DetailedTranscriptExtractor(include_system_messages=False)
            messages = extractor.extract_detailed_conversation(jsonl_path)
            
            if not messages:
                return None
            
            # Generate output filename
            session_id = jsonl_path.stem
            date_str = datetime.now().strftime("%Y-%m-%d")
            filename = f"claude-detailed-{date_str}-{session_id[:8]}.md"
            output_path = self.output_dir / filename
            
            # Save detailed transcript
            extractor.save_detailed_markdown(messages, output_path, include_raw_json=False)
            
            return output_path
            
        except Exception as e:
            print(f"❌ Error extracting detailed transcript: {e}")
            return None

    def list_recent_sessions(self, limit: int = 10) -> List[Path]:
        """List recent sessions with details."""
        sessions = self.find_sessions()

        if not sessions:
            print("❌ No Claude sessions found in ~/.claude/projects/")
            print("💡 Make sure you've used Claude Code and have conversations saved.")
            return []

        print(f"\n📚 Found {len(sessions)} Claude sessions:\n")

        for i, session in enumerate(sessions[:limit]):
            project = session.parent.name
            session_id = session.stem
            modified = datetime.fromtimestamp(session.stat().st_mtime)

            # Get file size
            size = session.stat().st_size
            size_kb = size / 1024

            print(f"{i + 1}. {project}")
            print(f"   Session: {session_id[:8]}...")
            print(f"   Modified: {modified.strftime('%Y-%m-%d %H:%M')}")
            print(f"   Size: {size_kb:.1f} KB")
            print()

        return sessions[:limit]

    def extract_multiple(
        self, sessions: List[Path], indices: List[int], detailed: bool = False,
        format: str = "markdown"
    ) -> Tuple[int, int]:
        """Extract multiple sessions by index."""
        success = 0
        total = len(indices)

        for idx in indices:
            if 0 <= idx < len(sessions):
                session_path = sessions[idx]
                
                if detailed:
                    # Extract detailed transcript with tool calls
                    output_path = self.extract_detailed_transcript(session_path)
                    if output_path:
                        success += 1
                        print(
                            f"✅ {success}/{total}: {output_path.name} "
                            f"(detailed transcript)"
                        )
                    else:
                        print(f"⏭️  Skipped session {idx + 1} (no detailed data)")
                else:
                    # Standard extraction
                    conversation = self.extract_conversation(session_path)
                    if conversation:
                        if format == "markdown":
                            output_path = self.save_as_markdown(conversation, session_path.stem)
                        else:
                            output_path = self.save_with_format(conversation, session_path.stem, format)
                        
                        if output_path:
                            success += 1
                            msg_count = len(conversation)
                            format_str = f" [{format}]" if format != "markdown" else ""
                            print(
                                f"✅ {success}/{total}: {output_path.name} "
                                f"({msg_count} messages{format_str})"
                            )
                        else:
                            print(f"❌ Failed to save session {idx + 1}")
                    else:
                        print(f"⏭️  Skipped session {idx + 1} (no conversation)")
            else:
                print(f"❌ Invalid session number: {idx + 1}")

        return success, total


def main():
    parser = argparse.ArgumentParser(
        description="Extract Claude Code conversations to clean markdown files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --list                    # List all available sessions
  %(prog)s --extract 1               # Extract the most recent session
  %(prog)s --extract 1,3,5           # Extract specific sessions
  %(prog)s --recent 5                # Extract 5 most recent sessions
  %(prog)s --all                     # Extract all sessions
  %(prog)s --output ~/my-logs        # Specify output directory
  %(prog)s --search "python error"   # Search conversations
  %(prog)s --search-regex "import.*" # Search with regex
        """,
    )
    parser.add_argument("--list", action="store_true", help="List recent sessions")
    parser.add_argument(
        "--extract",
        type=str,
        help="Extract specific session(s) by number (comma-separated)",
    )
    parser.add_argument(
        "--all", "--logs", action="store_true", help="Extract all sessions"
    )
    parser.add_argument(
        "--recent", type=int, help="Extract N most recent sessions", default=0
    )
    parser.add_argument(
        "--output", type=str, help="Output directory for markdown files"
    )
    parser.add_argument(
        "--limit", type=int, help="Limit for --list command", default=10
    )
    parser.add_argument(
        "--interactive",
        "-i",
        "--start",
        "-s",
        action="store_true",
        help="Launch interactive UI for easy extraction",
    )
    parser.add_argument(
        "--export",
        type=str,
        help="Export mode: 'logs' for interactive UI",
    )
    
    # Detailed export argument
    parser.add_argument(
        "--detailed",
        action="store_true",
        help="Export detailed transcript with tool calls and responses (Ctrl+R style)",
    )
    
    # Format argument
    parser.add_argument(
        "--format",
        type=str,
        choices=["markdown", "md", "json", "html"],
        default="markdown",
        help="Export format (default: markdown)",
    )
    
    # Statistics argument
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Generate and display conversation statistics",
    )

    # Search arguments
    parser.add_argument(
        "--search", type=str, help="Search conversations for text (smart search)"
    )
    parser.add_argument(
        "--search-regex", type=str, help="Search conversations using regex pattern"
    )
    parser.add_argument(
        "--search-date-from", type=str, help="Filter search from date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--search-date-to", type=str, help="Filter search to date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--search-speaker",
        choices=["human", "assistant", "both"],
        default="both",
        help="Filter search by speaker",
    )
    parser.add_argument(
        "--case-sensitive", action="store_true", help="Make search case-sensitive"
    )

    args = parser.parse_args()

    # Handle interactive mode
    if args.interactive or (args.export and args.export.lower() == "logs"):
        from interactive_ui import main as interactive_main

        interactive_main()
        return

    # Initialize extractor with optional output directory
    extractor = ClaudeConversationExtractor(args.output)

    # Handle search mode
    if args.search or args.search_regex:
        from datetime import datetime

        from search_conversations import ConversationSearcher

        searcher = ConversationSearcher()

        # Determine search mode and query
        if args.search_regex:
            query = args.search_regex
            mode = "regex"
        else:
            query = args.search
            mode = "smart"

        # Parse date filters
        date_from = None
        date_to = None
        if args.search_date_from:
            try:
                date_from = datetime.strptime(args.search_date_from, "%Y-%m-%d")
            except ValueError:
                print(f"❌ Invalid date format: {args.search_date_from}")
                return

        if args.search_date_to:
            try:
                date_to = datetime.strptime(args.search_date_to, "%Y-%m-%d")
            except ValueError:
                print(f"❌ Invalid date format: {args.search_date_to}")
                return

        # Speaker filter
        speaker_filter = None if args.search_speaker == "both" else args.search_speaker

        # Perform search
        print(f"🔍 Searching for: {query}")
        results = searcher.search(
            query=query,
            mode=mode,
            date_from=date_from,
            date_to=date_to,
            speaker_filter=speaker_filter,
            case_sensitive=args.case_sensitive,
            max_results=30,
        )

        if not results:
            print("❌ No matches found.")
            return

        print(f"\n✅ Found {len(results)} matches across conversations:")

        # Group and display results
        results_by_file = {}
        for result in results:
            if result.file_path not in results_by_file:
                results_by_file[result.file_path] = []
            results_by_file[result.file_path].append(result)

        for file_path, file_results in results_by_file.items():
            print(f"\n📄 {file_path.parent.name} ({len(file_results)} matches)")
            # Show first match preview
            first = file_results[0]
            print(f"   {first.speaker}: {first.matched_content[:100]}...")

        print("\n💡 Tip: Use --interactive mode for more search options and extraction")
        return

    # Handle statistics request
    if args.stats:
        if not STATS_AVAILABLE:
            print("❌ Statistics module not available")
            return
            
        sessions = extractor.find_sessions()
        if not sessions:
            print("❌ No sessions found")
            return
            
        print("📊 Analyzing conversations...")
        analyzer = ConversationAnalyzer()
        
        # Analyze all conversations
        all_conversations = []
        for session_path in sessions[:20]:  # Limit to 20 for performance
            conversation = extractor.extract_conversation(session_path)
            if conversation:
                all_conversations.append((conversation, session_path.stem))
        
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
            stats_file = extractor.output_dir / "conversation_statistics.json"
            analyzer.save_aggregate_stats(agg_stats, stats_file)
            print(f"\n💾 Full statistics saved to: {stats_file}")
        else:
            print("❌ No conversations found to analyze")
        return
    
    # Default action is to list sessions
    if args.list or (
        not args.extract
        and not args.all
        and not args.recent
        and not args.search
        and not args.search_regex
        and not args.stats
    ):
        sessions = extractor.list_recent_sessions(args.limit)

        if sessions and not args.list:
            print("\nTo extract conversations:")
            print("  %(prog)s --extract <number>      # Extract specific session")
            print("  %(prog)s --recent 5              # Extract 5 most recent")
            print("  %(prog)s --all                   # Extract all sessions")

    elif args.extract:
        sessions = extractor.find_sessions()

        # Parse comma-separated indices
        indices = []
        for num in args.extract.split(","):
            try:
                idx = int(num.strip()) - 1  # Convert to 0-based index
                indices.append(idx)
            except ValueError:
                print(f"❌ Invalid session number: {num}")
                continue

        if indices:
            if args.detailed:
                print(f"\n📤 Extracting {len(indices)} session(s) with detailed transcripts...")
            else:
                print(f"\n📤 Extracting {len(indices)} session(s)...")
            success, total = extractor.extract_multiple(sessions, indices, detailed=args.detailed, format=args.format)
            print(f"\n✅ Successfully extracted {success}/{total} sessions")

    elif args.recent:
        sessions = extractor.find_sessions()
        limit = min(args.recent, len(sessions))
        if args.detailed:
            print(f"\n📤 Extracting {limit} most recent sessions with detailed transcripts...")
        else:
            print(f"\n📤 Extracting {limit} most recent sessions...")

        indices = list(range(limit))
        success, total = extractor.extract_multiple(sessions, indices, detailed=args.detailed, format=args.format)
        print(f"\n✅ Successfully extracted {success}/{total} sessions")

    elif args.all:
        sessions = extractor.find_sessions()
        if args.detailed:
            print(f"\n📤 Extracting all {len(sessions)} sessions with detailed transcripts...")
        else:
            print(f"\n📤 Extracting all {len(sessions)} sessions...")

        indices = list(range(len(sessions)))
        success, total = extractor.extract_multiple(sessions, indices, detailed=args.detailed, format=args.format)
        print(f"\n✅ Successfully extracted {success}/{total} sessions")


def launch_interactive():
    """Launch the interactive UI directly."""
    from interactive_ui import main as interactive_main

    interactive_main()


def unified_main():
    """
    Unified entry point for Claude conversation extraction.
    
    Launches interactive UI when called without arguments,
    or processes CLI arguments for direct operations.
    """
    import sys
    
    # Special case: if only argument is 'search', launch search UI
    if len(sys.argv) == 2 and sys.argv[1] == 'search':
        from realtime_search import main as search_main
        return search_main()
    
    # If no arguments provided (just the command name), launch interactive UI
    if len(sys.argv) == 1:
        launch_interactive()
    else:
        # Has arguments - use traditional CLI
        main()


if __name__ == "__main__":
    unified_main()
