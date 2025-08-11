// ================================================================================
// Claude Conversation Extractor - Single File Zig Implementation
// 
// This is a complete rewrite of the Python claude-conversation-extractor in Zig.
// Everything is in this single file for easier AI manipulation and compilation.
// 
// Build commands:
//   Executable: zig build-exe extractor.zig -O ReleaseFast
//   Library:    zig build-lib extractor.zig -dynamic -O ReleaseFast
// ================================================================================

const std = @import("std");

// ================================================================================
// SECTION 1: Core Types and Constants
// ================================================================================

const VERSION = "2.0.0";
const MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB max for JSONL files
const MAX_LINE_LENGTH = 1024 * 1024; // 1MB max per line

// Role enum for messages
const Role = enum { user, assistant, system };

// Core message types matching Python structure
const Message = struct {
    role: Role,
    content: []const u8,
    timestamp: ?i64 = null,
    
    // Tool-related fields for detailed export
    tool_calls: ?[]ToolCall = null,
    tool_responses: ?[]ToolResponse = null,
};

const ToolCall = struct {
    tool_name: []const u8,
    parameters: []const u8, // JSON string
    result: ?[]const u8 = null,
};

const ToolResponse = struct {
    tool_name: []const u8,
    output: []const u8,
    err: ?[]const u8 = null,
};

const Conversation = struct {
    id: []const u8,
    project_name: []const u8,
    messages: []Message,
    created_at: i64,
    updated_at: i64,
    file_path: []const u8,
    
    // Statistics
    message_count: usize,
    user_message_count: usize,
    assistant_message_count: usize,
    total_chars: usize,
    estimated_tokens: usize,
};

// Export format options
const ExportFormat = enum {
    markdown,
    json,
    html,
    detailed_markdown,
};

// ================================================================================
// SECTION 2: Memory-Mapped Files and Block Index (.bix)
// ================================================================================

const builtin = @import("builtin");
const os = std.os;
const windows = if (builtin.os.tag == .windows) std.os.windows else void;

// Platform-agnostic memory mapped file abstraction
pub const MappedFile = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    data: []const u8,
    generation: u64,
    
    // Platform-specific handles
    file_handle: if (builtin.os.tag == .windows) windows.HANDLE else std.fs.File,
    map_handle: if (builtin.os.tag == .windows) windows.HANDLE else void,
    
    // File metadata for change detection
    size: u64,
    mtime_ns: i128,
    device_id: u64,
    inode: u64,
    
    const Self = @This();
    
    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Self {
        if (builtin.os.tag == .windows) {
            return openWindows(allocator, path);
        } else {
            return openPosix(allocator, path);
        }
    }
    
    fn openPosix(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
        errdefer file.close();
        
        const stat = try file.stat();
        
        // Map the file
        const data = try std.posix.mmap(
            null,
            stat.size,
            std.posix.PROT.READ,
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );
        
        return Self{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .data = data,
            .generation = 0,
            .file_handle = file,
            .map_handle = {},
            .size = stat.size,
            .mtime_ns = stat.mtime,
            .device_id = 0, // Not available in cross-platform stat
            .inode = @intCast(stat.inode),
        };
    }
    
    fn openWindows(allocator: std.mem.Allocator, path: []const u8) !Self {
        const path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
        defer allocator.free(path_w);
        
        // Open with sharing flags to allow concurrent access
        const file_handle = windows.kernel32.CreateFileW(
            path_w,
            windows.GENERIC_READ,
            windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
            null,
            windows.OPEN_EXISTING,
            windows.FILE_ATTRIBUTE_NORMAL,
            null,
        );
        
        if (file_handle == windows.INVALID_HANDLE_VALUE) {
            return error.FileOpenFailed;
        }
        errdefer _ = windows.CloseHandle(file_handle);
        
        // Get file size
        var file_size: windows.LARGE_INTEGER = undefined;
        if (windows.kernel32.GetFileSizeEx(file_handle, &file_size) == 0) {
            return error.StatFailed;
        }
        
        const size = @as(u64, @intCast(file_size));
        
        // Create file mapping
        const map_handle = windows.kernel32.CreateFileMappingW(
            file_handle,
            null,
            windows.PAGE_READONLY,
            0,
            0,
            null,
        );
        
        if (map_handle == null) {
            return error.CreateMappingFailed;
        }
        errdefer _ = windows.CloseHandle(map_handle);
        
        // Map view of file
        const ptr = windows.kernel32.MapViewOfFile(
            map_handle,
            windows.FILE_MAP_READ,
            0,
            0,
            0,
        );
        
        if (ptr == null) {
            return error.MapViewFailed;
        }
        
        const data = @as([*]const u8, @ptrCast(ptr))[0..size];
        
        // Get file time for change detection
        var file_time: windows.FILETIME = undefined;
        _ = windows.kernel32.GetFileTime(file_handle, null, null, &file_time);
        
        return Self{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .data = data,
            .generation = 0,
            .file_handle = file_handle,
            .map_handle = map_handle.?,
            .size = size,
            .mtime_ns = @as(i128, file_time.dwHighDateTime) << 32 | file_time.dwLowDateTime,
            .device_id = 0, // Volume serial number would go here
            .inode = 0, // File ID would go here
        };
    }
    
    pub fn remapIfChanged(self: *Self) !bool {
        if (builtin.os.tag == .windows) {
            return self.remapIfChangedWindows();
        } else {
            return self.remapIfChangedPosix();
        }
    }
    
    fn remapIfChangedPosix(self: *Self) !bool {
        const stat = try self.file_handle.stat();
        
        // Check for rotation (different inode)
        if (stat.inode != self.inode) {
            // File was rotated, we need to reopen
            self.close();
            const new_file = try Self.open(self.allocator, self.path);
            self.* = new_file;
            return true;
        }
        
        // Check if size changed
        if (stat.size != self.size) {
            // Unmap old view
            std.posix.munmap(@alignCast(self.data));
            
            // Remap with new size
            self.data = try std.posix.mmap(
                null,
                stat.size,
                std.posix.PROT.READ,
                .{ .TYPE = .PRIVATE },
                self.file_handle.handle,
                0,
            );
            
            self.size = stat.size;
            self.mtime_ns = stat.mtime;
            self.generation += 1;
            return true;
        }
        
        return false;
    }
    
    fn remapIfChangedWindows(self: *Self) !bool {
        // Get current file size
        var file_size: windows.LARGE_INTEGER = undefined;
        if (windows.kernel32.GetFileSizeEx(self.file_handle, &file_size) == 0) {
            return error.StatFailed;
        }
        
        const new_size = @as(u64, @intCast(file_size));
        
        // Check if size changed
        if (new_size != self.size) {
            // Unmap old view (but keep file handle open!)
            _ = windows.kernel32.UnmapViewOfFile(@ptrCast(self.data.ptr));
            _ = windows.CloseHandle(self.map_handle);
            
            // Create new mapping with same file handle
            const map_handle = windows.kernel32.CreateFileMappingW(
                self.file_handle,
                null,
                windows.PAGE_READONLY,
                0,
                0,
                null,
            );
            
            if (map_handle == null) {
                return error.CreateMappingFailed;
            }
            
            // Map new view
            const ptr = windows.kernel32.MapViewOfFile(
                map_handle,
                windows.FILE_MAP_READ,
                0,
                0,
                0,
            );
            
            if (ptr == null) {
                _ = windows.CloseHandle(map_handle);
                return error.MapViewFailed;
            }
            
            self.data = @as([*]const u8, @ptrCast(ptr))[0..new_size];
            self.map_handle = map_handle.?;
            self.size = new_size;
            self.generation += 1;
            return true;
        }
        
        return false;
    }
    
    pub fn close(self: *Self) void {
        if (builtin.os.tag == .windows) {
            _ = windows.kernel32.UnmapViewOfFile(@ptrCast(self.data.ptr));
            _ = windows.CloseHandle(self.map_handle);
            _ = windows.CloseHandle(self.file_handle);
        } else {
            std.posix.munmap(@alignCast(self.data));
            self.file_handle.close();
        }
        self.allocator.free(self.path);
    }
    
    // Helper to find line boundaries (CRLF-safe)
    pub fn findLines(self: Self, start_byte: u64, end_byte: u64) LineIterator {
        return LineIterator{
            .data = self.data,
            .pos = start_byte,
            .end = @min(end_byte, self.size),
        };
    }
};

pub const LineIterator = struct {
    data: []const u8,
    pos: u64,
    end: u64,
    
    pub const Line = struct {
        content: []const u8,
        start: u64,
        end: u64, // exclusive
    };
    
    pub fn next(self: *LineIterator) ?Line {
        if (self.pos >= self.end) return null;
        
        const start = self.pos;
        
        // Find next newline
        while (self.pos < self.end) : (self.pos += 1) {
            if (self.data[self.pos] == '\n') {
                var line_end = self.pos;
                
                // Trim \r if present (CRLF handling)
                if (line_end > start and self.data[line_end - 1] == '\r') {
                    line_end -= 1;
                }
                
                const line = Line{
                    .content = self.data[start..line_end],
                    .start = start,
                    .end = self.pos + 1, // Include the \n
                };
                
                self.pos += 1; // Move past \n
                return line;
            }
        }
        
        // No newline found - this is a partial line
        return null;
    }
};

// Block Index (.bix) - O(1) line access with incremental updates
pub const BlockIndex = struct {
    const MAGIC: u32 = 0x31584942; // "BIX1"
    const BIX_VERSION: u8 = 1;
    const DEFAULT_BLOCK_SIZE: u16 = 256;
    
    pub const Header = packed struct {
        magic: u32 = MAGIC,
        version: u8 = BIX_VERSION,
        block_size: u16 = DEFAULT_BLOCK_SIZE,
        reserved_byte: u8 = 0,
        total_lines: u64,
        last_byte: u64,
        crc32: u32,
        reserved1: u32 = 0,
        reserved2: u32 = 0,
        reserved3: u32 = 0,
        reserved4: u32 = 0,
        reserved5: u32 = 0,
        reserved6: u32 = 0,
        reserved7: u32 = 0,
        reserved8: u32 = 0,
        reserved9: u32 = 0,
    };
    
    allocator: std.mem.Allocator,
    path: []const u8,
    header: Header,
    block_offsets: []u64,
    
    const Self = @This();
    
    pub fn create(allocator: std.mem.Allocator, jsonl_path: []const u8) !Self {
        const bix_path = try std.fmt.allocPrint(allocator, "{s}.bix", .{jsonl_path});
        
        return Self{
            .allocator = allocator,
            .path = bix_path,
            .header = Header{},
            .block_offsets = &[_]u64{},
        };
    }
    
    pub fn load(allocator: std.mem.Allocator, jsonl_path: []const u8) !Self {
        const bix_path = try std.fmt.allocPrint(allocator, "{s}.bix", .{jsonl_path});
        errdefer allocator.free(bix_path);
        
        const file = std.fs.openFileAbsolute(bix_path, .{}) catch {
            // No index file exists yet
            return Self{
                .allocator = allocator,
                .path = bix_path,
                .header = Header{
                    .total_lines = 0,
                    .last_byte = 0,
                    .crc32 = 0,
                },
                .block_offsets = &[_]u64{},
            };
        };
        defer file.close();
        
        // Read header
        var header: Header = undefined;
        _ = try file.read(std.mem.asBytes(&header));
        
        if (header.magic != MAGIC or header.version != BIX_VERSION) {
            return error.InvalidBixFile;
        }
        
        // Read block offsets
        const blocks_count = (header.total_lines + header.block_size - 1) / header.block_size;
        const block_offsets = try allocator.alloc(u64, blocks_count);
        _ = try file.read(std.mem.sliceAsBytes(block_offsets));
        
        return Self{
            .allocator = allocator,
            .path = bix_path,
            .header = header,
            .block_offsets = block_offsets,
        };
    }
    
    pub fn appendIncremental(self: *Self, mapped_file: *const MappedFile) !void {
        var crc = std.hash.Crc32.init();
        
        // If we have existing data, start CRC from there
        if (self.header.last_byte > 0) {
            crc.update(mapped_file.data[0..self.header.last_byte]);
        }
        
        var line_count = self.header.total_lines;
        var pos = self.header.last_byte;
        var new_blocks = std.ArrayList(u64).init(self.allocator);
        defer new_blocks.deinit();
        
        // Scan for new lines starting from last_byte
        var iter = mapped_file.findLines(pos, mapped_file.size);
        while (iter.next()) |line| {
            // Update CRC with new data
            crc.update(mapped_file.data[pos..line.end]);
            pos = line.end;
            
            line_count += 1;
            
            // Record block boundary
            if (line_count % self.header.block_size == 0) {
                try new_blocks.append(line.end);
            }
        }
        
        // Only update if we found new complete lines
        if (line_count > self.header.total_lines) {
            // Extend block_offsets array
            const old_len = self.block_offsets.len;
            const new_total = old_len + new_blocks.items.len;
            
            if (new_blocks.items.len > 0) {
                // Properly handle empty slice case
                if (self.block_offsets.len == 0) {
                    self.block_offsets = try self.allocator.alloc(u64, new_blocks.items.len);
                    @memcpy(self.block_offsets, new_blocks.items);
                } else {
                    self.block_offsets = try self.allocator.realloc(self.block_offsets, new_total);
                    @memcpy(self.block_offsets[old_len..], new_blocks.items);
                }
            }
            
            // Update header (this will be written last for atomicity)
            self.header.total_lines = line_count;
            self.header.last_byte = pos;
            self.header.crc32 = crc.final();
            
            // Write to file atomically
            try self.writeAtomic();
        }
    }
    
    fn writeAtomic(self: *Self) !void {
        // Write to temp file first
        const tmp_path = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{self.path});
        defer self.allocator.free(tmp_path);
        
        const file = try std.fs.createFileAbsolute(tmp_path, .{});
        defer file.close();
        
        // Write block offsets first
        try file.writeAll(std.mem.sliceAsBytes(self.block_offsets));
        
        // Write header last (single atomic write makes it valid)
        try file.seekTo(0);
        try file.writeAll(std.mem.asBytes(&self.header));
        try file.writeAll(std.mem.sliceAsBytes(self.block_offsets));
        
        // Sync to disk
        try file.sync();
        
        // Atomic rename
        try std.fs.renameAbsolute(tmp_path, self.path);
    }
    
    pub fn getLineOffset(self: Self, line_no: u64) ?u64 {
        if (line_no >= self.header.total_lines) return null;
        if (line_no == 0) return 0;
        
        const block_idx = line_no / self.header.block_size;
        if (block_idx == 0) return 0;
        
        // Bounds check
        if (block_idx - 1 >= self.block_offsets.len) return null;
        
        return self.block_offsets[block_idx - 1];
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.path);
        if (self.block_offsets.len > 0) {
            self.allocator.free(self.block_offsets);
        }
    }
};

