# Testing Documentation

## Test Plan Overview

This document outlines the comprehensive testing strategy for the Claude Conversation Extractor, covering unit tests, integration tests, performance benchmarks, and edge case validation.

## Test Categories

### 1. Unit Tests

Tests for individual components in isolation.

#### MappedFile Tests

```zig
test "MappedFile opens and maps file correctly" {
    const path = "test_data/sample.jsonl";
    var mapped = try MappedFile.open(allocator, path);
    defer mapped.close();
    
    try testing.expect(mapped.size > 0);
    try testing.expect(mapped.data.len == mapped.size);
}

test "MappedFile detects file growth" {
    // Create temp file
    var tmp_file = try std.fs.cwd().createFile("test.tmp", .{});
    try tmp_file.writeAll("initial content\n");
    tmp_file.close();
    defer std.fs.cwd().deleteFile("test.tmp") catch {};
    
    var mapped = try MappedFile.open(allocator, "test.tmp");
    defer mapped.close();
    
    const initial_size = mapped.size;
    
    // Append to file
    tmp_file = try std.fs.cwd().openFile("test.tmp", .{ .mode = .write_only });
    try tmp_file.seekFromEnd(0);
    try tmp_file.writeAll("additional content\n");
    tmp_file.close();
    
    // Remap should detect change
    const changed = try mapped.remapIfChanged();
    try testing.expect(changed);
    try testing.expect(mapped.size > initial_size);
}

test "MappedFile handles CRLF correctly" {
    const content = "line1\r\nline2\nline3\r\n";
    // ... setup temp file with content
    
    var mapped = try MappedFile.open(allocator, "test.tmp");
    defer mapped.close();
    
    var iter = mapped.findLines(0, mapped.size);
    
    const line1 = iter.next().?;
    try testing.expectEqualStrings("line1", line1.content);
    
    const line2 = iter.next().?;
    try testing.expectEqualStrings("line2", line2.content);
    
    const line3 = iter.next().?;
    try testing.expectEqualStrings("line3", line3.content);
}
```

#### BlockIndex Tests

```zig
test "BlockIndex creates and loads correctly" {
    const path = "test_data/sample.jsonl";
    
    // Create new index
    var index = try BlockIndex.create(allocator, path);
    defer index.deinit();
    
    // Add some blocks
    var mapped = try MappedFile.open(allocator, path);
    defer mapped.close();
    try index.appendIncremental(&mapped);
    
    try testing.expect(index.header.total_lines > 0);
    try testing.expect(index.block_offsets.len > 0);
}

test "BlockIndex getLineOffset returns correct offset" {
    var index = try BlockIndex.load(allocator, "test_data/sample.jsonl");
    defer index.deinit();
    
    // Line 0 should be at offset 0
    try testing.expectEqual(@as(?u64, 0), index.getLineOffset(0));
    
    // Line 256 should be at first block offset
    if (index.block_offsets.len > 0) {
        const offset = index.getLineOffset(256);
        try testing.expect(offset.? > 0);
    }
    
    // Out of bounds should return null
    try testing.expectEqual(@as(?u64, null), index.getLineOffset(999999));
}

test "BlockIndex incremental update is idempotent" {
    var index = try BlockIndex.create(allocator, "test.jsonl");
    defer index.deinit();
    
    var mapped = try MappedFile.open(allocator, "test.jsonl");
    defer mapped.close();
    
    // First update
    try index.appendIncremental(&mapped);
    const lines1 = index.header.total_lines;
    const crc1 = index.header.crc32;
    
    // Second update (no new data)
    try index.appendIncremental(&mapped);
    const lines2 = index.header.total_lines;
    const crc2 = index.header.crc32;
    
    try testing.expectEqual(lines1, lines2);
    try testing.expectEqual(crc1, crc2);
}
```

#### Database Tests

