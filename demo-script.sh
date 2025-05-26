#!/bin/bash
# Demo script for Claude Conversation Extractor
# This creates a perfect demo showing all features

# Colors for better visibility
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Claude Conversation Extractor Demo ===${NC}"
echo ""
sleep 2

echo -e "${GREEN}$ # First, let's see what Claude sessions we have${NC}"
sleep 1
echo -e "${GREEN}$ claude-extract --list${NC}"
sleep 1
python3 extract_claude_logs.py --list
sleep 3

echo ""
echo -e "${GREEN}$ # Extract the most recent conversation${NC}"
sleep 1
echo -e "${GREEN}$ claude-extract --extract 1${NC}"
sleep 1
python3 extract_claude_logs.py --extract 1
sleep 3

echo ""
echo -e "${GREEN}$ # Extract multiple conversations at once${NC}"
sleep 1
echo -e "${GREEN}$ claude-extract --recent 3${NC}"
sleep 1
python3 extract_claude_logs.py --recent 3
sleep 3

echo ""
echo -e "${GREEN}$ # Check what was created${NC}"
sleep 1
echo -e "${GREEN}$ ls -la ~/Desktop/Claude\ logs/ | head -5${NC}"
sleep 1
ls -la ~/Desktop/Claude\ logs/ | head -5
sleep 2

echo ""
echo -e "${GREEN}$ # View a conversation excerpt${NC}"
sleep 1
echo -e "${GREEN}$ head -20 ~/Desktop/Claude\ logs/claude-conversation-*.md | tail -15${NC}"
sleep 1
head -20 ~/Desktop/Claude\ logs/claude-conversation-*.md | tail -15
sleep 3

echo ""
echo -e "${BLUE}✨ Clean markdown files ready for viewing, searching, or archiving!${NC}"
sleep 2