// ================================================================================
// SECTION 3: SQLite Database Layer
// ================================================================================

const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const Database = struct {
    allocator: std.mem.Allocator,
    db: *sqlite.sqlite3,
    
    // Prepared statements for hot paths
    insert_message_stmt: ?*sqlite.sqlite3_stmt = null,
    get_messages_stmt: ?*sqlite.sqlite3_stmt = null,
    update_source_file_stmt: ?*sqlite.sqlite3_stmt = null,
    get_latest_source_stmt: ?*sqlite.sqlite3_stmt = null,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        var db: ?*sqlite.sqlite3 = null;
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        
        if (sqlite.sqlite3_open(path_z, &db) != sqlite.SQLITE_OK) {
            return error.DatabaseOpenFailed;
        }
        errdefer _ = sqlite.sqlite3_close(db);
        
        var self = Self{
            .allocator = allocator,
            .db = db.?,
        };
        
        // Set pragmas for performance
        try self.exec("PRAGMA journal_mode=WAL");
        try self.exec("PRAGMA synchronous=NORMAL");
        try self.exec("PRAGMA foreign_keys=ON");
        try self.exec("PRAGMA page_size=8192");
        try self.exec("PRAGMA temp_store=MEMORY");
        try self.exec("PRAGMA cache_size=-64000"); // ~64MB
        
        // Create schema if needed
        try self.createSchema();
        
        // Prepare hot path statements
        try self.prepareStatements();
        
        return self;
    }
    
    fn createSchema(self: *Self) !void {
        // Create tables
        try self.exec(
            \\CREATE TABLE IF NOT EXISTS source_files (
            \\  id INTEGER PRIMARY KEY,
            \\  path TEXT UNIQUE NOT NULL,
            \\  device_id TEXT,
            \\  inode TEXT,
            \\  size_bytes INTEGER NOT NULL,
            \\  mtime_ns INTEGER NOT NULL,
            \\  last_line INTEGER NOT NULL DEFAULT 0,
            \\  last_byte INTEGER NOT NULL DEFAULT 0,
            \\  truncated INTEGER NOT NULL DEFAULT 0,
            \\  checksum TEXT
            \\)
        );
        
        try self.exec(
            \\CREATE TABLE IF NOT EXISTS conversations (
            \\  id TEXT PRIMARY KEY,
            \\  display_title TEXT,
            \\  created_at INTEGER,
            \\  updated_at INTEGER,
            \\  last_position INTEGER NOT NULL DEFAULT 0,
            \\  message_count INTEGER NOT NULL DEFAULT 0,
            \\  total_chars INTEGER NOT NULL DEFAULT 0
            \\)
        );
        
        try self.exec(
            \\CREATE TABLE IF NOT EXISTS messages (
            \\  id INTEGER PRIMARY KEY,
            \\  conversation_id TEXT NOT NULL,
            \\  source_file_id INTEGER NOT NULL,
            \\  line_no INTEGER NOT NULL,
            \\  byte_start INTEGER NOT NULL,
            \\  byte_end INTEGER NOT NULL,
            \\  position INTEGER NOT NULL,
            \\  role TEXT NOT NULL,
            \\  content TEXT NOT NULL,
            \\  timestamp INTEGER,
            \\  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
            \\  FOREIGN KEY(source_file_id) REFERENCES source_files(id),
            \\  UNIQUE(source_file_id, line_no)
            \\)
        );
        
        // Create indexes
        try self.exec("CREATE INDEX IF NOT EXISTS idx_msg_conv_pos_desc ON messages(conversation_id, position DESC)");
        try self.exec("CREATE INDEX IF NOT EXISTS idx_msg_file_line ON messages(source_file_id, line_no)");
        try self.exec("CREATE INDEX IF NOT EXISTS idx_conv_updated_desc ON conversations(updated_at DESC)");
        
        // Create FTS5 table for search
        try self.exec(
            \\CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            \\  content,
            \\  conversation_id UNINDEXED,
            \\  content='messages',
            \\  content_rowid='id',
            \\  tokenize='unicode61'
            \\)
        );
        
        // Create triggers for FTS
        try self.exec(
            \\CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
            \\  INSERT INTO messages_fts(rowid, content, conversation_id)
            \\  VALUES (new.id, new.content, new.conversation_id);
            \\END
        );
        
        try self.exec(
            \\CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
            \\  INSERT INTO messages_fts(messages_fts, rowid, content, conversation_id)
            \\  VALUES ('delete', old.id, old.content, old.conversation_id);
            \\END
        );
        
        try self.exec(
            \\CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
            \\  INSERT INTO messages_fts(messages_fts, rowid, content, conversation_id)
            \\  VALUES ('delete', old.id, old.content, old.conversation_id);
            \\  INSERT INTO messages_fts(rowid, content, conversation_id)
            \\  VALUES (new.id, new.content, new.conversation_id);
            \\END
        );
    }
    
    fn prepareStatements(self: *Self) !void {
        // Insert message statement
        const insert_sql = 
            \\INSERT OR IGNORE INTO messages 
            \\(conversation_id, source_file_id, line_no, byte_start, byte_end, position, role, content, timestamp)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ;
        if (sqlite.sqlite3_prepare_v2(self.db, insert_sql, -1, &self.insert_message_stmt, null) != sqlite.SQLITE_OK) {
            return error.PrepareStatementFailed;
        }
        
        // Get messages with keyset pagination
        const get_messages_sql =
            \\SELECT id, role, content, position, timestamp
            \\FROM messages
            \\WHERE conversation_id = ? AND position < ?
            \\ORDER BY position DESC
            \\LIMIT ?
        ;
        if (sqlite.sqlite3_prepare_v2(self.db, get_messages_sql, -1, &self.get_messages_stmt, null) != sqlite.SQLITE_OK) {
            return error.PrepareStatementFailed;
        }
        
        // Update source file progress
        const update_source_sql =
            \\UPDATE source_files 
            \\SET last_line = ?, last_byte = ?, size_bytes = ?, mtime_ns = ?
            \\WHERE id = ?
        ;
        if (sqlite.sqlite3_prepare_v2(self.db, update_source_sql, -1, &self.update_source_file_stmt, null) != sqlite.SQLITE_OK) {
            return error.PrepareStatementFailed;
        }
        
        // Get latest source file for conversation
        const get_latest_sql =
            \\SELECT sf.id, sf.path, sf.last_byte
            \\FROM source_files sf
            \\JOIN messages m ON m.source_file_id = sf.id
            \\WHERE m.conversation_id = ?
            \\ORDER BY m.id DESC
            \\LIMIT 1
        ;
        if (sqlite.sqlite3_prepare_v2(self.db, get_latest_sql, -1, &self.get_latest_source_stmt, null) != sqlite.SQLITE_OK) {
            return error.PrepareStatementFailed;
        }
    }
    
    pub fn exec(self: *Self, sql: []const u8) !void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        if (sqlite.sqlite3_exec(self.db, sql_z, null, null, null) != sqlite.SQLITE_OK) {
            std.debug.print("SQL Error: {s}\n", .{sqlite.sqlite3_errmsg(self.db)});
            return error.SqlExecFailed;
        }
    }
    
    pub fn beginTransaction(self: *Self) !void {
        try self.exec("BEGIN IMMEDIATE");
    }
    
    pub fn commit(self: *Self) !void {
        try self.exec("COMMIT");
    }
    
    pub fn rollback(self: *Self) !void {
        try self.exec("ROLLBACK");
    }
    
    // Get or create source file entry
    pub fn getOrCreateSourceFile(self: *Self, path: []const u8, stat: std.fs.File.Stat) !i64 {
        const sql = 
            \\INSERT OR IGNORE INTO source_files (path, device_id, inode, size_bytes, mtime_ns)
            \\VALUES (?, ?, ?, ?, ?)
        ;
        
        var stmt: ?*sqlite.sqlite3_stmt = null;
        defer _ = sqlite.sqlite3_finalize(stmt);
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        if (sqlite.sqlite3_prepare_v2(self.db, sql_z, -1, &stmt, null) != sqlite.SQLITE_OK) {
            return error.PrepareStatementFailed;
        }
        
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);
        
        _ = sqlite.sqlite3_bind_text(stmt, 1, path_z, @intCast(path.len), sqlite.SQLITE_STATIC);
        _ = sqlite.sqlite3_bind_text(stmt, 2, "0", 1, sqlite.SQLITE_STATIC); // device_id placeholder
        _ = sqlite.sqlite3_bind_text(stmt, 3, "0", 1, sqlite.SQLITE_STATIC); // inode placeholder
        _ = sqlite.sqlite3_bind_int64(stmt, 4, @intCast(stat.size));
        _ = sqlite.sqlite3_bind_int64(stmt, 5, @intCast(stat.mtime));
        
        if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) {
            return error.InsertFailed;
        }
        
        // Get the ID
        return sqlite.sqlite3_last_insert_rowid(self.db);
    }
    
    // Get conversation positions for incremental import
    pub fn getConversationPositions(self: *Self) !std.StringHashMap(i64) {
        var map = std.StringHashMap(i64).init(self.allocator);
        
        const sql = "SELECT id, last_position FROM conversations";
        var stmt: ?*sqlite.sqlite3_stmt = null;
        defer _ = sqlite.sqlite3_finalize(stmt);
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        if (sqlite.sqlite3_prepare_v2(self.db, sql_z, -1, &stmt, null) != sqlite.SQLITE_OK) {
            return error.PrepareStatementFailed;
        }
        
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            const id = std.mem.span(sqlite.sqlite3_column_text(stmt, 0));
            const position = sqlite.sqlite3_column_int64(stmt, 1);
            try map.put(try self.allocator.dupe(u8, id), position);
        }
        
        return map;
    }
    
    // Search result structure for database queries
    pub const DatabaseSearchResult = struct {
        conversation_id: []const u8,
        score: f32,
        snippet: []const u8,
        message_count: u32,
        total_chars: u32,
        position: u32,
    };
    
    // Fast FTS5 search using database
    pub fn search(self: *Self, query: []const u8) ![]DatabaseSearchResult {
        const sql = 
            \\SELECT DISTINCT
            \\  m.conversation_id,
            \\  1.0 as score,
            \\  SUBSTR(m.content, 1, 200) as snippet,
            \\  c.message_count,
            \\  c.total_chars,
            \\  m.position
            \\FROM messages_fts
            \\JOIN messages m ON messages_fts.rowid = m.id  
            \\JOIN conversations c ON m.conversation_id = c.id
            \\WHERE messages_fts MATCH ?
            \\ORDER BY m.conversation_id
            \\LIMIT 50
        ;
        
        var stmt: ?*sqlite.sqlite3_stmt = null;
        defer _ = sqlite.sqlite3_finalize(stmt);
        
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);
        
        if (sqlite.sqlite3_prepare_v2(self.db, sql_z, -1, &stmt, null) != sqlite.SQLITE_OK) {
            std.debug.print("SQL Error: {s}\n", .{sqlite.sqlite3_errmsg(self.db)});
            return error.PrepareStatementFailed;
        }
        
        const query_z = try self.allocator.dupeZ(u8, query);
        defer self.allocator.free(query_z);
        _ = sqlite.sqlite3_bind_text(stmt, 1, query_z, @intCast(query.len), sqlite.SQLITE_STATIC);
        
        var results = std.ArrayList(DatabaseSearchResult).init(self.allocator);
        
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            const conversation_id = std.mem.span(sqlite.sqlite3_column_text(stmt, 0));
            const score = @as(f32, @floatCast(sqlite.sqlite3_column_double(stmt, 1)));
            const snippet = std.mem.span(sqlite.sqlite3_column_text(stmt, 2));
            const message_count = @as(u32, @intCast(sqlite.sqlite3_column_int(stmt, 3)));
            const total_chars = @as(u32, @intCast(sqlite.sqlite3_column_int(stmt, 4)));
            const position = @as(u32, @intCast(sqlite.sqlite3_column_int(stmt, 5)));
            
            try results.append(DatabaseSearchResult{
                .conversation_id = try self.allocator.dupe(u8, conversation_id),
                .score = score,
                .snippet = try self.allocator.dupe(u8, snippet),
                .message_count = message_count,
                .total_chars = total_chars,
                .position = position,
            });
        }
        
        return results.toOwnedSlice();
    }
    
    // Free search results
    pub fn freeSearchResults(self: *Self, results: []DatabaseSearchResult) void {
        for (results) |result| {
            self.allocator.free(result.conversation_id);
            self.allocator.free(result.snippet);
        }
        self.allocator.free(results);
    }

    pub fn deinit(self: *Self) void {
        if (self.insert_message_stmt) |stmt| _ = sqlite.sqlite3_finalize(stmt);
        if (self.get_messages_stmt) |stmt| _ = sqlite.sqlite3_finalize(stmt);
        if (self.update_source_file_stmt) |stmt| _ = sqlite.sqlite3_finalize(stmt);
        if (self.get_latest_source_stmt) |stmt| _ = sqlite.sqlite3_finalize(stmt);
        _ = sqlite.sqlite3_close(self.db);
    }
};

