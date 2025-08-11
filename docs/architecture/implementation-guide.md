# Implementation Guide

## Quick Start

### Prerequisites

- Zig 0.11.0 or later
- SQLite3 development libraries
- Flutter SDK (for UI)
- 100MB free disk space for database

### Installation

```bash
# Install SQLite3 (macOS)
brew install sqlite3

# Install SQLite3 (Ubuntu/Debian)
sudo apt-get install libsqlite3-dev

# Install SQLite3 (Windows)
# Download from https://sqlite.org/download.html

# Clone repository
git clone https://github.com/yourusername/claude-conversation-extractor
cd claude-conversation-extractor

# Build the project
zig build -Doptimize=ReleaseFast

# Run tests
zig build test
```

### First Run

```bash
# Initialize database and import existing conversations
./zig-out/bin/extractor --init

# Or run in protocol mode for Flutter
./zig-out/bin/extractor --protocol
```

## Architecture Components

### 1. Memory-Mapped Files (MappedFile)

Platform-agnostic file mapping for zero-copy access.

**Usage Example:**
```zig
// Open a memory-mapped file
var mapped = try MappedFile.open(allocator, "/path/to/file.jsonl");
defer mapped.close();

// Check for changes and remap if needed
if (try mapped.remapIfChanged()) {
    std.debug.print("File changed, remapped\n", .{});
}

// Iterate lines efficiently
var iter = mapped.findLines(0, mapped.size);
while (iter.next()) |line| {
    // Process line without copying
    processLine(line.content);
}
```

**Key Features:**
- Automatic remapping on file growth
- CRLF/LF normalization
- Windows sharing compatibility
- Zero allocations for reads

### 2. Block Index (.bix)

Fast line number to byte offset mapping.

**Usage Example:**
```zig
// Load or create block index
var index = try BlockIndex.load(allocator, "/path/to/file.jsonl");
defer index.deinit();

// Update incrementally with new data
try index.appendIncremental(&mapped_file);

// Get byte offset for line 10000
if (index.getLineOffset(10000)) |offset| {
    // Jump directly to line 10000
    var iter = mapped_file.findLines(offset, mapped_file.size);
}
```

**File Format:**
```
.bix file = [Header:64 bytes][Block Offsets:8 bytes each]
```

### 3. SQLite Database Layer

Persistent index with FTS5 search.

**Usage Example:**
```zig
// Initialize database
var db = try Database.init(allocator, "extractor.db");
defer db.deinit();

// Get or create source file
const source_id = try db.getOrCreateSourceFile(path, stat);

// Insert messages in transaction
try db.beginTransaction();
defer db.rollback() catch {};

// Use prepared statement for speed
const stmt = db.insert_message_stmt.?;
_ = sqlite.sqlite3_bind_text(stmt, 1, conv_id, -1, null);
_ = sqlite.sqlite3_bind_int64(stmt, 2, source_id);
// ... bind other parameters
_ = sqlite.sqlite3_step(stmt);

try db.commit();
```

### 4. Incremental Importer

Combines all components for efficient importing.

**Usage Example:**
```zig
// Create importer with database
var importer = try IncrementalImporter.init(allocator, &db);
defer importer.deinit();

// Import a file (incremental, idempotent)
try importer.importFile("/path/to/conversation.jsonl");

// Get messages with live tail overlay
const messages = try importer.getMessagesWithTailOverlay(
    "conversation-id",
    last_position,  // Keyset cursor
    50             // Limit
);
defer allocator.free(messages);
```

## Integration with Flutter

### FFI Setup

**Zig Exports:**
```zig
export fn extractor_init(db_path: [*:0]const u8) ?*Context {
    // Initialize context with database
}

export fn extractor_get_messages_binary(
    ctx: *Context,
    conv_id: [*:0]const u8,
    before_position: i64,
    limit: u32,
) Buffer {
    // Return binary formatted messages
}

export fn extractor_free(ptr: [*]u8, len: usize) void {
    // Free allocated memory
}
```

**Dart FFI:**
```dart
import 'dart:ffi';

// Load native library
final dylib = DynamicLibrary.open('libclaude_extractor.so');

// Define function signatures
typedef ExtractorInitNative = Pointer Function(Pointer<Utf8>);
typedef ExtractorInit = Pointer Function(Pointer<Utf8>);

// Bind functions
final extractorInit = dylib
    .lookup<NativeFunction<ExtractorInitNative>>('extractor_init')
    .asFunction<ExtractorInit>();

// Use the API
final context = extractorInit(dbPath.toNativeUtf8());
```

### Binary Protocol Format