```zig
test "Database creates schema correctly" {
    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    
    // Check tables exist
    const tables = try db.query(
        "SELECT name FROM sqlite_master WHERE type='table'"
    );
    
    try testing.expect(containsString(tables, "source_files"));
    try testing.expect(containsString(tables, "conversations"));
    try testing.expect(containsString(tables, "messages"));
    try testing.expect(containsString(tables, "messages_fts"));
}

test "Database prepared statements work" {
    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    
    // Insert test data
    const stmt = db.insert_message_stmt.?;
    _ = sqlite.sqlite3_reset(stmt);
    _ = sqlite.sqlite3_bind_text(stmt, 1, "conv1", -1, null);
    _ = sqlite.sqlite3_bind_int64(stmt, 2, 1);
    // ... bind other params
    
    const result = sqlite.sqlite3_step(stmt);
    try testing.expectEqual(sqlite.SQLITE_DONE, result);
}

test "Database handles transactions correctly" {
    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    
    try db.beginTransaction();
    // Insert data
    try db.rollback();
    
    // Verify data was not committed
    const count = try db.queryScalar("SELECT COUNT(*) FROM messages");
    try testing.expectEqual(@as(i64, 0), count);
}
```

### 2. Integration Tests

Tests for component interactions.

#### Importer Tests

```zig
test "Importer processes JSONL file correctly" {
    var db = try Database.init(allocator, ":memory:");
    defer db.deinit();
    
    var importer = try IncrementalImporter.init(allocator, &db);
    defer importer.deinit();
    
    // Import test file
    try importer.importFile("test_data/conversation.jsonl");
    
    // Verify messages were imported
    const count = try db.queryScalar(
        "SELECT COUNT(*) FROM messages"
    );
    try testing.expect(count > 0);
}

test "Importer handles incremental updates" {
    // Setup
    var db = try Database.init(allocator, ":memory:");
    var importer = try IncrementalImporter.init(allocator, &db);
    
    // Initial import
    try importer.importFile("test.jsonl");
    const count1 = try db.queryScalar("SELECT COUNT(*) FROM messages");
    
    // Append to file
    appendToFile("test.jsonl", 
        \\{"conversation_id":"c1","type":"user","content":"New"}
    );
    
    // Incremental import
    try importer.importFile("test.jsonl");
    const count2 = try db.queryScalar("SELECT COUNT(*) FROM messages");
    
    try testing.expect(count2 == count1 + 1);
}

test "Live tail overlay returns recent messages" {
    var db = try Database.init(allocator, ":memory:");
    var importer = try IncrementalImporter.init(allocator, &db);
    
    // Import most of file
    try importer.importFile("test.jsonl");
    
    // Simulate new lines not yet imported
    appendToFile("test.jsonl", 
        \\{"conversation_id":"c1","type":"assistant","content":"Tail"}
    );
    
    // Get messages with tail overlay
    const messages = try importer.getMessagesWithTailOverlay(
        "c1", 9999, 50
    );
    
    // Should include tail message
    var found_tail = false;
    for (messages) |msg| {
        if (std.mem.eql(u8, msg.content, "Tail")) {
            found_tail = true;
            break;
        }
    }
    try testing.expect(found_tail);
}
```

### 3. Performance Tests

Benchmarks to ensure performance targets are met.

```zig
test "benchmark: message loading under 10ms" {
    var db = try setupLargeDatabase(); // 100k messages
    var importer = try IncrementalImporter.init(allocator, &db);
    
    const iterations = 100;
    var total_ns: u64 = 0;
    
    for (0..iterations) |_| {
        var timer = try std.time.Timer.start();
        
        const messages = try importer.getMessagesWithTailOverlay(
            "test-conv", 50000, 50
        );
        allocator.free(messages);
        
        total_ns += timer.read();
    }
    
    const avg_ms = @as(f64, @floatFromInt(total_ns)) / iterations / 1_000_000;
    
    std.debug.print("Average load time: {d:.2}ms\n", .{avg_ms});
    try testing.expect(avg_ms < 10.0);
}

test "benchmark: search 1M messages under 120ms" {
    var db = try setupMillionMessageDatabase();
    
    var timer = try std.time.Timer.start();
    
    const results = try db.search("test query", null, 200);
    
    const elapsed_ms = @as(f64, @floatFromInt(timer.read())) / 1_000_000;
    
    std.debug.print("Search time: {d:.2}ms\n", .{elapsed_ms});
    try testing.expect(elapsed_ms < 120.0);
}

test "benchmark: import throughput > 50k msgs/sec" {
    var db = try Database.init(allocator, ":memory:");
    var importer = try IncrementalImporter.init(allocator, &db);
    
    const test_messages = generateTestMessages(50000);
    
    var timer = try std.time.Timer.start();
    try importer.importContent(test_messages);
    const elapsed_ns = timer.read();
    
    const msgs_per_sec = 50000.0 * 1_000_000_000.0 / 
        @as(f64, @floatFromInt(elapsed_ns));
    
    std.debug.print("Import rate: {d:.0} msgs/sec\n", .{msgs_per_sec});
    try testing.expect(msgs_per_sec > 50000);
}
```