// ================================================================================
// SECTION 4: Incremental Importer with Live Tail Overlay
// ================================================================================

pub const IncrementalImporter = struct {
    allocator: std.mem.Allocator,
    db: *Database,
    mapped_files: std.StringHashMap(*MappedFile),
    block_indexes: std.StringHashMap(*BlockIndex),
    conv_positions: std.StringHashMap(i64),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, db: *Database) !Self {
        return Self{
            .allocator = allocator,
            .db = db,
            .mapped_files = std.StringHashMap(*MappedFile).init(allocator),
            .block_indexes = std.StringHashMap(*BlockIndex).init(allocator),
            .conv_positions = try db.getConversationPositions(),
        };
    }
    
    pub fn importFile(self: *Self, path: []const u8) !void {
        // Get or create mapped file
        var mapped_file = self.mapped_files.get(path) orelse blk: {
            const mf = try self.allocator.create(MappedFile);
            mf.* = try MappedFile.open(self.allocator, path);
            try self.mapped_files.put(path, mf);
            break :blk mf;
        };
        
        // Check for changes and remap if needed
        _ = try mapped_file.remapIfChanged();
        
        // Get or create block index
        var block_idx = self.block_indexes.get(path) orelse blk: {
            const bi = try self.allocator.create(BlockIndex);
            bi.* = try BlockIndex.load(self.allocator, path);
            try self.block_indexes.put(path, bi);
            break :blk bi;
        };
        
        // DO NOT update block index here - we need to import first!
        // Save the starting point for import
        const start_byte = block_idx.header.last_byte;
        const start_lines = block_idx.header.total_lines;
        
        // Get source file record
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        const stat = try file.stat();
        const source_file_id = try self.db.getOrCreateSourceFile(path, stat);
        
        // Transaction handling - only begin if we have lines to process
        var transaction_active = false;
        defer {
            if (transaction_active) {
                self.db.rollback() catch {};
            }
        }
        
        // Ensure conversation exists in database
        const file_basename = std.fs.path.basename(path);
        const conv_id_no_ext = if (std.mem.endsWith(u8, file_basename, ".jsonl"))
            file_basename[0..file_basename.len - 6]
        else
            file_basename;
        
        // Insert conversation if it doesn't exist
        const conv_sql = 
            \\INSERT OR IGNORE INTO conversations (id, display_title, created_at, updated_at)
            \\VALUES (?, ?, ?, ?)
        ;
        var conv_stmt: ?*sqlite.sqlite3_stmt = null;
        if (sqlite.sqlite3_prepare_v2(self.db.db, conv_sql, -1, &conv_stmt, null) == sqlite.SQLITE_OK) {
            defer _ = sqlite.sqlite3_finalize(conv_stmt);
            _ = sqlite.sqlite3_bind_text(conv_stmt, 1, conv_id_no_ext.ptr, @intCast(conv_id_no_ext.len), sqlite.SQLITE_STATIC);
            _ = sqlite.sqlite3_bind_text(conv_stmt, 2, conv_id_no_ext.ptr, @intCast(conv_id_no_ext.len), sqlite.SQLITE_STATIC);
            _ = sqlite.sqlite3_bind_int64(conv_stmt, 3, @intCast(@divTrunc(mapped_file.mtime_ns, 1_000_000)));
            _ = sqlite.sqlite3_bind_int64(conv_stmt, 4, @intCast(@divTrunc(mapped_file.mtime_ns, 1_000_000)));
            _ = sqlite.sqlite3_step(conv_stmt);
        }
        
        // Import new lines since last_byte
        var line_no = start_lines;
        var iter = mapped_file.findLines(start_byte, mapped_file.size);
        
        var batch_count: usize = 0;
        const batch_size = 5000;
        
        var total_messages: usize = 0;
        var lines_processed: usize = 0;
        var parse_errors: usize = 0;
        while (iter.next()) |line| {
            // Begin transaction on first line processing
            if (!transaction_active) {
                try self.db.beginTransaction();
                transaction_active = true;
            }
            
            lines_processed += 1;
            // Parse JSON line
            const parsed = std.json.parseFromSlice(
                std.json.Value,
                self.allocator,
                line.content,
                .{ .allocate = .alloc_always }
            ) catch {
                parse_errors += 1;
                if (lines_processed <= 5) {
                    std.debug.print("    JSON parse error on line {}: {s}\n", .{line_no, line.content[0..@min(100, line.content.len)]});
                }
                continue;
            };
            defer parsed.deinit();
            
            // Extract conversation info
            const conv_id = self.extractConversationId(parsed.value, path) catch continue;
            const role = self.extractRole(parsed.value) catch |err| {
                if (lines_processed <= 5) {
                    std.debug.print("    Failed to extract role on line {}: {} - JSON: {s}\n", .{line_no, err, line.content[0..@min(200, line.content.len)]});
                }
                continue;
            };
            const content = self.extractContent(parsed.value) catch |err| {
                if (lines_processed <= 5) {
                    std.debug.print("    Failed to extract content for role {s} on line {}: {} - JSON: {s}\n", .{role, line_no, err, line.content[0..@min(200, line.content.len)]});
                }
                continue;
            };
            const timestamp = self.extractTimestamp(parsed.value);
            
            // Get or increment position for this conversation
            const position = blk: {
                const entry = try self.conv_positions.getOrPut(conv_id);
                if (!entry.found_existing) {
                    entry.value_ptr.* = 0;
                }
                entry.value_ptr.* += 1;
                break :blk entry.value_ptr.*;
            };
            
            // Insert message using prepared statement
            const stmt = self.db.insert_message_stmt.?;
            _ = sqlite.sqlite3_reset(stmt);
            _ = sqlite.sqlite3_bind_text(stmt, 1, conv_id.ptr, @intCast(conv_id.len), sqlite.SQLITE_STATIC);
            _ = sqlite.sqlite3_bind_int64(stmt, 2, source_file_id);
            _ = sqlite.sqlite3_bind_int64(stmt, 3, @intCast(line_no));
            _ = sqlite.sqlite3_bind_int64(stmt, 4, @intCast(line.start));
            _ = sqlite.sqlite3_bind_int64(stmt, 5, @intCast(line.end));
            _ = sqlite.sqlite3_bind_int64(stmt, 6, position);
            _ = sqlite.sqlite3_bind_text(stmt, 7, role.ptr, @intCast(role.len), sqlite.SQLITE_STATIC);
            _ = sqlite.sqlite3_bind_text(stmt, 8, content.ptr, @intCast(content.len), sqlite.SQLITE_STATIC);
            if (timestamp) |ts| {
                _ = sqlite.sqlite3_bind_int64(stmt, 9, ts);
            } else {
                _ = sqlite.sqlite3_bind_null(stmt, 9);
            }
            
            if (sqlite.sqlite3_step(stmt) != sqlite.SQLITE_DONE) {
                continue; // Skip on constraint violation (duplicate)
            }
            
            total_messages += 1;
            line_no += 1;
            batch_count += 1;
            
            // Commit periodically
            if (batch_count >= batch_size) {
                try self.db.commit();
                try self.db.beginTransaction();
                batch_count = 0;
            }
        }
        
        // Update source file progress
        const update_stmt = self.db.update_source_file_stmt.?;
        _ = sqlite.sqlite3_reset(update_stmt);
        _ = sqlite.sqlite3_bind_int64(update_stmt, 1, @intCast(line_no));
        _ = sqlite.sqlite3_bind_int64(update_stmt, 2, @intCast(mapped_file.size));
        _ = sqlite.sqlite3_bind_int64(update_stmt, 3, @intCast(mapped_file.size));
        _ = sqlite.sqlite3_bind_int64(update_stmt, 4, @intCast(mapped_file.mtime_ns));
        _ = sqlite.sqlite3_bind_int64(update_stmt, 5, source_file_id);
        _ = sqlite.sqlite3_step(update_stmt);
        
        // Final commit - only if transaction was started
        if (transaction_active) {
            try self.db.commit();
            transaction_active = false; // Prevent defer rollback
        }
        
        // NOW that we've successfully imported, update the block index
        try block_idx.appendIncremental(mapped_file);
        
        std.debug.print("  Imported {} messages from {s} (processed {} lines, {} parse errors)\n", .{total_messages, std.fs.path.basename(path), lines_processed, parse_errors});
    }
    
    fn extractConversationId(self: *Self, value: std.json.Value, file_path: []const u8) ![]const u8 {
        _ = value; // Ignore JSON conversation_id to use filename instead
        
        // Use the filename as the conversation ID
        const basename = std.fs.path.basename(file_path);
        
        // Remove .jsonl extension if present
        if (std.mem.endsWith(u8, basename, ".jsonl")) {
            const name_without_ext = basename[0..basename.len - 6];
            return try self.allocator.dupe(u8, name_without_ext);
        }
        
        return try self.allocator.dupe(u8, basename);
    }
    
    fn extractRole(self: *Self, value: std.json.Value) ![]const u8 {
        _ = self;
        if (value != .object) return error.InvalidJson;
        
        // Check if this is a message type (user/assistant/system)
        const type_field = value.object.get("type") orelse return error.MissingField;
        if (type_field != .string) return error.InvalidType;
        
        const type_str = type_field.string;
        // Only process actual messages
        if (!std.mem.eql(u8, type_str, "user") and 
            !std.mem.eql(u8, type_str, "assistant") and 
            !std.mem.eql(u8, type_str, "system")) {
            return error.NotAMessage;
        }
        
        // The actual role is in message.role
        if (value.object.get("message")) |msg| {
            if (msg == .object) {
                if (msg.object.get("role")) |role| {
                    if (role == .string) return role.string;
                }
            }
        }
        
        // Fallback to type as role
        return type_str;
    }
    
    fn extractContent(self: *Self, value: std.json.Value) ![]const u8 {
        _ = self;
        if (value != .object) return error.InvalidJson;
        
        // Content is in message.content
        const msg = value.object.get("message") orelse return error.MissingField;
        if (msg != .object) return error.InvalidType;
        
        const content = msg.object.get("content") orelse return error.MissingField;
        
        switch (content) {
            .string => return content.string,
            .array => {
                // Handle array of content blocks (assistant messages)
                for (content.array.items) |item| {
                    if (item != .object) continue;
                    if (item.object.get("text")) |text| {
                        if (text == .string) return text.string;
                    }
                }
                return "";
            },
            else => return error.InvalidType,
        }
    }
    
    fn extractTimestamp(self: *Self, value: std.json.Value) ?i64 {
        _ = self;
        if (value != .object) return null;
        const ts = value.object.get("timestamp") orelse return null;
        switch (ts) {
            .integer => return ts.integer,
            .float => return @intFromFloat(ts.float),
            .string => {
                // Parse ISO 8601 timestamp like "2025-08-09T01:33:37.599Z"
                // For now, just return current timestamp as fallback
                // TODO: Implement proper ISO 8601 parsing
                return std.time.timestamp();
            },
            else => return null,
        }
    }
    
    pub fn getMessagesWithTailOverlay(
        self: *Self,
        conv_id: []const u8,
        before_position: i64,
        limit: usize,
    ) ![]Message {
        // Get messages from DB
        const stmt = self.db.get_messages_stmt.?;
        _ = sqlite.sqlite3_reset(stmt);
        _ = sqlite.sqlite3_bind_text(stmt, 1, conv_id.ptr, @intCast(conv_id.len), sqlite.SQLITE_STATIC);
        _ = sqlite.sqlite3_bind_int64(stmt, 2, before_position);
        _ = sqlite.sqlite3_bind_int64(stmt, 3, @intCast(limit));
        
        var db_messages = std.ArrayList(Message).init(self.allocator);
        defer db_messages.deinit();
        
        while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
            const role_str = std.mem.span(sqlite.sqlite3_column_text(stmt, 1));
            const role = if (std.mem.eql(u8, role_str, "user")) Role.user
                else if (std.mem.eql(u8, role_str, "assistant")) Role.assistant
                else Role.system;
            
            const content = std.mem.span(sqlite.sqlite3_column_text(stmt, 2));
            const position = sqlite.sqlite3_column_int64(stmt, 3);
            const timestamp = if (sqlite.sqlite3_column_type(stmt, 4) != sqlite.SQLITE_NULL)
                sqlite.sqlite3_column_int64(stmt, 4)
            else
                null;
            
            try db_messages.append(Message{
                .role = role,
                .content = try self.allocator.dupe(u8, content),
                .timestamp = timestamp,
            });
            
            _ = position; // Track for tail overlay boundary
        }
        
        // Get latest source file for tail overlay
        const latest_stmt = self.db.get_latest_source_stmt.?;
        _ = sqlite.sqlite3_reset(latest_stmt);
        _ = sqlite.sqlite3_bind_text(latest_stmt, 1, conv_id.ptr, @intCast(conv_id.len), sqlite.SQLITE_STATIC);
        
        if (sqlite.sqlite3_step(latest_stmt) == sqlite.SQLITE_ROW) {
            const source_path = std.mem.span(sqlite.sqlite3_column_text(latest_stmt, 1));
            const last_byte = @as(u64, @intCast(sqlite.sqlite3_column_int64(latest_stmt, 2)));
            
            // Check for unindexed tail
            if (self.mapped_files.get(source_path)) |mapped_file| {
                if (mapped_file.size > last_byte) {
                    // Parse tail lines
                    var tail_messages = std.ArrayList(Message).init(self.allocator);
                    defer tail_messages.deinit();
                    
                    var iter = mapped_file.findLines(last_byte, mapped_file.size);
                    while (iter.next()) |line| {
                        const parsed = std.json.parseFromSlice(
                            std.json.Value,
                            self.allocator,
                            line.content,
                            .{ .allocate = .alloc_always }
                        ) catch continue;
                        defer parsed.deinit();
                        
                        const line_conv_id = self.extractConversationId(parsed.value, source_path) catch continue;
                        if (!std.mem.eql(u8, line_conv_id, conv_id)) continue;
                        
                        const role_str = self.extractRole(parsed.value) catch continue;
                        const role = if (std.mem.eql(u8, role_str, "user")) Role.user
                            else if (std.mem.eql(u8, role_str, "assistant")) Role.assistant
                            else Role.system;
                        
                        const content = self.extractContent(parsed.value) catch continue;
                        const timestamp = self.extractTimestamp(parsed.value);
                        
                        try tail_messages.append(Message{
                            .role = role,
                            .content = try self.allocator.dupe(u8, content),
                            .timestamp = timestamp,
                        });
                    }
                    
                    // Merge tail with DB results (newest first)
                    const total_messages = db_messages.items.len + tail_messages.items.len;
                    var result = try self.allocator.alloc(Message, total_messages);
                    
                    // Copy tail messages first (they're newest)
                    @memcpy(result[0..tail_messages.items.len], tail_messages.items);
                    // Then DB messages
                    @memcpy(result[tail_messages.items.len..], db_messages.items);
                    
                    return result;
                }
            }
        }
        
        // No tail overlay needed, just return DB results
        return db_messages.toOwnedSlice();
    }
    
    pub fn deinit(self: *Self) void {
        var mf_iter = self.mapped_files.iterator();
        while (mf_iter.next()) |entry| {
            entry.value_ptr.*.close();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.mapped_files.deinit();
        
        var bi_iter = self.block_indexes.iterator();
        while (bi_iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.block_indexes.deinit();
        
        var cp_iter = self.conv_positions.iterator();
        while (cp_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.conv_positions.deinit();
    }
};

// ================================================================================
// SECTION 5: File System Operations (Port of find_sessions)
// ================================================================================

const FileSystem = struct {
    allocator: std.mem.Allocator,
    claude_dir: []const u8,
    output_dir: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) !FileSystem {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        
        // Build ~/.claude/projects path
        const claude_dir = try std.fmt.allocPrint(allocator, "{s}/.claude/projects", .{home});
        
        // Try to create output directory in order of preference
        var output_dirs = std.ArrayList([]const u8).init(allocator);
        defer output_dirs.deinit();
        
        try output_dirs.append(try std.fmt.allocPrint(allocator, "{s}/Desktop/Claude logs", .{home}));
        try output_dirs.append(try std.fmt.allocPrint(allocator, "{s}/Documents/Claude logs", .{home}));
        try output_dirs.append(try std.fmt.allocPrint(allocator, "{s}/Claude logs", .{home}));
        try output_dirs.append("./claude-logs");
        
        var output_dir: []const u8 = "./claude-logs";
        var selected_index: ?usize = null;
        
        for (output_dirs.items, 0..) |dir, i| {
            std.fs.makeDirAbsolute(dir) catch |err| {
                switch (err) {
                    error.PathAlreadyExists => {},
                    else => continue,
                }
            };
            
            // Test write permissions
            const test_path = try std.fmt.allocPrint(allocator, "{s}/.test", .{dir});
            defer allocator.free(test_path);
            
            if (std.fs.createFileAbsolute(test_path, .{})) |file| {
                file.close();
                std.fs.deleteFileAbsolute(test_path) catch {};
                selected_index = i;
                output_dir = dir;
                break;
            } else |_| {
                continue;
            }
        }
        
        // Free the dirs we didn't select
        for (output_dirs.items, 0..) |dir, i| {
            if (selected_index == null or i != selected_index.?) {
                if (!std.mem.eql(u8, dir, "./claude-logs")) {
                    allocator.free(dir);
                }
            }
        }
        
        // Duplicate the selected output_dir so it persists
        const final_output_dir = if (!std.mem.eql(u8, output_dir, "./claude-logs"))
            output_dir  // Already allocated, just use it
        else
            try allocator.dupe(u8, output_dir);  // Duplicate the literal
        
        // Ensure output directory exists
        std.fs.makeDirAbsolute(final_output_dir) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };
        
        return FileSystem{
            .allocator = allocator,
            .claude_dir = claude_dir,
            .output_dir = final_output_dir,
        };
    }
    
    pub fn findSessions(self: *FileSystem, project_path: ?[]const u8) ![][]const u8 {
        var sessions = std.ArrayList([]const u8).init(self.allocator);
        
        const search_dir = if (project_path) |proj| blk: {
            // If project path is absolute (starts with /), use it directly
            if (proj.len > 0 and proj[0] == '/') {
                break :blk try self.allocator.dupe(u8, proj);
            } else {
                // Otherwise, treat it as relative to claude_dir
                break :blk try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.claude_dir, proj });
            }
        } else
            try self.allocator.dupe(u8, self.claude_dir);
        
        defer self.allocator.free(search_dir);
        
        var dir = std.fs.openDirAbsolute(search_dir, .{ .iterate = true }) catch {
            std.debug.print("⚠️  Cannot open directory: {s}\n", .{search_dir});
            return sessions.toOwnedSlice();
        };
        defer dir.close();
        
        var walker = try dir.walk(self.allocator);
        defer walker.deinit();
        
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            
            // Check if it's a JSONL file
            if (std.mem.endsWith(u8, entry.basename, ".jsonl")) {
                const full_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}",
                    .{ search_dir, entry.path }
                );
                try sessions.append(full_path);
            }
        }
        
        // Sort by modification time (most recent first)
        const SessionSorter = struct {
            fn lessThan(context: void, a: []const u8, b: []const u8) bool {
                _ = context;
                const a_stat = std.fs.cwd().statFile(a) catch return false;
                const b_stat = std.fs.cwd().statFile(b) catch return false;
                return a_stat.mtime > b_stat.mtime;
            }
        };
        
        std.mem.sort([]const u8, sessions.items, {}, SessionSorter.lessThan);
        
        return sessions.toOwnedSlice();
    }
    
    pub fn deinit(self: *FileSystem) void {
        self.allocator.free(self.claude_dir);
        self.allocator.free(self.output_dir);
    }
};

