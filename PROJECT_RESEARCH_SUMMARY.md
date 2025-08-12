# Claude Conversation Extractor - Project Research Summary

## Executive Overview

**Claude Conversation Extractor** is a high-performance desktop application that extracts, indexes, and enables full-text search across Claude AI conversation histories stored locally on users' machines. Built with a Zig backend for maximum performance and a Flutter frontend for cross-platform desktop UI, it processes conversations from Claude's undocumented JSONL format into a searchable SQLite database with sub-millisecond query times.

## Core Purpose & Problem Solved

- **Problem**: Claude AI stores conversations in JSONL files (~/.claude/projects/) that are difficult to search and analyze
- **Solution**: Automated extraction, indexing, and instant full-text search across all conversations
- **Users**: Developers using Claude AI who need to reference past conversations
- **Scale**: Handles 500MB+ conversation files with 50,000+ messages efficiently

## Technology Stack

### Backend (Zig)
- **Language**: Zig 0.13.0 (systems programming, manual memory management)
- **Database**: SQLite 3 with FTS5 (full-text search extension)
- **Architecture**: Single binary, zero dependencies
- **Communication**: NDJSON protocol over stdin/stdout
- **Performance**: Sub-microsecond message processing, 1.5ms search latency

### Frontend (Flutter/Dart)
- **Framework**: Flutter 3.x with Material Design 3
- **State Management**: Riverpod (reactive state management)
- **Routing**: GoRouter (declarative navigation)
- **Platform**: macOS, Windows, Linux desktop support
- **Design**: Custom design system with animated components

## Data Flow Architecture

```
JSONL Files → Memory Map → Block Index → SQLite → FTS5 Index
     ↓             ↓            ↓          ↓         ↓
   Flutter ← NDJSON Protocol ← Zig Core ← Query ← Search
```

### 1. Data Ingestion Pipeline
- **Memory-mapped files** for zero-copy reading
- **Block Index (.bix)** for O(1) line access (256-line blocks)
- **Incremental importing** - only processes new data
- **Batch transactions** - 5000 messages per commit
- **Platform-agnostic** - supports POSIX and Windows

### 2. Database Schema

```sql
-- Core tables
source_files      -- Tracks JSONL files (path, size, mtime, last_byte)
conversations     -- Metadata (id, title, timestamps, message_count)
messages          -- Content (conversation_id, role, content, position)
messages_fts      -- FTS5 virtual table for search

-- Key indexes
CREATE INDEX idx_messages_conversation ON messages(conversation_id);
CREATE INDEX idx_messages_position ON messages(conversation_id, position);
```

### 3. Protocol Communication

**Request/Response Format** (NDJSON):
```json
// Request
{"id":"1","method":"search","params":{"q":"query","limit":50}}

// Response
{"id":"1","type":"result","data":[...]}

// Progress Event
{"id":"2","type":"event","stage":"import","progress":0.75}
```

**Supported Operations**:
- `build_index` - Import all JSONL files with progress tracking
- `list_sessions` - Enumerate available conversations
- `search` - FTS5 full-text search with snippets
- `extract` - Export in Markdown/JSON/HTML
- `get_messages` - Paginated message retrieval
- `cancel` - Atomic operation cancellation

## Performance Characteristics

### Backend Performance
- **Search**: 1.5ms for 1M+ messages (FTS5 optimized)
- **Import**: 10,000 messages/second
- **Memory**: 50MB baseline + mapped file size
- **Startup**: <100ms to ready state

### Optimizations
- **Zero-allocation hot paths** using arena allocators
- **Prepared statements** eliminate SQL parsing
- **Incremental processing** with last_byte tracking
- **Memory-mapped I/O** avoids data copying
- **Batch operations** reduce transaction overhead

## Critical Functions & Entry Points

### Backend (Zig)

```zig
// Main protocol handler
runProtocolMode() 
  → handleRequest()
    → protocolBuildIndex() / protocolSearch() / etc.

// Data import pipeline  
IncrementalImporter.importFile()
  → MappedFile.findLines()
    → extractMessage()
      → Database.insertMessage()

// Search implementation
protocolSearch()
  → Database.searchMessages()
    → FTS5 query
      → snippet generation
```

### Frontend (Flutter)

```dart
// Core state management
ZigCoreClient 
  → request() / requestWithEvents()
    → Process.stdin/stdout
      → ProtocolMessage parsing

// UI entry points
HomeScreen → Auto-index on startup
SessionsScreen → Real-time search
ConversationScreen → Message display
```

