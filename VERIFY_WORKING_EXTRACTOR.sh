#!/bin/bash

# VERIFICATION SCRIPT - Run this to check if you have the RIGHT extractor
# Created: August 11, 2025
# This is the WORKING version where both messages AND search work

echo "================================"
echo "EXTRACTOR VERSION VERIFICATION"
echo "================================"

CORRECT_SHA="4c7d3e0d525f081db2017e902b9267afd915752906e709352493a30642134e62"
CORRECT_SIZE="504K"
WORKING_BACKUP="$HOME/Desktop/extractor_working_aug11_v2.0.0_504KB"

echo ""
echo "The CORRECT working extractor should have:"
echo "  SHA256: $CORRECT_SHA"
echo "  Size: approximately $CORRECT_SIZE"
echo ""

# Check main extractor
if [ -f "extractor" ]; then
    CURRENT_SHA=$(shasum -a 256 extractor | cut -d' ' -f1)
    CURRENT_SIZE=$(ls -lh extractor | awk '{print $5}')
    
    echo "Current extractor in this directory:"
    echo "  SHA256: $CURRENT_SHA"
    echo "  Size: $CURRENT_SIZE"
    
    if [ "$CURRENT_SHA" = "$CORRECT_SHA" ]; then
        echo "  ✅ CORRECT VERSION!"
    else
        echo "  ❌ WRONG VERSION!"
        echo ""
        echo "To restore the working version:"
        echo "  cp $WORKING_BACKUP ./extractor"
    fi
else
    echo "❌ No extractor found in current directory"
    echo ""
    echo "To get the working version:"
    echo "  cp $WORKING_BACKUP ./extractor"
fi

echo ""
echo "================================"
echo "BACKUP LOCATIONS:"
echo "================================"
echo "1. Desktop backup: $WORKING_BACKUP"
if [ -f "$WORKING_BACKUP" ]; then
    BACKUP_SHA=$(shasum -a 256 "$WORKING_BACKUP" | cut -d' ' -f1)
    if [ "$BACKUP_SHA" = "$CORRECT_SHA" ]; then
        echo "   ✅ Backup is CORRECT"
    else
        echo "   ⚠️  Backup SHA doesn't match!"
    fi
else
    echo "   ❌ Backup NOT FOUND!"
fi

echo ""
echo "2. Git commit: f73dcad (branch: fix-message-display-issue)"
echo "   To restore from git:"
echo "   git checkout f73dcad -- extractor.zig"
echo "   zig build -Doptimize=ReleaseFast"

echo ""
echo "3. Complete TAR backup: ~/Desktop/COMPLETE_WORKING_PROJECT_*.tar.gz"

echo ""
echo "================================"
echo "HOW TO TEST IF IT'S WORKING:"
echo "================================"
echo "1. Run: ./extractor --version"
echo "   Should show: 2.0.0"
echo ""
echo "2. Run: ./extractor --search 'claude'"
echo "   Should return results quickly"
echo ""
echo "3. In Flutter app:"
echo "   - Messages should display when clicking sessions"
echo "   - Search should work and show results"
echo ""