// ================================================================================
// SECTION 3: JSONL Parser with Streaming Support
// ================================================================================

const StreamingJSONLParser = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    buffer: []u8,
    buffer_size: usize = 64 * 1024, // 64KB buffer for streaming
    line_arena: std.heap.ArenaAllocator, // Reusable arena for line parsing
    
    pub fn init(allocator: std.mem.Allocator) !StreamingJSONLParser {
        const buffer = try allocator.alloc(u8, 64 * 1024);
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .buffer = buffer,
            .line_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }
    
    pub fn deinit(self: *StreamingJSONLParser) void {
        self.allocator.free(self.buffer);
        self.arena.deinit();
        self.line_arena.deinit();
    }
    
    pub fn reset(self: *StreamingJSONLParser) void {
        // Reset arenas for next file
        _ = self.arena.reset(.retain_capacity);
        _ = self.line_arena.reset(.retain_capacity);
    }
    
    // Stream parse large files without loading everything into memory
    pub fn parseFileStreaming(self: *StreamingJSONLParser, file_path: []const u8) !Conversation {
        const file = try std.fs.openFileAbsolute(file_path, .{});
        defer file.close();
        
        const file_stat = try file.stat();
        
        // For small files, use the old method
        if (file_stat.size < 10 * 1024 * 1024) { // < 10MB
            const content = try file.readToEndAlloc(self.allocator, file_stat.size);
            defer self.allocator.free(content);
            return try self.parseContent(content, file_path);
        }
        
        // For large files, stream parse
        return try self.streamParse(file, file_path);
    }
    
    fn streamParse(self: *StreamingJSONLParser, file: std.fs.File, file_path: []const u8) !Conversation {
        var messages = std.ArrayList(Message).init(self.allocator);
        errdefer messages.deinit();
        
        var line_buffer = std.ArrayList(u8).init(self.allocator);
        defer line_buffer.deinit();
        
        const created_at: i64 = std.time.timestamp();
        const updated_at: i64 = created_at;
        var total_chars: usize = 0;
        var user_count: usize = 0;
        var assistant_count: usize = 0;
        
        // Read file in chunks
        while (true) {
            const bytes_read = try file.read(self.buffer);
            if (bytes_read == 0) break;
            
            // Process chunk
            for (self.buffer[0..bytes_read]) |byte| {
                if (byte == '\n') {
                    if (line_buffer.items.len > 0) {
                        // Parse the line using reusable arena
                        _ = self.line_arena.reset(.retain_capacity);
                        
                        if (std.json.parseFromSlice(
                            std.json.Value,
                            self.line_arena.allocator(),
                            line_buffer.items,
                            .{},
                        )) |parsed| {
                            defer parsed.deinit();
                            
                            if (try self.extractMessage(parsed.value)) |message| {
                                if (message.content.len > 0) {
                                    total_chars += message.content.len;
                                    switch (message.role) {
                                        .user => user_count += 1,
                                        .assistant => assistant_count += 1,
                                        .system => {},
                                    }
                                    try messages.append(message);
                                }
                            }
                        } else |_| {
                            // Skip malformed lines
                        }
                        
                        line_buffer.clearRetainingCapacity();
                    }
                } else {
                    try line_buffer.append(byte);
                }
            }
        }
        
        // Handle trailing buffer if file doesn't end with newline
        if (line_buffer.items.len > 0) {
            _ = self.line_arena.reset(.retain_capacity);
            if (std.json.parseFromSlice(std.json.Value, self.line_arena.allocator(), line_buffer.items, .{})) |parsed| {
                defer parsed.deinit();
                if (try self.extractMessage(parsed.value)) |message| {
                    if (message.content.len > 0) {
                        total_chars += message.content.len;
                        switch (message.role) {
                            .user => user_count += 1,
                            .assistant => assistant_count += 1,
                            .system => {},
                        }
                        try messages.append(message);
                    }
                }
            } else |_| {}
            line_buffer.clearRetainingCapacity();
        }
        
        const project_name = try self.extractProjectName(file_path);
        const messages_slice = try messages.toOwnedSlice();
        
        return Conversation{
            .id = try self.allocator.dupe(u8, std.fs.path.basename(file_path)),
            .project_name = project_name,
            .messages = messages_slice,
            .created_at = created_at,
            .updated_at = updated_at,
            .file_path = try self.allocator.dupe(u8, file_path),
            .message_count = messages_slice.len,
            .user_message_count = user_count,
            .assistant_message_count = assistant_count,
            .total_chars = total_chars,
            .estimated_tokens = @divFloor(total_chars * 4, 3),
        };
    }
    
    pub fn parseFile(self: *StreamingJSONLParser, file_path: []const u8) !Conversation {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("DEBUG: Parsing file: {s}\n", .{std.fs.path.basename(file_path)});
        const result = try self.parseFileStreaming(file_path);
        try stderr.print("DEBUG: Parsed {s} -> ID: {s}, Messages: {d}, Chars: {d}\n", .{
            std.fs.path.basename(file_path), result.id, result.message_count, result.total_chars
        });
        return result;
    }
    
    pub fn parseContent(self: *StreamingJSONLParser, content: []const u8, file_path: []const u8) !Conversation {
        var messages = std.ArrayList(Message).init(self.allocator);
        errdefer messages.deinit();
        
        var lines = std.mem.tokenizeScalar(u8, content, '\n');
        
        var created_at: i64 = std.time.timestamp();
        var updated_at: i64 = created_at;
        var total_chars: usize = 0;
        var user_count: usize = 0;
        var assistant_count: usize = 0;
        
        var line_count: usize = 0;
        var valid_lines: usize = 0;
        
        // Parse each JSONL line
        while (lines.next()) |line| {
            line_count += 1;
            if (line.len == 0) continue;
            
            // Use arena allocator for temporary JSON parsing
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            
            // Parse the JSON line
            const parsed = std.json.parseFromSlice(
                std.json.Value,
                arena.allocator(),
                line,
                .{},
            ) catch |err| {
                std.debug.print("Warning: Failed to parse JSON line: {any}\n", .{err});
                continue;
            };
            defer parsed.deinit();
            
            // Extract message from the parsed JSON
            if (try self.extractMessage(parsed.value)) |message| {
                // Skip empty messages
                if (message.content.len == 0) {
                    self.allocator.free(message.content);
                    continue;
                }
                
                // Update statistics
                total_chars += message.content.len;
                switch (message.role) {
                    .user => user_count += 1,
                    .assistant => assistant_count += 1,
                    .system => {},
                }
                
                // Extract timestamps if available
                if (parsed.value.object.get("created_at")) |created| {
                    if (created == .integer) {
                        if (user_count == 1 and assistant_count == 0) {
                            created_at = created.integer;
                        }
                    }
                }
                if (parsed.value.object.get("updated_at")) |updated| {
                    if (updated == .integer) {
                        updated_at = updated.integer;
                    }
                }
                
                try messages.append(message);
                valid_lines += 1;
            }
        }
        
        const stderr = std.io.getStdErr().writer();
        stderr.print("PARSER: File {s} - processed {d} lines, {d} valid messages\n", .{
            std.fs.path.basename(file_path), line_count, valid_lines
        }) catch {};
        
        // Extract project name from path
        const project_name = try self.extractProjectName(file_path);
        errdefer self.allocator.free(project_name);
        
        const id = try self.allocator.dupe(u8, std.fs.path.basename(file_path));
        errdefer self.allocator.free(id);
        
        const file_path_copy = try self.allocator.dupe(u8, file_path);
        errdefer self.allocator.free(file_path_copy);
        
        const messages_slice = try messages.toOwnedSlice();
        
        return Conversation{
            .id = id,
            .project_name = project_name,
            .messages = messages_slice,
            .created_at = created_at,
            .updated_at = updated_at,
            .file_path = file_path_copy,
            .message_count = messages_slice.len,
            .user_message_count = user_count,
            .assistant_message_count = assistant_count,
            .total_chars = total_chars,
            .estimated_tokens = @divFloor(total_chars * 4, 3),
        };
    }
    
    fn extractMessage(self: *StreamingJSONLParser, value: std.json.Value) !?Message {
        if (value != .object) return null;
        const obj = value.object;

        var role_opt: ?Role = null;
        var content_val_opt: ?std.json.Value = null;

        // Path A: type=user/assistant + message{role,content}
        if (obj.get("type")) |t| {
            if (t == .string) {
                if (std.mem.eql(u8, t.string, "user") or std.mem.eql(u8, t.string, "assistant")) {
                    if (obj.get("message")) |m| {
                        if (m == .object) {
                            if (m.object.get("role")) |r| {
                                if (r == .string) {
                                    role_opt = if (std.mem.eql(u8, r.string, "user")) .user
                                               else if (std.mem.eql(u8, r.string, "assistant")) .assistant
                                               else .system;
                                }
                            }
                            if (m.object.get("content")) |c| content_val_opt = c;
                        }
                    }
                }
            }
        }

        // Path B: message{role,content} regardless of top-level type
        if (role_opt == null or content_val_opt == null) {
            if (obj.get("message")) |m| {
                if (m == .object) {
                    if (m.object.get("role")) |r| {
                        if (r == .string) {
                            role_opt = if (std.mem.eql(u8, r.string, "user")) .user
                                       else if (std.mem.eql(u8, r.string, "assistant")) .assistant
                                       else .system;
                        }
                    }
                    if (m.object.get("content")) |c| content_val_opt = c;
                }
            }
        }

        // Path C: role/content at top level
        if (role_opt == null or content_val_opt == null) {
            if (obj.get("role")) |r| {
                if (r == .string) {
                    role_opt = if (std.mem.eql(u8, r.string, "user")) .user
                               else if (std.mem.eql(u8, r.string, "assistant")) .assistant
                               else .system;
                }
            }
            if (obj.get("content")) |c| content_val_opt = c;
        }

        if (role_opt == null or content_val_opt == null) return null;

        var content_builder = std.ArrayList(u8).init(self.allocator);
        errdefer content_builder.deinit();
        try self.extractContent(content_val_opt.?, &content_builder);

        const content_str = try content_builder.toOwnedSlice();

        // Timestamp still optional:
        var timestamp: ?i64 = null;
        if (obj.get("created_at")) |ts| {
            switch (ts) {
                .integer => timestamp = ts.integer,
                .float => timestamp = @intFromFloat(ts.float),
                else => {},
            }
        }

        return Message{
            .role = role_opt.?,
            .content = content_str,
            .timestamp = timestamp,
            .tool_calls = null,
            .tool_responses = null,
        };
    }
    
    fn extractContent(_: *StreamingJSONLParser, content_val: std.json.Value, builder: *std.ArrayList(u8)) !void {
        switch (content_val) {
            .string => {
                // Simple string content (user messages)
                try builder.appendSlice(content_val.string);
            },
            .array => {
                // Array of content blocks (assistant messages)
                for (content_val.array.items, 0..) |item, i| {
                    if (item != .object) continue;
                    
                    const block_type = item.object.get("type") orelse continue;
                    if (block_type != .string) continue;
                    
                    if (std.mem.eql(u8, block_type.string, "text")) {
                        if (item.object.get("text")) |text| {
                            if (text == .string) {
                                if (i > 0 and builder.items.len > 0) {
                                    try builder.append('\n');
                                }
                                try builder.appendSlice(text.string);
                            }
                        }
                    } else if (std.mem.eql(u8, block_type.string, "tool_use")) {
                        // Handle tool use blocks
                        if (item.object.get("name")) |name| {
                            if (name == .string) {
                                if (builder.items.len > 0) try builder.append('\n');
                                try builder.appendSlice("[Tool: ");
                                try builder.appendSlice(name.string);
                                try builder.appendSlice("]\n");
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }
    
    fn extractProjectName(self: *StreamingJSONLParser, file_path: []const u8) ![]const u8 {
        // Extract project name from path (e.g., /home/user/.claude/projects/myproject/...)
        if (std.mem.indexOf(u8, file_path, "/projects/")) |start| {
            const after_projects = file_path[start + 10..];
            if (std.mem.indexOf(u8, after_projects, "/")) |end| {
                return try self.allocator.dupe(u8, after_projects[0..end]);
            }
        }
        return try self.allocator.dupe(u8, "unknown");
    }
};

// Alias for compatibility
const JSONLParser = StreamingJSONLParser;

// ================================================================================
// SECTION 4: Export Formats (Port of save_as_markdown and export_formats)
// ================================================================================

const ExportManager = struct {
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    
    pub fn exportMarkdown(_: *ExportManager, conversation: *const Conversation, output_path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(output_path, .{});
        defer file.close();
        
        var writer = file.writer();
        
        // Write header
        try writer.print("# Claude Conversation Log\n\n", .{});
        try writer.print("Session ID: {s}\n", .{conversation.id});
        try writer.print("Project: {s}\n", .{conversation.project_name});
        try writer.print("Date: {d}\n", .{conversation.created_at});
        try writer.print("Messages: {d}\n", .{conversation.message_count});
        try writer.print("\n---\n\n", .{});
        
        // Write messages
        for (conversation.messages) |msg| {
            switch (msg.role) {
                .user => try writer.print("## 👤 User\n\n", .{}),
                .assistant => try writer.print("## 🤖 Claude\n\n", .{}),
                .system => try writer.print("## ⚙️ System\n\n", .{}),
            }
            
            // Write content
            try writer.print("{s}\n\n", .{msg.content});
            try writer.print("---\n\n", .{});
        }
    }
    
    pub fn exportJSON(_: *ExportManager, conversation: *const Conversation, output_path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(output_path, .{});
        defer file.close();
        
        var writer = file.writer();
        
        // Start JSON object
        try writer.print("{{\n", .{});
        try writer.print("  \"id\": \"{s}\",\n", .{conversation.id});
        try writer.print("  \"project\": \"{s}\",\n", .{conversation.project_name});
        try writer.print("  \"created_at\": {d},\n", .{conversation.created_at});
        try writer.print("  \"updated_at\": {d},\n", .{conversation.updated_at});
        try writer.print("  \"message_count\": {d},\n", .{conversation.message_count});
        try writer.print("  \"total_chars\": {d},\n", .{conversation.total_chars});
        try writer.print("  \"estimated_tokens\": {d},\n", .{conversation.estimated_tokens});
        try writer.print("  \"messages\": [\n", .{});
        
        // Write messages
        for (conversation.messages, 0..) |msg, i| {
            try writer.print("    {{\n", .{});
            try writer.print("      \"role\": \"{s}\",\n", .{@tagName(msg.role)});
            
            // Escape JSON string content
            try writer.print("      \"content\": \"", .{});
            for (msg.content) |c| {
                switch (c) {
                    '"' => try writer.print("\\\"", .{}),
                    '\\' => try writer.print("\\\\", .{}),
                    '\n' => try writer.print("\\n", .{}),
                    '\r' => try writer.print("\\r", .{}),
                    '\t' => try writer.print("\\t", .{}),
                    else => try writer.writeByte(c),
                }
            }
            try writer.print("\"", .{});
            
            if (msg.timestamp) |ts| {
                try writer.print(",\n      \"timestamp\": {d}", .{ts});
            }
            
            try writer.print("\n    }}", .{});
            if (i < conversation.messages.len - 1) {
                try writer.print(",", .{});
            }
            try writer.print("\n", .{});
        }
        
        try writer.print("  ]\n", .{});
        try writer.print("}}\n", .{});
    }
    
    pub fn exportHTML(_: *ExportManager, conversation: *const Conversation, output_path: []const u8) !void {
        const file = try std.fs.createFileAbsolute(output_path, .{});
        defer file.close();
        
        var writer = file.writer();
        
        // HTML header with embedded CSS
        try writer.print(
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\    <meta charset="UTF-8">
            \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\    <title>Claude Conversation - {s}</title>
            \\    <style>
            \\        body {{
            \\            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            \\            max-width: 800px;
            \\            margin: 0 auto;
            \\            padding: 20px;
            \\            background: #f5f5f5;
            \\        }}
            \\        .header {{
            \\            background: white;
            \\            padding: 20px;
            \\            border-radius: 8px;
            \\            margin-bottom: 20px;
            \\            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            \\        }}
            \\        .message {{
            \\            background: white;
            \\            padding: 15px 20px;
            \\            margin-bottom: 10px;
            \\            border-radius: 8px;
            \\            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            \\        }}
            \\        .user {{ border-left: 4px solid #007bff; }}
            \\        .assistant {{ border-left: 4px solid #28a745; }}
            \\        .role {{
            \\            font-weight: bold;
            \\            margin-bottom: 10px;
            \\            display: flex;
            \\            align-items: center;
            \\        }}
            \\        .content {{
            \\            white-space: pre-wrap;
            \\            line-height: 1.5;
            \\        }}
            \\        .stats {{
            \\            display: grid;
            \\            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            \\            gap: 10px;
            \\            margin-top: 15px;
            \\        }}
            \\        .stat {{
            \\            background: #f8f9fa;
            \\            padding: 8px 12px;
            \\            border-radius: 4px;
            \\        }}
            \\    </style>
            \\</head>
            \\<body>
            \\
        , .{conversation.project_name});
        
        // Header section
        try writer.print(
            \\    <div class="header">
            \\        <h1>Claude Conversation Log</h1>
            \\        <div class="stats">
            \\            <div class="stat"><strong>Project:</strong> {s}</div>
            \\            <div class="stat"><strong>Messages:</strong> {d}</div>
            \\            <div class="stat"><strong>Characters:</strong> {d}</div>
            \\            <div class="stat"><strong>Est. Tokens:</strong> {d}</div>
            \\        </div>
            \\    </div>
            \\
        , .{ conversation.project_name, conversation.message_count, conversation.total_chars, conversation.estimated_tokens });
        
        // Messages
        for (conversation.messages) |msg| {
            const role_class = switch (msg.role) {
                .user => "user",
                .assistant => "assistant",
                .system => "system",
            };
            
            const role_emoji = switch (msg.role) {
                .user => "👤",
                .assistant => "🤖",
                .system => "⚙️",
            };
            
            const role_name = switch (msg.role) {
                .user => "User",
                .assistant => "Claude",
                .system => "System",
            };
            
            try writer.print(
                \\    <div class="message {s}">
                \\        <div class="role">{s} {s}</div>
                \\        <div class="content">{s}</div>
                \\    </div>
                \\
            , .{ role_class, role_emoji, role_name, msg.content });
        }
        
        // HTML footer
        try writer.print(
            \\</body>
            \\</html>
            \\
        , .{});
    }
    
    pub fn generateFilename(self: *ExportManager, conversation: *const Conversation, format: ExportFormat) ![]const u8 {
        const extension = switch (format) {
            .markdown => "md",
            .json => "json",
            .html => "html",
            .detailed_markdown => "detailed.md",
        };
        
        // Extract session ID (first 8 chars of filename)
        var session_id: [8]u8 = [_]u8{0} ** 8;
        const basename = std.fs.path.basename(conversation.file_path);
        const id_len = @min(8, basename.len);
        @memcpy(session_id[0..id_len], basename[0..id_len]);
        if (id_len < 8) {
            @memset(session_id[id_len..], '0');
        }
        
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}/claude-conversation-{d}-{s}.{s}",
            .{ self.output_dir, conversation.created_at, session_id, extension }
        );
    }
};

// ================================================================================
// SECTION 5: Compression Algorithms for Search Engine
// ================================================================================

// Gorilla compression - Facebook's time-series compression algorithm
// Excellent for timestamps, positions, and floating-point scores
// GorillaCompressor removed - using SQLite FTS5 only

// Compression structures removed - using SQLite FTS5 only
// Simple8b, VByteEncoder, SimpleCompressor removed

// ================================================================================
// SECTION 6: Bytecode VM for Query Evaluation
// ================================================================================

// QueryOpcode removed - using SQLite FTS5 only

// QueryVM and related compression structures removed - using SQLite FTS5 only
    
// QueryVM execution methods, VByteStreamReader, and QueryCompiler removed - using SQLite FTS5 only
// QueryCompiler methods removed - using SQLite FTS5 only

// ================================================================================
// SECTION 7: Ring Buffer and SIMD Operations
// ================================================================================

// RingBuffer removed - using SQLite FTS5 only

// CacheAwareBufferChain removed - using SQLite FTS5 only

// SIMDSearch removed - using SQLite FTS5 only

// ================================================================================
// SECTION 8: Compressed Search Engine with Integrated Optimizations
// ================================================================================

// ConversationsSoA struct removed - using SQLite FTS5 only

// CompressedPostingList struct removed - using SQLite FTS5 only

// PostingList struct removed - using SQLite FTS5 only

// InvertedIndex struct removed - using SQLite FTS5 only

// SearchResult struct removed - using DatabaseSearchResult only

// ================================================================================
// SECTION 6: Terminal UI and Interactive Search
// ================================================================================


// ================================================================================
// SECTION 7: CLI Interface and Main Function
// ================================================================================

const CLI = struct {
    allocator: std.mem.Allocator,
    fs: FileSystem,
    db: *Database,
    importer: *IncrementalImporter,
    
    pub fn run(allocator: std.mem.Allocator) !void {
        // Allocate CLI on heap to avoid stack overflow with optimizations
        const cli_ptr = try allocator.create(CLI);
        defer allocator.destroy(cli_ptr);
        
        const fs = try FileSystem.init(allocator);
        
        // Initialize database
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch ".";
        defer if (!std.mem.eql(u8, home, ".")) allocator.free(home);
        const db_path = try std.fmt.allocPrint(allocator, "{s}/.claude/extractor.db", .{home});
        defer allocator.free(db_path);
        
        var db = try Database.init(allocator, db_path);
        defer db.deinit();
        
        var importer = try IncrementalImporter.init(allocator, &db);
        defer importer.deinit();
        
        cli_ptr.* = CLI{
            .allocator = allocator,
            .fs = fs,
            .db = &db,
            .importer = &importer,
        };
        defer cli_ptr.fs.deinit();
        
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        
        if (args.len == 1) {
            try cli_ptr.showHelp();
            return;
        }
        
        // Parse command line arguments
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                try cli_ptr.showHelp();
                return;
            } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
                std.debug.print("{s}\n", .{VERSION});
                return;
            } else if (std.mem.eql(u8, arg, "--list") or std.mem.eql(u8, arg, "-l")) {
                try cli_ptr.listSessions(null);
                return;
            } else if (std.mem.eql(u8, arg, "--extract") or std.mem.eql(u8, arg, "-e")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --extract requires a session number\n", .{});
                    return;
                }
                i += 1;
                const session_num = std.fmt.parseInt(usize, args[i], 10) catch {
                    std.debug.print("Error: Invalid session number: {s}\n", .{args[i]});
                    return;
                };
                try cli_ptr.extractSession(session_num - 1, .markdown);
                return;
            } else if (std.mem.eql(u8, arg, "--extract-all")) {
                try cli_ptr.extractAllSessions(.markdown);
                return;
            } else if (std.mem.eql(u8, arg, "--search") or std.mem.eql(u8, arg, "-s")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --search requires a query\n", .{});
                    return;
                }
                i += 1;
                try cli_ptr.searchConversations(args[i]);
                return;
            } else if (std.mem.eql(u8, arg, "--benchmark") or std.mem.eql(u8, arg, "-b")) {
                std.debug.print("Benchmarks disabled - compression structures removed\n", .{});
                return;
            } else if (std.mem.eql(u8, arg, "--format")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --format requires a format type\n", .{});
                    return;
                }
                i += 1;
                const format = std.meta.stringToEnum(ExportFormat, args[i]) orelse {
                    std.debug.print("Error: Unknown format: {s}\n", .{args[i]});
                    return;
                };
                _ = format; // Store for next extract command
            } else {
                std.debug.print("Error: Unknown argument: {s}\n", .{arg});
                try cli_ptr.showHelp();
                return;
            }
        }
    }
    
    fn showHelp(_: *CLI) !void {
        std.debug.print(
            \\🚀 Claude Conversation Extractor & Search Engine v{s} (Zig)
            \\
            \\Usage: extractor [OPTIONS]
            \\
            \\Options:
            \\  -h, --help          Show this help message
            \\  -l, --list          List all available conversations
            \\  -e, --extract N     Extract conversation N to markdown
            \\  --extract-all       Extract all conversations
            \\  --format FORMAT     Set export format (markdown, json, html)
            \\  -s, --search QUERY  Search conversations for QUERY
            \\
            \\Examples:
            \\  extractor --search "python async"   # Search for conversations
            \\  extractor --list                    # List all conversations
            \\  extractor --extract 1                # Extract first conversation
            \\  extractor --extract-all --format json  # Export all as JSON
            \\
        , .{VERSION});
    }
    
    fn listSessions(self: *CLI, project: ?[]const u8) !void {
        const sessions = try self.fs.findSessions(project);
        defer {
            for (sessions) |session| {
                self.allocator.free(session);
            }
            self.allocator.free(sessions);
        }
        
        std.debug.print("\n📊 Found {d} conversation files\n\n", .{sessions.len});
        
        for (sessions, 0..) |session, i| {
            const basename = std.fs.path.basename(session);
            const stat = std.fs.cwd().statFile(session) catch continue;
            
            std.debug.print("  {d:2}. {s:<40} ({d} KB)\n", .{
                i + 1,
                if (basename.len > 40) basename[0..40] else basename,
                @divFloor(stat.size, 1024),
            });
            
            if (i >= 19) {
                if (sessions.len > 20) {
                    std.debug.print("  ... and {d} more\n", .{sessions.len - 20});
                }
                break;
            }
        }
    }
    
    fn extractSession(self: *CLI, index: usize, format: ExportFormat) !void {
        const sessions = try self.fs.findSessions(null);
        defer {
            for (sessions) |session| {
                self.allocator.free(session);
            }
            self.allocator.free(sessions);
        }
        
        if (index >= sessions.len) {
            std.debug.print("Error: Session {d} not found (only {d} sessions available)\n", .{ index + 1, sessions.len });
            return;
        }
        
        std.debug.print("📄 Extracting session {d}...\n", .{index + 1});
        
        const start_time = std.time.nanoTimestamp();
        
        // Get conversation ID from filename
        const file_path = sessions[index];
        const file_basename = std.fs.path.basename(file_path);
        const conv_id = if (std.mem.endsWith(u8, file_basename, ".jsonl"))
            file_basename[0..file_basename.len - 6]
        else if (std.mem.endsWith(u8, file_basename, ".jso"))
            file_basename[0..file_basename.len - 4]  // Remove .jso extension
        else
            file_basename;
        
        std.debug.print("🔍 Looking for conversation ID: {s}\n", .{conv_id});
        
        // Get all messages from database (limit to a reasonable number)
        const db_start = std.time.nanoTimestamp();
        const messages = try self.importer.getMessagesWithTailOverlay(conv_id, 999999, 10000);
        const db_end = std.time.nanoTimestamp();
        defer {
            for (messages) |msg| {
                self.allocator.free(msg.content);
            }
            self.allocator.free(messages);
        }
        
        if (messages.len == 0) {
            std.debug.print("❌ No messages found for session {d}. Database may not be populated.\n", .{index + 1});
            return;
        }
        
        // Create conversation from database messages
        const conversation = Conversation{
            .id = try self.allocator.dupe(u8, conv_id),
            .project_name = try self.allocator.dupe(u8, "claude-project"),
            .messages = messages,
            .created_at = if (messages.len > 0 and messages[0].timestamp != null) messages[0].timestamp.? else std.time.timestamp(),
            .updated_at = if (messages.len > 0 and messages[messages.len - 1].timestamp != null) messages[messages.len - 1].timestamp.? else std.time.timestamp(),
            .file_path = try self.allocator.dupe(u8, file_path),
            .message_count = messages.len,
            .user_message_count = blk: {
                var count: usize = 0;
                for (messages) |msg| {
                    if (msg.role == .user) count += 1;
                }
                break :blk count;
            },
            .assistant_message_count = blk: {
                var count: usize = 0;
                for (messages) |msg| {
                    if (msg.role == .assistant) count += 1;
                }
                break :blk count;
            },
            .total_chars = blk: {
                var count: usize = 0;
                for (messages) |msg| {
                    count += msg.content.len;
                }
                break :blk count;
            },
            .estimated_tokens = blk: {
                // Rough estimate: 1 token per 4 characters
                const total_chars = blk2: {
                    var count: usize = 0;
                    for (messages) |msg| {
                        count += msg.content.len;
                    }
                    break :blk2 count;
                };
                break :blk @divFloor(total_chars, 4);
            },
        };
        defer {
            self.allocator.free(conversation.id);
            self.allocator.free(conversation.project_name);
            self.allocator.free(conversation.file_path);
            // Don't free messages array itself as it's moved to conversation
        }
        
        var export_manager = ExportManager{
            .allocator = self.allocator,
            .output_dir = self.fs.output_dir,
        };
        
        const output_path = try export_manager.generateFilename(&conversation, format);
        defer self.allocator.free(output_path);
        
        const export_start = std.time.nanoTimestamp();
        switch (format) {
            .markdown, .detailed_markdown => try export_manager.exportMarkdown(&conversation, output_path),
            .json => try export_manager.exportJSON(&conversation, output_path),
            .html => try export_manager.exportHTML(&conversation, output_path),
        }
        const export_end = std.time.nanoTimestamp();
        
        const total_time = export_end - start_time;
        const db_time = db_end - db_start;
        const export_time = export_end - export_start;
        
        std.debug.print("✅ Exported {d} messages to: {s}\n", .{ messages.len, output_path });
        std.debug.print("⚡ Performance: DB query: {d:.2}ms, Export: {d:.2}ms, Total: {d:.2}ms\n", .{
            @as(f64, @floatFromInt(db_time)) / 1_000_000.0,
            @as(f64, @floatFromInt(export_time)) / 1_000_000.0,
            @as(f64, @floatFromInt(total_time)) / 1_000_000.0,
        });
    }
    
    fn extractAllSessions(self: *CLI, format: ExportFormat) !void {
        const sessions = try self.fs.findSessions(null);
        defer {
            for (sessions) |session| {
                self.allocator.free(session);
            }
            self.allocator.free(sessions);
        }
        
        std.debug.print("📄 Extracting {d} sessions...\n", .{sessions.len});
        
        var success_count: usize = 0;
        var parser = try JSONLParser.init(self.allocator);
        defer parser.deinit();
        
        for (sessions, 0..) |session, i| {
            std.debug.print("  [{d}/{d}] Processing {s}...", .{ i + 1, sessions.len, std.fs.path.basename(session) });
            
            if (parser.parseFile(session)) |conversation| {
                defer self.freeConversation(&conversation);
                
                var export_manager = ExportManager{
                    .allocator = self.allocator,
                    .output_dir = self.fs.output_dir,
                };
                
                const output_path = try export_manager.generateFilename(&conversation, format);
                defer self.allocator.free(output_path);
                
                switch (format) {
                    .markdown, .detailed_markdown => try export_manager.exportMarkdown(&conversation, output_path),
                    .json => try export_manager.exportJSON(&conversation, output_path),
                    .html => try export_manager.exportHTML(&conversation, output_path),
                }
                
                std.debug.print(" ✅\n", .{});
                success_count += 1;
            } else |err| {
                std.debug.print(" ❌ ({any})\n", .{err});
            }
        }
        
        std.debug.print("\n✅ Successfully exported {d}/{d} conversations\n", .{ success_count, sessions.len });
    }
    
    fn searchConversations(self: *CLI, query: []const u8) !void {
        std.debug.print("🔍 Searching for: {s}\n", .{query});
        
        const start_time = std.time.nanoTimestamp();
        
        // Use fast database FTS5 search
        const results = self.db.search(query) catch |err| {
            std.debug.print("❌ Search failed: {any}\n", .{err});
            return;
        };
        defer self.db.freeSearchResults(results);
        
        const search_time = std.time.nanoTimestamp() - start_time;
        
        if (results.len == 0) {
            std.debug.print("No conversations found matching '{s}'.\n", .{query});
            return;
        }
        
        std.debug.print("\n📊 Found {d} matching conversations:\n", .{results.len});
        std.debug.print("⚡ Search completed in {d:.2}ms\n\n", .{@as(f32, @floatFromInt(search_time)) / 1_000_000});
        
        for (results[0..@min(10, results.len)], 0..) |result, i| {
            std.debug.print("{d}. Conversation {s} (score: {d:.2})\n", .{
                i + 1,
                result.conversation_id[0..8], // Show first 8 chars of conversation ID
                result.score,
            });
            std.debug.print("   Messages: {d}, Characters: {d}\n", .{
                result.message_count,
                result.total_chars,
            });
            
            // Clean up HTML markup from snippet for console display
            var clean_snippet = std.ArrayList(u8).init(self.allocator);
            defer clean_snippet.deinit();
            
            var i_char: usize = 0;
            while (i_char < result.snippet.len) {
                if (i_char + 6 < result.snippet.len and std.mem.eql(u8, result.snippet[i_char..i_char+6], "<mark>")) {
                    i_char += 6; // Skip <mark>
                } else if (i_char + 7 < result.snippet.len and std.mem.eql(u8, result.snippet[i_char..i_char+7], "</mark>")) {
                    i_char += 7; // Skip </mark>
                } else {
                    try clean_snippet.append(result.snippet[i_char]);
                    i_char += 1;
                }
            }
            
            const display_snippet = if (clean_snippet.items.len > 200) 
                clean_snippet.items[0..200] 
            else 
                clean_snippet.items;
            
            std.debug.print("   Snippet: {s}...\n\n", .{display_snippet});
        }
        
        if (results.len > 10) {
            std.debug.print("... and {d} more results\n", .{results.len - 10});
        }
    }
    
    fn freeConversation(self: *CLI, conversation: *const Conversation) void {
        self.allocator.free(conversation.id);
        self.allocator.free(conversation.project_name);
        self.allocator.free(conversation.file_path);
        for (conversation.messages) |msg| {
            self.allocator.free(msg.content);
            if (msg.tool_calls) |calls| {
                for (calls) |call| {
                    self.allocator.free(call.tool_name);
                    self.allocator.free(call.parameters);
                    if (call.result) |r| self.allocator.free(r);
                }
                self.allocator.free(calls);
            }
            if (msg.tool_responses) |responses| {
                for (responses) |resp| {
                    self.allocator.free(resp.tool_name);
                    self.allocator.free(resp.output);
                    if (resp.err) |e| self.allocator.free(e);
                }
                self.allocator.free(responses);
            }
        }
        self.allocator.free(conversation.messages);
    }
};

// ================================================================================
// SECTION 6: NDJSON Protocol Mode for Flutter Integration
// ================================================================================

const ProtocolVersion = 1;
const CoreVersion = "2.1.0";

fn runProtocolMode(allocator: std.mem.Allocator) !void {
    // Send hello message
    try sendHello();
    
    // Initialize context
    var fs = try FileSystem.init(allocator);
    defer fs.deinit();
    
    // Initialize database (new backend)
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch ".";
    defer if (!std.mem.eql(u8, home, ".")) allocator.free(home);
    const db_path = try std.fmt.allocPrint(allocator, "{s}/.claude/extractor.db", .{home});
    defer allocator.free(db_path);
    
    var db = try Database.init(allocator, db_path);
    defer db.deinit();
    
    // Initialize incremental importer
    var importer = try IncrementalImporter.init(allocator, &db);
    defer importer.deinit();
    
    // InvertedIndex removed - using SQLite FTS5 only
    
    var cancel_flag = std.atomic.Value(bool).init(false);
    
    // Main protocol loop
    const stdin = std.io.getStdIn().reader();
    var line_buffer = std.ArrayList(u8).init(allocator);
    defer line_buffer.deinit();
    
    while (true) {
        line_buffer.clearRetainingCapacity();
        
        // Read line from stdin
        stdin.streamUntilDelimiter(line_buffer.writer(), '\n', null) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        
        if (line_buffer.items.len == 0) continue;
        
        // Parse request robustly
        const req_val = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            line_buffer.items,
            .{ .ignore_unknown_fields = true }
        ) catch |err| {
            std.debug.print("Failed to parse request: {any}\n", .{err});
            continue;
        };
        defer req_val.deinit();
        
        const obj = req_val.value.object;
        
        // id: accept "123" or 123
        var id_buf: [32]u8 = undefined;
        const id_field = obj.get("id") orelse {
            try sendError("?", "BAD_REQUEST", "missing id");
            continue;
        };
        const id: []const u8 = switch (id_field) {
            .string => |s| s,
            .integer => |i| std.fmt.bufPrint(&id_buf, "{d}", .{i}) catch "0",
            .float => |f| std.fmt.bufPrint(&id_buf, "{d}", .{@as(i64, @intFromFloat(f))}) catch "0",
            else => "0",
        };
        
        // method + aliases
        const method_field = obj.get("method") orelse {
            try sendError(id, "BAD_REQUEST", "missing method");
            continue;
        };
        if (method_field != .string) {
            try sendError(id, "BAD_REQUEST", "method must be string");
            continue;
        }
        const method_raw = method_field.string;
        const method = if (std.mem.eql(u8, method_raw, "list")) 
            "list_sessions" 
        else 
            method_raw;
        
        // params (optional)
        const params = obj.get("params");
        
        // Route to handler
        if (std.mem.eql(u8, method, "build_index")) {
            protocolBuildIndex(allocator, &fs, &importer, id, params, &cancel_flag) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "list_sessions")) {
            protocolListSessions(allocator, &fs, id, params) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "search")) {
            protocolSearch(allocator, &db, &fs, id, params) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "extract")) {
            protocolExtract(allocator, &fs, &importer, id, params) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "cancel")) {
            cancel_flag.store(true, .release);
            try sendResult(id, .{ .string = "cancelled" });
        } else {
            try sendError(id, "UNKNOWN_METHOD", "Unknown method");
        }
    }
}