### 4. Edge Case Tests

Tests for boundary conditions and error cases.

```zig
test "handles 40MB file efficiently" {
    const large_file = try generateLargeFile(40 * 1024 * 1024);
    defer std.fs.cwd().deleteFile(large_file) catch {};
    
    var timer = try std.time.Timer.start();
    
    var importer = try IncrementalImporter.init(allocator, &db);
    try importer.importFile(large_file);
    
    const elapsed_s = @as(f64, @floatFromInt(timer.read())) / 1_000_000_000;
    
    std.debug.print("40MB import time: {d:.2}s\n", .{elapsed_s});
    try testing.expect(elapsed_s < 10.0); // Should complete in <10s
}

test "handles file rotation correctly" {
    // Create initial file
    createTestFile("rotating.jsonl", "content1\n");
    
    var importer = try IncrementalImporter.init(allocator, &db);
    try importer.importFile("rotating.jsonl");
    
    const source1 = try db.queryScalar(
        "SELECT COUNT(*) FROM source_files"
    );
    
    // Simulate rotation (delete and recreate)
    std.fs.cwd().deleteFile("rotating.jsonl") catch {};
    createTestFile("rotating.jsonl", "content2\n");
    
    try importer.importFile("rotating.jsonl");
    
    const source2 = try db.queryScalar(
        "SELECT COUNT(*) FROM source_files"
    );
    
    // Should have created new source file entry
    try testing.expect(source2 == source1 + 1);
}

test "handles file truncation" {
    createTestFile("truncate.jsonl", "line1\nline2\nline3\n");
    
    var importer = try IncrementalImporter.init(allocator, &db);
    try importer.importFile("truncate.jsonl");
    
    // Truncate file
    createTestFile("truncate.jsonl", "newline1\n");
    
    try importer.importFile("truncate.jsonl");
    
    // Should treat as new file
    const sources = try db.queryScalar(
        "SELECT COUNT(*) FROM source_files WHERE path='truncate.jsonl'"
    );
    try testing.expect(sources == 2);
}

test "handles concurrent writer" {
    var writer_thread = try std.Thread.spawn(.{}, continuousWriter, .{
        "concurrent.jsonl"
    });
    
    var importer = try IncrementalImporter.init(allocator, &db);
    
    // Import while writing
    for (0..10) |_| {
        try importer.importFile("concurrent.jsonl");
        std.time.sleep(100_000_000); // 100ms
    }
    
    writer_thread.join();
    
    // Verify no data loss
    const file_lines = countFileLines("concurrent.jsonl");
    const db_lines = try db.queryScalar(
        "SELECT COUNT(*) FROM messages"
    );
    
    try testing.expectEqual(file_lines, db_lines);
}

test "handles partial lines correctly" {
    createTestFile("partial.jsonl", 
        \\{"complete":"line1"}
        \\{"partial":"incomp
    );
    
    var importer = try IncrementalImporter.init(allocator, &db);
    try importer.importFile("partial.jsonl");
    
    const count = try db.queryScalar("SELECT COUNT(*) FROM messages");
    try testing.expectEqual(@as(i64, 1), count); // Only complete line
    
    // Complete the partial line
    appendToFile("partial.jsonl", "lete\"}\n");
    
    try importer.importFile("partial.jsonl");
    const count2 = try db.queryScalar("SELECT COUNT(*) FROM messages");
    try testing.expectEqual(@as(i64, 2), count2); // Now both lines
}

test "handles huge lines (8MB)" {
    const huge_content = try allocator.alloc(u8, 8 * 1024 * 1024);
    defer allocator.free(huge_content);
    @memset(huge_content, 'X');
    
    const huge_line = try std.fmt.allocPrint(allocator,
        \\{{"conversation_id":"c1","type":"user","content":"{s}"}}
    , .{huge_content});
    defer allocator.free(huge_line);
    
    createTestFile("huge.jsonl", huge_line);
    
    var importer = try IncrementalImporter.init(allocator, &db);
    
    // Should skip line that's too large
    try importer.importFile("huge.jsonl");
    
    const count = try db.queryScalar("SELECT COUNT(*) FROM messages");
    try testing.expectEqual(@as(i64, 0), count);
}

test "handles corrupt JSON gracefully" {
    createTestFile("corrupt.jsonl",
        \\{"valid":"json1"}
        \\{corrupt json}
        \\{"valid":"json2"}
        \\
    );
    
    var importer = try IncrementalImporter.init(allocator, &db);
    try importer.importFile("corrupt.jsonl");
    
    // Should import valid lines only
    const count = try db.queryScalar("SELECT COUNT(*) FROM messages");
    try testing.expectEqual(@as(i64, 2), count);
}

test "handles mixed line endings" {
    const mixed = "line1\r\nline2\nline3\r\nline4\n\r\n";
    createTestFile("mixed.jsonl", mixed);
    
    var mapped = try MappedFile.open(allocator, "mixed.jsonl");
    defer mapped.close();
    
    var count: usize = 0;
    var iter = mapped.findLines(0, mapped.size);
    while (iter.next()) |_| {
        count += 1;
    }
    
    try testing.expectEqual(@as(usize, 5), count); // Including empty line
}
```

