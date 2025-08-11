# Database Schema Documentation

## Overview

The Claude Conversation Extractor uses SQLite as a persistent index for JSONL conversation data. This document details the database schema, indexes, and design rationale.

## Schema Version

Current Version: 1.0.0

## Tables

### source_files

Tracks JSONL source files and import progress.

```sql
CREATE TABLE source_files (
  id INTEGER PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,      -- Absolute path to JSONL file
  device_id TEXT,                 -- Platform-specific device identifier
  inode TEXT,                     -- File system inode (or Windows file ID)
  size_bytes INTEGER NOT NULL,    -- Current file size
  mtime_ns INTEGER NOT NULL,      -- Modification time (nanoseconds)
  last_line INTEGER NOT NULL DEFAULT 0,   -- Last processed line number
  last_byte INTEGER NOT NULL DEFAULT 0,   -- Last processed byte offset
  truncated INTEGER NOT NULL DEFAULT 0,   -- Flag: was file truncated?
  checksum TEXT                   -- Optional: file checksum for integrity
);
```

**Purpose**: 
- Track import progress per file
- Detect file rotation (different inode)
- Resume imports from last position
- Handle multiple JSONL files

**Key Points**:
- `path` is unique but files can rotate (new row with same path)
- `last_byte` enables incremental import
- `truncated` flag helps handle file shrinkage

### conversations

Metadata and statistics per conversation.

```sql
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,             -- Conversation UUID from JSONL
  display_title TEXT,              -- Human-readable title
  created_at INTEGER,              -- Unix timestamp (first message)
  updated_at INTEGER,              -- Unix timestamp (last message)
  last_position INTEGER NOT NULL DEFAULT 0,  -- Highest position assigned
  message_count INTEGER NOT NULL DEFAULT 0,  -- Total message count
  total_chars INTEGER NOT NULL DEFAULT 0     -- Total character count
);
```

**Purpose**:
- Quick conversation listing
- Statistics without scanning messages
- Position counter for monotonic ordering

**Key Points**:
- No foreign key to source_files (conversations can span files)
- `last_position` ensures monotonic message ordering
- Statistics updated during import

### messages

Core message storage with efficient access patterns.

```sql
CREATE TABLE messages (
  id INTEGER PRIMARY KEY,
  conversation_id TEXT NOT NULL,   -- Foreign key to conversations
  source_file_id INTEGER NOT NULL, -- Foreign key to source_files
  line_no INTEGER NOT NULL,        -- Line number in source file
  byte_start INTEGER NOT NULL,     -- Byte offset start (inclusive)
  byte_end INTEGER NOT NULL,       -- Byte offset end (exclusive)
  position INTEGER NOT NULL,       -- Monotonic position in conversation
  role TEXT NOT NULL,              -- 'user', 'assistant', or 'system'
  content TEXT NOT NULL,           -- Message content
  timestamp INTEGER,                -- Optional Unix timestamp
  
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY(source_file_id) REFERENCES source_files(id),
  UNIQUE(source_file_id, line_no)  -- Prevent duplicate imports
);
```

**Purpose**:
- Store parsed messages
- Enable keyset pagination
- Support exact line retrieval
- Prevent duplicate imports

**Key Points**:
- `UNIQUE(source_file_id, line_no)` ensures idempotency
- `byte_start/byte_end` allows exact line extraction
- `position` enables correct ordering across files
- Content stored for FTS5 backing

### messages_fts

Full-text search index using FTS5.

```sql
CREATE VIRTUAL TABLE messages_fts USING fts5(
  content,                         -- Indexed message content
  conversation_id UNINDEXED,       -- For filtering (not searched)
  content='messages',              -- Backed by messages table
  content_rowid='id',              -- Use messages.id as rowid
  tokenize='unicode61 remove_diacritics 2 tokenchars "._#-+/@$"'
);
```

**Purpose**:
- Enable fast full-text search
- Code-aware tokenization
- BM25 relevance ranking

**Key Points**:
- Content-backed (not external content)
- Custom tokenizer for code tokens
- `conversation_id` for filtered search
- Automatically updated via triggers

## Indexes

### Performance Indexes

```sql
-- Keyset pagination for messages
CREATE INDEX idx_msg_conv_pos_desc 
  ON messages(conversation_id, position DESC);

-- Fast lookup by source file and line
CREATE INDEX idx_msg_file_line 
  ON messages(source_file_id, line_no);

-- Conversation listing by recency
CREATE INDEX idx_conv_updated_desc 
  ON conversations(updated_at DESC);
```

## Triggers

### FTS Synchronization