fn sendHello() !void {
    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const w = bw.writer();
    try w.print(
        \\{{"type":"hello","core_version":"{s}","protocol":{d},"capabilities":["index","search","extract","list"]}}
    ++ "\n", .{ CoreVersion, ProtocolVersion });
    try bw.flush();
}

fn sendEvent(id: []const u8, stage: []const u8, progress: f32) !void {
    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const w = bw.writer();
    try w.print(
        \\{{"id":"{s}","type":"event","stage":"{s}","progress":{d:.2}}}
    ++ "\n", .{ id, stage, progress });
    try bw.flush();
}

fn sendResult(id: []const u8, data: std.json.Value) !void {
    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const w = bw.writer();
    try w.print(
        \\{{"id":"{s}","type":"result","data":
    , .{id});
    try std.json.stringify(data, .{}, w);
    try w.print("}}\n", .{});
    try bw.flush();
}

fn sendError(id: []const u8, code: []const u8, message: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout);
    const w = bw.writer();
    try w.print(
        \\{{"id":"{s}","type":"error","error":{{"code":"{s}","message":"{s}"}}}}
    ++ "\n", .{ id, code, message });
    try bw.flush();
}

fn protocolBuildIndex(
    allocator: std.mem.Allocator,
    fs: *FileSystem,
    importer: *IncrementalImporter,
    id: []const u8,
    params: ?std.json.Value,
    cancel_flag: *std.atomic.Value(bool),
) !void {
    cancel_flag.store(false, .release);
    
    const root = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("root")) |r| {
                if (r == .string) break :blk r.string;
            }
        }
        break :blk null;
    } else null;
    
    try sendEvent(id, "scan", 0.0);
    
    const sessions = try fs.findSessions(root);
    defer {
        for (sessions) |session| allocator.free(session);
        allocator.free(sessions);
    }
    
    if (cancel_flag.load(.acquire)) {
        try sendError(id, "CANCELLED", "Operation cancelled");
        return;
    }
    
    try sendEvent(id, "import", 0.2);
    
    // Import all sessions into SQLite database using incremental importer
    for (sessions, 0..) |session, i| {
        if (cancel_flag.load(.acquire)) {
            try sendError(id, "CANCELLED", "Operation cancelled");
            return;
        }
        
        const progress = 0.2 + (0.8 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sessions.len)));
        try sendEvent(id, "import", progress);
        
        // Import file into SQLite database with FTS5 support
        try importer.importFile(session);
    }
    
    try sendEvent(id, "complete", 1.0);
    
    var result = std.StringArrayHashMap(std.json.Value).init(allocator);
    defer result.deinit();
    try result.put("status", .{ .string = "ok" });
    try result.put("conversations", .{ .integer = @intCast(sessions.len) });
    try sendResult(id, .{ .object = result });
}