Efficient binary format for hot paths:

```
[Header: 8 bytes]
  version: u16 = 1
  reserved: u16 = 0
  message_count: u32

[Messages: variable]
  For each message:
    position: i64
    timestamp: i64
    role: u8
    content_offset: u32
    content_length: u32

[Content: variable]
  Raw UTF-8 strings concatenated
```

**Parsing in Dart:**
```dart
class BinaryMessage {
  final int position;
  final int timestamp;
  final Role role;
  final String content;
  
  static List<BinaryMessage> parse(Uint8List buffer) {
    final bytes = ByteData.view(buffer.buffer);
    int offset = 0;
    
    // Read header
    final version = bytes.getUint16(offset, Endian.little);
    offset += 2;
    offset += 2; // Skip reserved
    final count = bytes.getUint32(offset, Endian.little);
    offset += 4;
    
    // Read messages
    final messages = <BinaryMessage>[];
    for (int i = 0; i < count; i++) {
      final position = bytes.getInt64(offset, Endian.little);
      offset += 8;
      // ... parse rest of message
    }
    
    return messages;
  }
}
```

## File Watching & Live Updates

### Platform-Specific Watchers

**Windows (ReadDirectoryChangesW):**
```zig
const handle = windows.kernel32.CreateFileW(
    path,
    windows.FILE_LIST_DIRECTORY,
    windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
    null,
    windows.OPEN_EXISTING,
    windows.FILE_FLAG_BACKUP_SEMANTICS,
    null
);

var buffer: [4096]u8 = undefined;
_ = windows.kernel32.ReadDirectoryChangesW(
    handle,
    &buffer,
    buffer.len,
    true,  // Watch subtree
    windows.FILE_NOTIFY_CHANGE_LAST_WRITE,
    null,
    null,
    null
);
```

**macOS (FSEvents):**
```zig
// Use FSEvents API via C bindings
const stream = c.FSEventStreamCreate(
    null,
    callback,
    context,
    paths,
    kFSEventStreamEventIdSinceNow,
    1.0,  // Latency
    kFSEventStreamCreateFlagFileEvents
);
```

**Linux (inotify):**
```zig
const fd = try os.inotify_init1(os.linux.IN_CLOEXEC);
const wd = try os.inotify_add_watch(
    fd,
    path,
    os.linux.IN_MODIFY | os.linux.IN_CREATE
);
```

### Debouncing Strategy

```zig
const Debouncer = struct {
    timer: ?std.time.Timer = null,
    delay_ns: u64 = 100_000_000, // 100ms
    
    pub fn trigger(self: *Debouncer) bool {
        const now = std.time.nanoTimestamp();
        if (self.timer) |last| {
            if (now - last < self.delay_ns) {
                return false; // Still in debounce period
            }
        }
        self.timer = now;
        return true;
    }
};
```

## Performance Optimization Tips

### 1. Batch Operations

```zig
// BAD: Commit per message
for (messages) |msg| {
    try db.insertMessage(msg);
    try db.commit(); // Slow!
}

// GOOD: Batch commits
try db.beginTransaction();
for (messages, 0..) |msg, i| {
    try db.insertMessage(msg);
    if (i % 5000 == 0) {
        try db.commit();
        try db.beginTransaction();
    }
}
try db.commit();
```

### 2. Prepared Statements

```zig
// BAD: Parse SQL every time
for (messages) |msg| {
    try db.exec("INSERT INTO messages VALUES ...");
}

// GOOD: Prepare once, execute many
const stmt = try db.prepare("INSERT INTO messages VALUES (?, ?, ?)");
for (messages) |msg| {
    try stmt.bind(msg.values);
    try stmt.execute();
    try stmt.reset();
}
```

### 3. Memory Pool for Hot Paths

```zig
// Create arena for temporary allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

// Use arena for parsing
const parsed = try parseJson(arena.allocator(), line);
// No need to free individual allocations
```

### 4. SIMD Optimizations

```zig
// Use SIMD for line counting
pub fn countLinesSimd(data: []const u8) usize {
    const vector_size = 32;
    var count: usize = 0;
    var i: usize = 0;
    
    // Process 32 bytes at a time
    while (i + vector_size <= data.len) : (i += vector_size) {
        const vec = @as(@Vector(32, u8), data[i..][0..32].*);
        const newlines = vec == @as(@Vector(32, u8), @splat('\n'));
        count += @popCount(@as(u32, @bitCast(newlines)));
    }
    
    // Handle remainder
    while (i < data.len) : (i += 1) {
        if (data[i] == '\n') count += 1;
    }
    
    return count;
}
```

