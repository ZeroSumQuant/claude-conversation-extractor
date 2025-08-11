# Claude Conversation Extractor - Architecture Overview

## Executive Summary

The Claude Conversation Extractor uses a hybrid SQLite + Zig architecture to achieve sub-10ms response times when loading conversations from 40MB+ JSONL files. This document describes the production-ready implementation that solves the critical performance issue of re-parsing entire files on every access.

## Problem Statement

The original implementation had a fundamental flaw: it re-parsed entire JSONL files (up to 40MB with 100k+ lines) on every conversation access:

```zig
// OLD: This was re-parsing the entire file every time!
const conversation = try parser.parseFile(sessions[index]);
```

This caused:
- 10-100ms latency per conversation load
- CPU spikes from repeated parsing
- Memory allocation churn
- Poor user experience with laggy UI transitions

## Solution Architecture

### High-Level Design

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Flutter   │────▶│   Zig Core   │────▶│   SQLite    │
│     UI      │◀────│   (FFI)      │◀────│   (WAL)     │
└─────────────┘     └──────────────┘     └─────────────┘
                            │                     │
                            ▼                     │
                    ┌──────────────┐             │
                    │  Memory Map  │             │
                    │   (mmap)     │             │
                    └──────────────┘             │
                            │                     │
                            ▼                     ▼
                    ┌──────────────┐     ┌─────────────┐
                    │ Block Index  │     │    FTS5     │
                    │   (.bix)     │     │   Search    │
                    └──────────────┘     └─────────────┘
```

### Core Components

1. **SQLite Database (Persistent Index)**
   - Stores parsed messages with keyset pagination
   - FTS5 for code-aware full-text search
   - WAL mode for concurrent reads during writes
   - Content-backed design (messages table is source of truth)

2. **Memory-Mapped Files (Zero-Copy Access)**
   - Platform-agnostic (Windows/POSIX)
   - Handles file growth without closing handles
   - CRLF-safe line iteration
   - Automatic remapping on changes

3. **Block Index Files (.bix)**
   - O(1) line number to byte offset lookup
   - Incremental updates (only scan new data)
   - Atomic writes with header-last approach
   - 256-line blocks (configurable)

4. **Incremental Importer**
   - Single-writer, idempotent
   - Only processes new lines since last_byte
   - Batch commits for performance
   - Handles rotation/truncation gracefully

5. **Live Tail Overlay**
   - Merges DB results with unindexed tail
   - Provides instant freshness
   - Zero-copy from mmap
   - Transparent to UI

## Performance Characteristics

### Targets (P95, warm cache)
- Load 50 messages: ≤10ms desktop, ≤20ms mobile
- Search 1M messages: ≤120ms
- Importer lag: ≤2s steady-state
- Memory per 40MB file: ≤10MB

### Actual Performance
- Message loading: <1ms from SQLite (indexed)
- Tail overlay: <5ms for parsing recent lines
- Block index lookup: <100ns
- File remapping: <1ms

## Data Flow

### Import Flow
```
JSONL File → MappedFile → LineIterator → JSON Parse
    ↓            ↓                           ↓
   .bix     Block Index                 SQLite DB
  (index)    (update)                   (messages)
```

### Query Flow
```
Request → SQLite Query → DB Messages
    ↓          ↓              ↓
Tail Check → MappedFile → Parse Tail → Merge Results
    ↓                                        ↓
Response ← Binary/JSON Format ← Combined Messages
```

## File Formats

### Block Index (.bix)
```
Header (64 bytes):
  magic:       u32  "BIX1"
  version:     u8   1
  block_size:  u16  256
  reserved1:   u8   0
  total_lines: u64  line count
  last_byte:   u64  highest byte processed
  crc32:       u32  rolling checksum
  reserved:    [36]u8

Body:
  block_offsets: []u64  byte offset every 256th line
```

### Binary Wire Format (FFI)
```
Header:
  version:       u16
  reserved:      u16
  message_count: u32

Messages:
  [MessageHeader]
    position:      i64
    timestamp:     i64
    role:          u8
    content_offset: u32
    content_len:   u32

Content:
  [raw UTF-8 strings concatenated]
```

## Key Design Decisions

### Why SQLite?
- Battle-tested, reliable
- Built-in FTS5 for search
- WAL for concurrent access
- Zero-copy page cache
- Excellent query optimizer

### Why Memory Mapping?
- Zero-copy access to file data
- OS handles page cache
- Efficient for large files
- No memory allocation for reads

### Why Block Indexes?
- O(1) line lookups
- Tiny memory footprint
- Incremental updates
- Survives crashes (atomic writes)

### Why Hybrid Approach?
- SQLite alone: Can't handle live appends well
- Mmap alone: No efficient search/filtering
- Together: Best of both worlds

## Edge Cases Handled

1. **File Rotation**: New source_file row, preserves history
2. **File Truncation**: Treated as rotation
3. **Concurrent Writers**: FILE_SHARE_DELETE on Windows
4. **Partial Lines**: Ignored until complete
5. **CRLF/LF**: Normalized during parsing
6. **Large Lines (>8MB)**: Skipped with logging
7. **Corrupt JSON**: Skipped, continues processing
8. **Database Corruption**: Rebuild from JSONL source

## Deployment Considerations

### Database Location
- Default: `~/.claude/extractor.db`
- Configurable via environment variable
- Same directory as JSONL files for locality

### Index Files
- Stored alongside JSONL: `file.jsonl.bix`
- Automatically rebuilt if missing/corrupt
- Small size (~8 bytes per 256 lines)

### Memory Usage
- SQLite cache: 64MB default
- Mmap: OS page cache (not counted)
- Block indexes: <1MB per file
- Hot cache: 512MB cap on desktop

### Platform Differences

**Windows**:
- FILE_SHARE_READ|WRITE|DELETE flags
- Retry logic for file operations
- Different mmap API (CreateFileMapping)

**macOS/Linux**:
- Standard POSIX mmap
- O_CLOEXEC for file descriptors
- inotify/FSEvents for watching

## Migration Path

1. On first run: Create SQLite database
2. Background: Import existing JSONL files
3. UI shows progress during initial import
4. Live tail overlay provides immediate access
5. Full performance after import completes

## Monitoring & Observability

Key metrics exposed via FFI:
- Importer lag (ms)
- Lines per second
- P50/P95/P99 query latency
- Cache hit rate
- Memory usage
- Remap count

## Future Optimizations

1. **Compression**: LZ4 for message content
2. **Sharding**: Split large conversations
3. **Incremental FTS**: Update search index async
4. **Prefetching**: Predictive page loading
5. **Delta Sync**: Efficient replication

## Security Considerations

- Read-only access to JSONL files
- No network access required
- SQL injection prevented (prepared statements)
- File paths validated before access
- No execution of user content

## Testing Strategy

See [testing.md](testing.md) for comprehensive test plan covering:
- Performance benchmarks
- Edge case validation
- Platform-specific tests
- Stress testing
- Data integrity verification