fn protocolListSessions(
    allocator: std.mem.Allocator,
    fs: *FileSystem,
    id: []const u8,
    params: ?std.json.Value,
) !void {
    // Use arena for all temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    
    const root = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("root")) |r| {
                if (r == .string) break :blk r.string;
            }
        }
        break :blk null;
    } else null;
    
    const sessions = try fs.findSessions(root);
    defer {
        for (sessions) |session| allocator.free(session);
        allocator.free(sessions);
    }
    
    var sessions_array = std.ArrayList(std.json.Value).init(arena_alloc);
    
    for (sessions, 0..) |session, i| {
        var obj = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
        
        const id_str = try std.fmt.allocPrint(arena_alloc, "session_{d}", .{i});
        try obj.put("id", .{ .string = id_str });
        try obj.put("path", .{ .string = session });
        try obj.put("name", .{ .string = std.fs.path.basename(session) });
        
        if (std.fs.cwd().statFile(session)) |stat| {
            try obj.put("size", .{ .integer = @intCast(stat.size) });
            try obj.put("mtime", .{ .integer = @intCast(stat.mtime) });
        } else |_| {
            try obj.put("size", .{ .integer = 0 });
            try obj.put("mtime", .{ .integer = 0 });
        }
        
        try sessions_array.append(.{ .object = obj });
    }
    
    try sendResult(id, .{ .array = sessions_array });
}

