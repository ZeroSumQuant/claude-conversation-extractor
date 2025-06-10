#!/usr/bin/env python3
"""Demo of what the interactive UI looks like"""

print("\033[2J\033[H", end="")  # Clear screen

print(
    """
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║   🤖 CLAUDE CONVERSATION EXTRACTOR - INTERACTIVE MODE 🤖      ║
    ║                                                               ║
    ║              Extract your Claude chats with ease!             ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝

📁 Where would you like to save your conversations?

Suggested locations:
  1. /Users/dustinkirby/Desktop/Claude Conversations
  2. /Users/dustinkirby/Documents/Claude Conversations
  3. /Users/dustinkirby/Downloads/Claude Conversations
  4. /Users/dustinkirby/claude-conversation-extractor/Claude Conversations

  C. Custom location
  Q. Quit

Select an option (1-4, C, or Q): _
"""
)

print("\n--- After selecting folder, user sees: ---\n")

print(
    """
🔍 Finding your Claude conversations...

✅ Found 23 conversations!

   1. [2025-06-05 14:23] luca-dev-assistant              (45.2 KB)
   2. [2025-06-05 12:15] cake-deterministic-wrapper      (23.1 KB)
   3. [2025-06-04 18:45] claude-extractor-improvements   (12.8 KB)
   4. [2025-06-04 09:30] python-optimization-tips        (34.5 KB)
   5. [2025-06-03 22:10] react-component-debugging       (56.3 KB)
   6. [2025-06-03 15:42] sql-query-optimization          (8.9 KB)
   7. [2025-06-02 11:20] docker-compose-setup            (15.4 KB)
   8. [2025-06-01 19:55] api-authentication-jwt          (28.7 KB)
   9. [2025-05-31 08:30] machine-learning-basics         (41.2 KB)
  10. [2025-05-30 16:45] git-workflow-best-practices     (19.6 KB)

  ... and 13 more conversations

============================================================

Options:
  A. Extract ALL conversations
  R. Extract 5 most RECENT
  S. SELECT specific conversations (e.g., 1,3,5)
  Q. QUIT

Your choice: _
"""
)

print("\n--- After selecting extraction option: ---\n")

print(
    """
📤 Extracting 5 conversations...

[████████████████████████████████████████] 5/5 Extracting luca-dev-assistant...

✅ Successfully extracted 5/5 conversations!

📁 Files saved to: /Users/dustinkirby/Desktop/Claude Conversations

🗂️  Open output folder? (Y/n): _
"""
)

print("\n--- Final screen: ---\n")

print(
    """
✨ Press Enter to exit..."""
)