## Error Handling

### Graceful Degradation

```zig
// Try fast path first, fall back to slow path
const messages = getFromCache(conv_id) catch |err| switch (err) {
    error.CacheMiss => try getFromDatabase(conv_id),
    error.DatabaseLocked => try getFromJsonl(conv_id),
    else => return err,
};
```

### Recovery Strategies

```zig
// Detect and handle corruption
if (index.header.crc32 != calculateCrc32(data)) {
    std.log.warn("Index corrupted, rebuilding", .{});
    try index.rebuild();
}

// Handle file rotation
if (stat.inode != cached_inode) {
    std.log.info("File rotated, creating new source", .{});
    source_id = try db.createNewSourceFile(path);
}
```

## Testing Strategy

### Unit Tests

```zig
test "mmap handles file growth" {
    var tmp = try std.testing.tmpDir(.{});
    defer tmp.cleanup();
    
    // Create file
    const path = try tmp.dir.realpathAlloc(allocator, "test.jsonl");
    defer allocator.free(path);
    
    var file = try tmp.dir.createFile("test.jsonl", .{});
    try file.writeAll("line1\n");
    file.close();
    
    // Map file
    var mapped = try MappedFile.open(allocator, path);
    defer mapped.close();
    
    try testing.expectEqual(@as(usize, 6), mapped.size);
    
    // Grow file
    file = try tmp.dir.openFile("test.jsonl", .{ .mode = .write_only });
    try file.seekFromEnd(0);
    try file.writeAll("line2\n");
    file.close();
    
    // Remap should detect growth
    try testing.expect(try mapped.remapIfChanged());
    try testing.expectEqual(@as(usize, 12), mapped.size);
}
```

### Integration Tests

```zig
test "end-to-end import and query" {
    // Setup test database
    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    
    // Create test JSONL
    const jsonl = 
        \\{"conversation_id":"c1","type":"user","content":"Hello"}
        \\{"conversation_id":"c1","type":"assistant","content":"Hi!"}
    ;
    
    // Import
    var importer = try IncrementalImporter.init(allocator, &db);
    defer importer.deinit();
    try importer.importContent(jsonl);
    
    // Query
    const messages = try importer.getMessagesWithTailOverlay("c1", 999, 10);
    defer allocator.free(messages);
    
    try testing.expectEqual(@as(usize, 2), messages.len);
    try testing.expectEqualStrings("Hi!", messages[0].content);
}
```

### Performance Benchmarks

```zig
test "benchmark message loading" {
    const iterations = 1000;
    var timer = try std.time.Timer.start();
    
    for (0..iterations) |_| {
        const messages = try importer.getMessages(conv_id, 0, 50);
        allocator.free(messages);
    }
    
    const ns = timer.read();
    const ms_per_op = @as(f64, @floatFromInt(ns)) / iterations / 1_000_000;
    
    try testing.expect(ms_per_op < 10.0); // Must be under 10ms
    std.debug.print("Message load: {d:.2}ms\n", .{ms_per_op});
}
```

## Deployment Checklist

### Pre-Production

- [ ] Run all tests (`zig build test`)
- [ ] Check memory leaks (Valgrind/ASAN)
- [ ] Verify platform compatibility
- [ ] Test with large files (>100MB)
- [ ] Benchmark performance targets
- [ ] Review security (path validation)

### Production

- [ ] Set appropriate SQLite pragmas
- [ ] Configure cache sizes for hardware
- [ ] Enable file watching
- [ ] Set up monitoring/metrics
- [ ] Document backup procedures
- [ ] Plan migration strategy

### Monitoring

Key metrics to track:
- Import lag (current vs latest byte)
- Query latency (P50/P95/P99)
- Cache hit rates
- Memory usage
- File descriptor count
- Database size growth

## Troubleshooting

### Common Issues

**Issue: Slow imports**
- Check transaction batch size
- Verify indexes aren't rebuilding
- Look for lock contention

**Issue: High memory usage**
- Reduce SQLite cache size
- Check for memory leaks
- Verify mmap pages are released

**Issue: Database corruption**
- Run `PRAGMA integrity_check`
- Restore from JSONL source
- Check disk space

**Issue: Missing messages**
- Verify file watching is active
- Check for parsing errors in logs
- Ensure proper line endings

## Additional Resources

- [SQLite Performance Tuning](https://sqlite.org/pragma.html)
- [Zig Language Reference](https://ziglang.org/documentation/)
- [Memory-Mapped Files Guide](https://en.wikipedia.org/wiki/Memory-mapped_file)
- [Protocol Buffers (future)](https://protobuf.dev/)