fn protocolSearch(
    allocator: std.mem.Allocator,
    db: *Database,
    fs: *FileSystem,
    id: []const u8,
    params: ?std.json.Value,
) !void {
    // Use arena for all temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    
    const query = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("q")) |q| {
                if (q == .string) break :blk q.string;
            }
            if (p.object.get("query")) |q2| {  // alias
                if (q2 == .string) break :blk q2.string;
            }
        }
        break :blk null;
    } else null;
    
    if (query == null) {
        try sendError(id, "INVALID_PARAMS", "Missing query");
        return;
    }
    
    // Get the list of sessions from filesystem to create conversation_id -> session_id mapping
    const sessions = fs.findSessions(null) catch {
        // Return empty results on error
        var empty_response = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
        const empty_array = std.ArrayList(std.json.Value).init(arena_alloc);
        try empty_response.put("results", .{ .array = empty_array });
        try sendResult(id, .{ .object = empty_response });
        return;
    };
    defer {
        for (sessions) |session| allocator.free(session);
        allocator.free(sessions);
    }
    
    // Create mapping from conversation_id to session_id format
    var conversation_to_session = std.StringArrayHashMap([]const u8).init(arena_alloc);
    for (sessions, 0..) |session, i| {
        const basename = std.fs.path.basename(session);
        // Remove .jsonl extension to get conversation_id
        const conversation_id = if (std.mem.endsWith(u8, basename, ".jsonl"))
            basename[0..basename.len - 6]
        else
            basename;
        
        const session_id = try std.fmt.allocPrint(arena_alloc, "session_{d}", .{i});
        try conversation_to_session.put(conversation_id, session_id);
    }
    
    // Use SQLite FTS5 search directly
    const db_results = db.search(query.?) catch {
        // Return empty results on error
        var empty_response = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
        const empty_array = std.ArrayList(std.json.Value).init(arena_alloc);
        try empty_response.put("results", .{ .array = empty_array });
        try sendResult(id, .{ .object = empty_response });
        return;
    };
    
    defer {
        for (db_results) |r| allocator.free(r.snippet);
        allocator.free(db_results);
    }
    
    // Convert database results to protocol format
    var results_array = std.ArrayList(std.json.Value).init(arena_alloc);
    
    for (db_results) |r| {
        // Map conversation_id to session_id format
        const session_id = conversation_to_session.get(r.conversation_id) orelse {
            // Skip results that don't have a corresponding session file
            continue;
        };
        
        var obj = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
        try obj.put("session_id", .{ .string = session_id });
        try obj.put("session_name", .{ .string = r.conversation_id });
        try obj.put("score", .{ .float = r.score });
        try obj.put("snippet", .{ .string = r.snippet });
        try obj.put("position", .{ .integer = @as(i64, @intCast(r.position)) });
        try obj.put("match_count", .{ .integer = 1 });
        try results_array.append(.{ .object = obj });
    }
    
    // Results are already sorted by SQLite FTS5 ranking
    
    // Wrap in a results object as expected by Flutter
    var response = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
    try response.put("results", .{ .array = results_array });
    try sendResult(id, .{ .object = response });
}

