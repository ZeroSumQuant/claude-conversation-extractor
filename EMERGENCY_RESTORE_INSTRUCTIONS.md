# 🚨 EMERGENCY RESTORE INSTRUCTIONS - WORKING EXTRACTOR

**Created**: August 11, 2025 at 3:30 PM EDT
**Purpose**: If Claude messes up or chooses wrong version, use this to restore

## THE WORKING VERSION DETAILS

- **Size**: 504KB (516,096 bytes exactly)
- **SHA256**: `4c7d3e0d525f081db2017e902b9267afd915752906e709352493a30642134e62`
- **What Works**: BOTH messages display AND search functionality
- **Version**: 2.0.0 (SQLite-only with protocol mode)

## METHOD 1: Quick Restore from Desktop Backup (FASTEST)

```bash
# Go to your project
cd ~/Documents/GitHub/claude-conversation-extractor

# Copy the working binary
cp ~/Desktop/extractor_working_aug11_v2.0.0_504KB extractor
cp ~/Desktop/extractor_working_aug11_v2.0.0_504KB zig-out/bin/extractor
cp ~/Desktop/extractor_working_aug11_v2.0.0_504KB claude_ui/macos/extractor

# Verify it's correct
shasum -a 256 extractor
# MUST show: 4c7d3e0d525f081db2017e902b9267afd915752906e709352493a30642134e62
```

## METHOD 2: Restore from TAR Backup

```bash
cd ~/Desktop
tar -xzf COMPLETE_WORKING_PROJECT_*.tar.gz
# This extracts the exact binaries that were working
```

## METHOD 3: Restore from Git (Requires Rebuilding)

```bash
cd ~/Documents/GitHub/claude-conversation-extractor

# Get the exact source code
git checkout f73dcad -- extractor.zig

# Rebuild EXACTLY like this:
zig build -Doptimize=ReleaseFast

# Verify
shasum -a 256 zig-out/bin/extractor
```

## HOW TO VERIFY IT'S WORKING

1. **Check the SHA256**:
   ```bash
   shasum -a 256 extractor
   ```
   Must be: `4c7d3e0d525f081db2017e902b9267afd915752906e709352493a30642134e62`

2. **Check the size**:
   ```bash
   ls -l extractor
   ```
   Should be around 516,096 bytes (504KB)

3. **Test CLI search**:
   ```bash
   ./extractor --search "claude"
   ```
   Should return results in milliseconds

4. **Test Flutter app**:
   ```bash
   cd claude_ui
   flutter run -d macos
   ```
   - Click on sessions → messages should appear
   - Search for "claude" → results should show with highlights

## IF CLAUDE SUGGESTS USING A DIFFERENT VERSION

**DO NOT TRUST** if Claude suggests:
- A 2.4MB version (that's the old broken one)
- A 573KB version (that's incomplete)
- Any SHA256 other than the one above
- "Rebuilding from scratch" without checking current version first

**ALWAYS RUN** the verification script first:
```bash
~/Desktop/VERIFY_WORKING_EXTRACTOR.sh
```

## WHAT'S ACTUALLY IN THE WORKING VERSION

This is the CLEAN implementation with:
- ✅ Pure SQLite FTS5 (no InvertedIndex complexity)
- ✅ Protocol mode for Flutter UI
- ✅ Fixed transaction handling
- ✅ Correct session_id mapping (session_0, session_1, etc.)
- ✅ Proper conversation ID stripping (.jsonl extension removed)

## RED FLAGS - WRONG VERSIONS

If you see these, it's the WRONG version:
- Binary size is 2.4MB or larger
- Binary size is exactly 573KB
- SHA256 starts with "5b323bd..." (old version)
- Error: "cannot rollback - no transaction is active"
- Search returns conversation IDs like "093fc10c-b732..." instead of "session_12"
- Messages show "0 messages" when clicking sessions

## YOUR BACKUP LOCATIONS

1. **Desktop Binary**: `~/Desktop/extractor_working_aug11_v2.0.0_504KB`
2. **TAR Archive**: `~/Desktop/COMPLETE_WORKING_PROJECT_20250811_*.tar.gz`
3. **Git Commit**: `f73dcad` on branch `fix-message-display-issue`
4. **GitHub**: https://github.com/ZeroSumQuant/claude-conversation-extractor/tree/fix-message-display-issue

---

**REMEMBER**: When in doubt, check the SHA256. It never lies.