### 5. Platform-Specific Tests

```zig
test "Windows: file sharing works" {
    if (builtin.os.tag != .windows) return;
    
    // Open file with sharing
    var mapped = try MappedFile.open(allocator, "shared.jsonl");
    defer mapped.close();
    
    // Should be able to open for writing
    const file = try std.fs.cwd().openFile("shared.jsonl", .{
        .mode = .write_only,
    });
    defer file.close();
    
    try file.seekFromEnd(0);
    try file.writeAll("new line\n");
    
    // Remap should see the change
    try testing.expect(try mapped.remapIfChanged());
}

test "POSIX: mmap remapping preserves fd" {
    if (builtin.os.tag == .windows) return;
    
    var mapped = try MappedFile.open(allocator, "test.jsonl");
    const initial_fd = mapped.file_handle.handle;
    
    // Cause remap
    appendToFile("test.jsonl", "new content\n");
    _ = try mapped.remapIfChanged();
    
    // File descriptor should be the same
    try testing.expectEqual(initial_fd, mapped.file_handle.handle);
}
```

### 6. Stress Tests

```zig
test "stress: rapid file changes" {
    var writer = try std.Thread.spawn(.{}, rapidWriter, .{"rapid.jsonl"});
    defer writer.join();
    
    var mapped = try MappedFile.open(allocator, "rapid.jsonl");
    defer mapped.close();
    
    var remaps: usize = 0;
    const start = std.time.milliTimestamp();
    
    while (std.time.milliTimestamp() - start < 5000) { // 5 seconds
        if (try mapped.remapIfChanged()) {
            remaps += 1;
        }
        std.time.sleep(10_000_000); // 10ms
    }
    
    std.debug.print("Remaps in 5s: {}\n", .{remaps});
    try testing.expect(remaps > 100); // Should handle many remaps
}

test "stress: many concurrent readers" {
    var db = try setupLargeDatabase();
    
    const thread_count = 50;
    var threads: [thread_count]std.Thread = undefined;
    
    for (0..thread_count) |i| {
        threads[i] = try std.Thread.spawn(.{}, readerThread, .{&db});
    }
    
    for (threads) |thread| {
        thread.join();
    }
    
    // All threads should complete without error
    try testing.expect(true);
}

test "stress: memory usage stays bounded" {
    var db = try Database.init(allocator, ":memory:");
    var importer = try IncrementalImporter.init(allocator, &db);
    
    const initial_memory = getProcessMemory();
    
    // Process many messages
    for (0..100) |_| {
        const batch = generateTestMessages(10000);
        try importer.importContent(batch);
        allocator.free(batch);
    }
    
    const final_memory = getProcessMemory();
    const growth = final_memory - initial_memory;
    
    std.debug.print("Memory growth: {}MB\n", .{growth / 1024 / 1024});
    try testing.expect(growth < 100 * 1024 * 1024); // <100MB growth
}
```