fn protocolExtract(
    allocator: std.mem.Allocator,
    fs: *FileSystem,
    importer: *IncrementalImporter,
    id: []const u8,
    params: ?std.json.Value,
) !void {
    const session_id = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("session_id")) |s| {
                if (s == .string) break :blk s.string;
            }
        }
        break :blk null;
    } else null;
    
    if (session_id == null) {
        try sendError(id, "INVALID_PARAMS", "Missing session_id");
        return;
    }
    
    const format_str = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("format")) |f| {
                if (f == .string) break :blk f.string;
            }
        }
        break :blk "markdown";
    } else "markdown";
    
    // Parse session_N to get index
    if (!std.mem.startsWith(u8, session_id.?, "session_")) {
        try sendError(id, "INVALID_SESSION", "Invalid session ID");
        return;
    }
    
    const index = std.fmt.parseInt(usize, session_id.?[8..], 10) catch {
        try sendError(id, "INVALID_SESSION", "Invalid session number");
        return;
    };
    
    const sessions = try fs.findSessions(null);
    defer {
        for (sessions) |session| allocator.free(session);
        allocator.free(sessions);
    }
    
    if (index >= sessions.len) {
        try sendError(id, "SESSION_NOT_FOUND", "Session not found");
        return;
    }
    
    // Import the file if not already in database (ensures it's indexed)
    try importer.importFile(sessions[index]);
    
    // Extract conversation ID from the file path, removing the .jsonl extension
    const file_basename = std.fs.path.basename(sessions[index]);
    const conv_id = if (std.mem.endsWith(u8, file_basename, ".jsonl"))
        file_basename[0..file_basename.len - 6]
    else if (std.mem.endsWith(u8, file_basename, ".jso"))
        file_basename[0..file_basename.len - 4]  // Remove .jso extension
    else
        file_basename;
    
    // Check for pagination parameters
    const limit = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("limit")) |l| {
                if (l == .integer) break :blk @as(usize, @intCast(l.integer));
            }
        }
        break :blk 0; // 0 means all messages
    } else 0;
    
    const offset = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("offset")) |o| {
                if (o == .integer) break :blk @as(usize, @intCast(o.integer));
            }
        }
        break :blk 0;
    } else 0;
    
    // Check if this is a view request (json format without export flag) or export request
    const is_export = if (params) |p| blk: {
        if (p == .object) {
            if (p.object.get("export")) |e| {
                if (e == .bool) break :blk e.bool;
            }
        }
        break :blk false;
    } else false;
    
    if (std.mem.eql(u8, format_str, "json") and !is_export) {
        // VIEW mode: Use fast database query with tail overlay
        var result = std.StringArrayHashMap(std.json.Value).init(allocator);
        defer result.deinit();
        
        // Get messages using the new fast importer with tail overlay
        const before_position: i64 = if (offset > 0) @as(i64, 999999) else @as(i64, 999999); // High number for newest
        const messages = try importer.getMessagesWithTailOverlay(
            conv_id,
            before_position,
            if (limit > 0) limit else 50
        );
        defer {
            for (messages) |msg| {
                allocator.free(msg.content);
            }
            allocator.free(messages);
        }
        
        // Add conversation metadata
        try result.put("id", .{ .string = conv_id });
        try result.put("project_name", .{ .string = "claude-project" });
        try result.put("created_at", .{ .integer = std.time.timestamp() });
        try result.put("updated_at", .{ .integer = std.time.timestamp() });
        
        // Add messages array (already fetched with pagination applied)
        var messages_array = std.ArrayList(std.json.Value).init(allocator);
        for (messages) |msg| {
            var msg_obj = std.StringArrayHashMap(std.json.Value).init(allocator);
            try msg_obj.put("role", .{ .string = @tagName(msg.role) });
            try msg_obj.put("content", .{ .string = msg.content });
            if (msg.timestamp) |ts| {
                try msg_obj.put("timestamp", .{ .integer = @intCast(ts) });
            } else {
                try msg_obj.put("timestamp", .{ .null = {} });
            }
            try messages_array.append(.{ .object = msg_obj });
        }
        try result.put("messages", .{ .array = messages_array });
        try result.put("total_messages", .{ .integer = @intCast(messages.len) });
        try result.put("has_more", .{ .bool = messages.len == limit });
        
        try sendResult(id, .{ .object = result });
    } else {
        // EXPORT mode: For now, parse the file for export (will optimize later)
        var parser = try StreamingJSONLParser.init(allocator);
        defer parser.deinit();
        
        const conversation = try parser.parseFile(sessions[index]);
        defer {
            allocator.free(conversation.id);
            allocator.free(conversation.project_name);
            allocator.free(conversation.file_path);
            for (conversation.messages) |msg| {
                allocator.free(msg.content);
            }
            allocator.free(conversation.messages);
        }
        
        var export_mgr = ExportManager{
            .allocator = allocator,
            .output_dir = fs.output_dir,
        };
        
        const format = std.meta.stringToEnum(ExportFormat, format_str) orelse .markdown;
        const output_path = try export_mgr.generateFilename(&conversation, format);
        defer allocator.free(output_path);
        
        switch (format) {
            .markdown, .detailed_markdown => try export_mgr.exportMarkdown(&conversation, output_path),
            .json => try export_mgr.exportJSON(&conversation, output_path),
            .html => try export_mgr.exportHTML(&conversation, output_path),
        }
        
        var result = std.StringArrayHashMap(std.json.Value).init(allocator);
        defer result.deinit();
        try result.put("path", .{ .string = output_path });
        try result.put("format", .{ .string = format_str });
        try sendResult(id, .{ .object = result });
    }
}

// ================================================================================
// SECTION 7: Main Function
// ================================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Check if we have command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    // Check for explicit protocol mode argument
    var protocol_mode = false;
    if (args.len > 1) {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--protocol") or std.mem.eql(u8, arg, "protocol")) {
                protocol_mode = true;
                break;
            }
        }
    }
    
    if (protocol_mode) {
        // Explicit protocol mode requested
        try runProtocolMode(allocator);
    } else if (args.len > 1) {
        // CLI mode - user provided arguments (but not protocol mode)
        try CLI.run(allocator);
    } else if (std.io.getStdIn().isTty()) {
        // CLI mode - stdin is a terminal (interactive)
        try CLI.run(allocator);
    } else {
        // Protocol mode - stdin is a pipe (Flutter calling us)
        try runProtocolMode(allocator);
    }
}

// ================================================================================
// SECTION 7: Benchmarks and Performance Tests
// ================================================================================

// Benchmarks disabled - compression structures removed
// Benchmarks disabled - compression structures removed
// fn runBenchmarks() !void {
//     std.debug.print("Benchmarks disabled\n", .{});
// }

// ================================================================================
// SECTION 8: Tests
// ================================================================================

test "FileSystem initialization" {
    const allocator = std.testing.allocator;
    var fs = try FileSystem.init(allocator);
    defer fs.deinit();
    
    try std.testing.expect(fs.claude_dir.len > 0);
    try std.testing.expect(fs.output_dir.len > 0);
}

test "JSONL parsing" {
    const allocator = std.testing.allocator;
    const sample = 
        \\{"type": "user", "message": {"role": "user", "content": "Hello, Claude!"}}
        \\{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Hello! How can I help you today?"}]}}
    ;
    
    var parser = try JSONLParser.init(allocator);
    defer parser.deinit();
    
    const conversation = try parser.parseContent(sample, "/test/path.jsonl");
    defer {
        // Clean up
        allocator.free(conversation.id);
        allocator.free(conversation.project_name);
        allocator.free(conversation.file_path);
        for (conversation.messages) |msg| {
            allocator.free(msg.content);
        }
        allocator.free(conversation.messages);
    }
    
    try std.testing.expect(conversation.message_count == 2);
    try std.testing.expect(conversation.user_message_count == 1);
    try std.testing.expect(conversation.assistant_message_count == 1);
}