```sql
-- Insert trigger
CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, content, conversation_id)
  VALUES (new.id, new.content, new.conversation_id);
END;

-- Delete trigger
CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, content, conversation_id)
  VALUES ('delete', old.id, old.content, old.conversation_id);
END;

-- Update trigger
CREATE TRIGGER messages_au AFTER UPDATE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, content, conversation_id)
  VALUES ('delete', old.id, old.content, old.conversation_id);
  INSERT INTO messages_fts(rowid, content, conversation_id)
  VALUES (new.id, new.content, new.conversation_id);
END;
```

## Query Patterns

### Keyset Pagination (Messages)

```sql
-- Get page of messages (newest to oldest)
SELECT id, role, content, position, timestamp
FROM messages
WHERE conversation_id = ? 
  AND position < ?  -- Keyset cursor
ORDER BY position DESC
LIMIT ?;
```

### Latest Source File (for tail overlay)

```sql
-- Find most recent source file for a conversation
SELECT sf.id, sf.path, sf.last_byte
FROM source_files sf
JOIN messages m ON m.source_file_id = sf.id
WHERE m.conversation_id = ?
ORDER BY m.id DESC
LIMIT 1;
```

### Full-Text Search

```sql
-- Search with BM25 ranking
SELECT m.id, m.conversation_id, m.position, 
       m.timestamp, bm25(messages_fts) AS rank
FROM messages_fts f 
JOIN messages m ON m.id = f.rowid
WHERE messages_fts MATCH ?
  AND (? IS NULL OR f.conversation_id = ?)
ORDER BY rank
LIMIT ?;
```

### Conversation Listing

```sql
-- List recent conversations with stats
SELECT id, display_title, message_count, 
       total_chars, updated_at
FROM conversations
WHERE updated_at < ?  -- Keyset cursor
ORDER BY updated_at DESC
LIMIT ?;
```

## Pragmas

Optimized for performance and reliability:

```sql
PRAGMA journal_mode=WAL;        -- Concurrent reads during writes
PRAGMA synchronous=NORMAL;      -- Balance safety/performance
PRAGMA foreign_keys=ON;         -- Enforce referential integrity
PRAGMA page_size=8192;          -- Larger pages for fewer I/Os
PRAGMA temp_store=MEMORY;       -- Temp tables in RAM
PRAGMA cache_size=-64000;       -- 64MB cache
PRAGMA mmap_size=268435456;     -- 256MB memory-mapped I/O
```

## Migration Strategy

### Initial Setup

```sql
-- Check schema version
PRAGMA user_version;

-- Set initial version
PRAGMA user_version = 1;
```

### Future Migrations

1. Check current version
2. Apply migrations sequentially
3. Update version number
4. Validate integrity

Example migration:
```sql
-- Migration 1 -> 2: Add tags support
BEGIN TRANSACTION;
ALTER TABLE conversations ADD COLUMN tags TEXT;
CREATE INDEX idx_conv_tags ON conversations(tags);
PRAGMA user_version = 2;
COMMIT;
```

## Data Integrity

### Constraints
- Foreign keys enforced
- UNIQUE on (source_file_id, line_no)
- NOT NULL on critical fields
- CHECK constraints considered for v2

### Recovery
1. If corrupt: Delete and rebuild from JSONL
2. If missing: Create fresh database
3. If outdated: Run migrations
4. If locked: WAL mode prevents most locks

## Performance Considerations

### Write Performance
- Batch inserts (5000 rows/transaction)
- Prepared statements for hot paths
- WAL mode for concurrent access
- Periodic VACUUM after large imports

### Read Performance
- Covering indexes for common queries
- Keyset pagination (no OFFSET)
- FTS5 for search operations
- Memory-mapped I/O for page cache

### Space Efficiency
- Content stored once (FTS content-backed)
- Indexes ~20% of data size
- WAL checkpoint periodically
- VACUUM after deleting conversations

## Backup & Recovery

### Backup Strategy
```bash
# Online backup (safe during writes)
sqlite3 extractor.db ".backup backup.db"

# With compression
sqlite3 extractor.db ".dump" | gzip > backup.sql.gz
```

### Recovery Process
1. Stop importer
2. Restore from backup
3. Identify last imported position
4. Resume import from that point

## Monitoring Queries

### Database Statistics
```sql
-- Table sizes
SELECT name, 
       COUNT(*) as row_count,
       SUM(length(content)) as total_bytes
FROM messages
GROUP BY conversation_id;

-- Import progress
SELECT path, 
       last_line, 
       size_bytes,
       ROUND(last_byte * 100.0 / size_bytes, 2) as percent
FROM source_files;

-- Search performance
SELECT COUNT(*) as search_count,
       AVG(rank) as avg_rank
FROM (
  SELECT bm25(messages_fts) as rank
  FROM messages_fts
  WHERE messages_fts MATCH 'test query'
);
```

## Security Notes

- Use prepared statements (prevent SQL injection)
- Validate file paths before operations
- No ATTACH DATABASE allowed
- Read-only mode for UI queries option
- Consider encryption at rest (SQLCipher)