## Test Data

### Sample Files

Located in `test_data/`:

- `small.jsonl` - 10 messages, <1KB
- `medium.jsonl` - 1000 messages, ~100KB  
- `large.jsonl` - 100k messages, ~10MB
- `huge.jsonl` - 1M messages, ~100MB
- `corrupt.jsonl` - Mix of valid/invalid JSON
- `mixed_endings.jsonl` - CRLF/LF mixed
- `unicode.jsonl` - Unicode and emoji content

### Test Data Generation

```zig
fn generateTestMessages(count: usize) []const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    
    for (0..count) |i| {
        const line = std.fmt.allocPrint(allocator,
            \\{{"conversation_id":"test","type":"user","content":"Message {}"}}
        , .{i}) catch unreachable;
        buffer.appendSlice(line) catch unreachable;
        buffer.append('\n') catch unreachable;
    }
    
    return buffer.toOwnedSlice();
}
```

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    
    runs-on: ${{ matrix.os }}
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: 0.11.0
    
    - name: Install SQLite (Ubuntu)
      if: matrix.os == 'ubuntu-latest'
      run: sudo apt-get install -y libsqlite3-dev
    
    - name: Install SQLite (macOS)
      if: matrix.os == 'macos-latest'
      run: brew install sqlite3
    
    - name: Run Tests
      run: zig build test
    
    - name: Run Benchmarks
      run: zig build bench
    
    - name: Check Performance
      run: |
        ./zig-out/bin/extractor --benchmark
        # Parse output and fail if targets not met
```

## Test Coverage

Target: 80% code coverage

### Coverage Report Generation

```bash
# Build with coverage
zig build-exe extractor.zig -ftest-coverage

# Run tests
./extractor --test

# Generate report
llvm-cov report ./extractor -instr-profile=default.profraw
```

### Critical Paths to Cover

1. Import pipeline (100% coverage required)
2. Query operations (100% coverage required)
3. Error handling (90% coverage required)
4. Platform-specific code (80% per platform)
5. Optimization paths (70% coverage acceptable)

## Performance Regression Prevention

### Benchmark Suite

Run on every PR:

```zig
pub fn runBenchmarks() !void {
    var results = BenchmarkResults{};
    
    results.message_load_p95 = try benchmarkMessageLoad();
    results.search_1m_p95 = try benchmarkSearch();
    results.import_rate = try benchmarkImport();
    
    // Compare with baseline
    const baseline = try loadBaseline();
    
    if (results.message_load_p95 > baseline.message_load_p95 * 1.1) {
        return error.PerformanceRegression;
    }
    
    // Save new baseline if improved
    if (results.message_load_p95 < baseline.message_load_p95 * 0.9) {
        try saveBaseline(results);
    }
}
```

## Manual Testing Checklist

Before release:

- [ ] Test with real Claude conversation files
- [ ] Test with 40MB+ files
- [ ] Test with active Claude Code session
- [ ] Test Flutter UI responsiveness
- [ ] Test search with complex queries
- [ ] Test export functionality
- [ ] Test on all platforms
- [ ] Test upgrade from previous version
- [ ] Test with corrupted database
- [ ] Test with read-only file system