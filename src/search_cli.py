#!/usr/bin/env python3
"""
Simple CLI search for Claude conversations without terminal control.
This is used when running `claude-search` from the command line.
"""

import sys

# Handle both package and direct execution imports
try:
    from .search_conversations import ConversationSearcher
    from .realtime_search import create_smart_searcher
    from .extract_claude_logs import ClaudeConversationExtractor
except ImportError:
    # Fallback for direct execution or when not installed as package
    from search_conversations import ConversationSearcher
    from realtime_search import create_smart_searcher
    from extract_claude_logs import ClaudeConversationExtractor


def main():
    """Main entry point for CLI search."""
    # Get search term from stdin or arguments
    if len(sys.argv) > 1:
        # Search term provided as argument
        search_term = " ".join(sys.argv[1:])
    else:
        # Prompt for search term
        try:
            search_term = input("🔍 Enter search term: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n👋 Search cancelled")
            return
    
    if not search_term:
        print("❌ No search term provided")
        return
    
    print(f"\n🔍 Searching for: '{search_term}'")
    print("=" * 60)
    
    # Initialize searcher
    searcher = ConversationSearcher()
    smart_searcher = create_smart_searcher(searcher)
    
    # Perform search
    results = smart_searcher.search(search_term, max_results=20)
    
    if results:
        print(f"\n✅ Found {len(results)} results across conversations:\n")
        
        # Group by file
        by_file = {}
        for result in results:
            fname = result.file_path.name
            if fname not in by_file:
                by_file[fname] = []
            by_file[fname].append(result)
        
        # Display results
        sessions = []
        session_paths = []
        extractor = ClaudeConversationExtractor()
        all_sessions = extractor.find_sessions()
        
        for i, (fname, file_results) in enumerate(by_file.items(), 1):
            session_id = fname.replace('.jsonl', '')
            sessions.append((fname, session_id))
            
            # Find the actual file path
            for session_path in all_sessions:
                if session_path.name == fname:
                    session_paths.append(session_path)
                    break
            
            print(f"{i}. Session {session_id[:8]}... ({len(file_results)} matches)")
            
            # Show first match preview
            first = file_results[0]
            preview = first.matched_content[:150].replace('\n', ' ')
            print(f"   {first.speaker}: {preview}...")
            print()
        
        # Offer to view or extract conversations
        if session_paths:
            print("\n" + "=" * 60)
            print("Options:")
            print("  V. VIEW a conversation")
            print("  E. EXTRACT all conversations")
            print("  Q. QUIT")
            
            try:
                choice = input("\nYour choice: ").strip().upper()
                
                if choice == 'V':
                    # View conversation
                    if len(session_paths) == 1:
                        # Only one result, view it directly
                        extractor.display_conversation(session_paths[0])
                        
                        # After viewing, offer to extract
                        extract_choice = input("\n📤 Extract this conversation? (y/N): ").strip().lower()
                        if extract_choice == 'y':
                            conversation = extractor.extract_conversation(session_paths[0])
                            if conversation:
                                output = extractor.save_as_markdown(conversation, sessions[0][1])
                                print(f"✅ Saved: {output.name}")
                    else:
                        # Multiple results, let user choose
                        print("\nSelect conversation to view:")
                        for i, (fname, sid) in enumerate(sessions, 1):
                            print(f"  {i}. {sid[:8]}...")
                        
                        try:
                            view_num = int(input("\nEnter number (1-{}): ".format(len(sessions))))
                            if 1 <= view_num <= len(session_paths):
                                extractor.display_conversation(session_paths[view_num - 1])
                                
                                # After viewing, offer to extract
                                extract_choice = input("\n📤 Extract this conversation? (y/N): ").strip().lower()
                                if extract_choice == 'y':
                                    conversation = extractor.extract_conversation(session_paths[view_num - 1])
                                    if conversation:
                                        output = extractor.save_as_markdown(conversation, sessions[view_num - 1][1])
                                        print(f"✅ Saved: {output.name}")
                        except (ValueError, IndexError):
                            print("❌ Invalid selection")
                
                elif choice == 'E':
                    # Extract all found conversations
                    for i, (session_path, (fname, sid)) in enumerate(zip(session_paths, sessions), 1):
                        print(f"\n📤 Extracting session {i}...")
                        conversation = extractor.extract_conversation(session_path)
                        if conversation:
                            output = extractor.save_as_markdown(conversation, sid)
                            print(f"✅ Saved: {output.name}")
                
                elif choice == 'Q':
                    print("\n👋 Goodbye!")
                    
            except (EOFError, KeyboardInterrupt):
                print("\n👋 Search cancelled")
    else:
        print(f"\n❌ No matches found for '{search_term}'")
        print("\n💡 Tips:")
        print("   - Try a more general search term")
        print("   - Search is case-insensitive by default")
        print("   - Partial matches are included")


if __name__ == "__main__":
    main()