## Analytics Integration Strategy

### Recommended Analytics Points

#### Backend Integration Points

1. **Message Processing Hook** (extractor.zig:1653)
   - After `extractMessage()` completes
   - Capture: message length, role, timestamp patterns
   - Use case: Content analysis, response time metrics

2. **Search Analytics** (extractor.zig:2089)
   - Post-FTS5 query execution
   - Capture: query terms, result count, latency
   - Use case: Search relevance optimization

3. **Import Completion** (extractor.zig:1898)
   - End of `importFile()`
   - Capture: file size, message count, duration
   - Use case: Performance monitoring

4. **Protocol Events** (extractor.zig:2341)
   - Within event handlers
   - Capture: operation type, duration, success/failure
   - Use case: Usage patterns, error tracking

#### Frontend Integration Points

1. **User Interactions** (SessionsScreen)
   - Search queries, session clicks
   - Capture: search terms, click-through rates

2. **Navigation Events** (AppScaffold)
   - Tab switches, feature usage
   - Capture: feature adoption, user flows

3. **Export Operations** (ConversationScreen)
   - Format preferences, export sizes
   - Capture: usage patterns, format popularity

### Database Extensions for Analytics

```sql
-- Analytics events table
CREATE TABLE analytics_events (
    id INTEGER PRIMARY KEY,
    timestamp INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    conversation_id TEXT,
    user_action TEXT,
    metadata JSON,
    duration_ms INTEGER,
    INDEX idx_analytics_timestamp (timestamp),
    INDEX idx_analytics_type (event_type)
);

-- Conversation metrics
CREATE TABLE conversation_metrics (
    conversation_id TEXT PRIMARY KEY,
    total_messages INTEGER,
    avg_message_length REAL,
    avg_response_time_ms INTEGER,
    last_accessed INTEGER,
    access_count INTEGER DEFAULT 0,
    search_hit_count INTEGER DEFAULT 0
);

-- Search analytics
CREATE TABLE search_analytics (
    id INTEGER PRIMARY KEY,
    timestamp INTEGER,
    query TEXT,
    result_count INTEGER,
    click_position INTEGER,
    latency_ms INTEGER
);
```

### Protocol Extensions for Analytics

```json
// New analytics method
{"method": "get_analytics", "params": {"period": "7d"}}

// Analytics event streaming
{"method": "track_event", "params": {
  "event": "search",
  "data": {"query": "flutter", "results": 42}
}}
```

## Architecture Strengths

1. **Performance**: Orders of magnitude faster than file parsing
2. **Incremental**: Only processes new data
3. **Cross-platform**: Single codebase for all desktop platforms
4. **Extensible**: Clean protocol for adding features
5. **Maintainable**: Clear separation of concerns

## Current Limitations & Considerations

1. **Analytics**: Prepared UI components but backend not yet implemented
2. **Memory**: Large conversation files are fully memory-mapped
3. **Concurrency**: Single-threaded processing (could parallelize)
4. **Real-time**: No file watching for live updates yet

## Development & Testing

### Build Commands
```bash
# Backend
zig build -Doptimize=ReleaseFast

# Frontend
cd claude_ui && flutter build macos

# Run with protocol mode
./extractor --protocol
```

### Key Files for Researchers

**Backend Core**:
- `extractor.zig` - Main implementation (2500+ lines)
- Database operations: lines 358-571
- Protocol handlers: lines 2258-2555
- Search implementation: lines 2089-2153

**Frontend Core**:
- `lib/core/zig_core_client.dart` - Backend communication
- `lib/features/sessions/sessions_screen.dart` - Search UI
- `lib/features/conversation/conversation_screen.dart` - Message display
- `lib/app.dart` - Routing configuration

## Recommendations for Analytics Implementation

1. **Start with passive collection** - Track existing operations without new UI
2. **Use SQLite for storage** - Leverage existing database infrastructure
3. **Implement streaming analytics** - Real-time event processing
4. **Add batched uploads** - Aggregate before sending to analytics service
5. **Create dashboard view** - Utilize prepared Flutter components
6. **Focus on search metrics** - Most valuable for improving relevance

## Contact & Repository

- **GitHub**: https://github.com/ZeroSumQuant/claude-conversation-extractor
- **Branch**: perfect-clean-version
- **Primary Language**: Zig (backend), Dart (frontend)
- **License**: MIT

---

*This summary prepared for analytics integration research. The project is production-ready with working search, export, and UI features. Analytics infrastructure is partially prepared but requires backend implementation to activate.*