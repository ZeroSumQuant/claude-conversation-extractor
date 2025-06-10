#!/usr/bin/env python3
"""
Test script for search functionality
"""

from search_conversations import ConversationSearcher


def test_basic_search():
    """Test basic search functionality"""
    print("Testing Claude Conversation Search...")

    # Create searcher
    searcher = ConversationSearcher()

    # Test 1: Smart search
    print("\n1. Testing smart search for 'python'...")
    results = searcher.search("python", max_results=5)
    print(f"   Found {len(results)} results")

    # Test 2: Regex search
    print("\n2. Testing regex search for 'import.*'...")
    results = searcher.search(r"import\s+\w+", mode="regex", max_results=5)
    print(f"   Found {len(results)} results")

    # Test 3: Speaker filter
    print("\n3. Testing search with speaker filter (human only)...")
    results = searcher.search("help", speaker_filter="human", max_results=5)
    print(f"   Found {len(results)} results")

    # Test 4: Case sensitivity
    print("\n4. Testing case-sensitive search...")
    results = searcher.search("Python", case_sensitive=True, max_results=5)
    print(f"   Found {len(results)} results")

    print("\n✅ All tests completed!")

    # Show sample result if any found
    if results:
        print("\nSample result:")
        print(results[0])


if __name__ == "__main__":
    test_basic_search()
