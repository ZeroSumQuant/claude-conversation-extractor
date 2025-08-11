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
        
        // Update block index incrementally
        try block_idx.appendIncremental(mapped_file);
        
        // Get source file record
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        const stat = try file.stat();
        const source_file_id = try self.db.getOrCreateSourceFile(path, stat);
        
        // Begin transaction for batch inserts
        try self.db.beginTransaction();
        defer self.db.rollback() catch {};
        
        // Import new lines since last_byte
        var line_no = block_idx.header.total_lines;
        var iter = mapped_file.findLines(block_idx.header.last_byte, mapped_file.size);
        
        var batch_count: usize = 0;
        const batch_size = 5000;
        
        while (iter.next()) |line| {
            // Parse JSON line
            const parsed = std.json.parseFromSlice(
                std.json.Value,
                self.allocator,
                line.content,
                .{ .allocate = .alloc_always }
            ) catch continue;
            defer parsed.deinit();
            
            // Extract conversation info
            const conv_id = self.extractConversationId(parsed.value, path) catch continue;
            const role = self.extractRole(parsed.value) catch continue;
            const content = self.extractContent(parsed.value) catch continue;
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
        
        // Final commit
        try self.db.commit();
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
        const role = value.object.get("type") orelse return error.MissingField;
        if (role != .string) return error.InvalidType;
        return role.string;
    }
    
    fn extractContent(self: *Self, value: std.json.Value) ![]const u8 {
        _ = self;
        if (value != .object) return error.InvalidJson;
        const content = value.object.get("content") orelse return error.MissingField;
        
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
const GorillaCompressor = struct {
    // Compress timestamps using XOR-based delta encoding
    pub fn compressTimestamps(allocator: std.mem.Allocator, timestamps: []const i64) ![]u8 {
        if (timestamps.len == 0) return &[_]u8{};
        
        var bits = std.ArrayList(u1).init(allocator);
        defer bits.deinit();
        
        // Store first timestamp as-is (64 bits)
        for (0..64) |i| {
            try bits.append(@intCast((timestamps[0] >> @intCast(63 - i)) & 1));
        }
        
        var prev_delta: i64 = 0;
        var prev_timestamp = timestamps[0];
        
        for (timestamps[1..]) |ts| {
            const delta = ts - prev_timestamp;
            const xor_delta = delta ^ prev_delta;
            
            if (xor_delta == 0) {
                // Same delta - store single '0' bit
                try bits.append(0);
            } else {
                // Different delta - use variable-length encoding
                try bits.append(1);
                
                // Find leading and trailing zeros in XOR
                const leading_zeros = @clz(xor_delta);
                const trailing_zeros = @ctz(xor_delta);
                
                if (leading_zeros >= 32 and trailing_zeros >= 32) {
                    // Can fit in center 4 bits
                    try bits.append(0);
                    try bits.append(0);
                    for (0..4) |i| {
                        try bits.append(@intCast((xor_delta >> @intCast(30 + i)) & 1));
                    }
                } else if (leading_zeros >= 20 and trailing_zeros >= 20) {
                    // Can fit in center 24 bits  
                    try bits.append(0);
                    try bits.append(1);
                    for (0..24) |i| {
                        try bits.append(@intCast((xor_delta >> @intCast(20 + i)) & 1));
                    }
                } else {
                    // Need full encoding
                    try bits.append(1);
                    try bits.append(1);
                    // Store leading zeros (6 bits)
                    for (0..6) |i| {
                        try bits.append(@intCast((leading_zeros >> @intCast(5 - i)) & 1));
                    }
                    // Store significant bits length (6 bits)
                    const sig_bits = 64 - leading_zeros - trailing_zeros;
                    for (0..6) |i| {
                        try bits.append(@intCast((sig_bits >> @intCast(5 - i)) & 1));
                    }
                    // Store significant bits
                    for (0..sig_bits) |i| {
                        try bits.append(@intCast((xor_delta >> @intCast(trailing_zeros + sig_bits - 1 - i)) & 1));
                    }
                }
            }
            
            prev_delta = delta;
            prev_timestamp = ts;
        }
        
        // Convert bits to bytes
        return bitsToBytes(allocator, bits.items);
    }
    
    // Compress floating-point values (BM25 scores)
    pub fn compressFloats(allocator: std.mem.Allocator, values: []const f32) ![]u8 {
        if (values.len == 0) return &[_]u8{};
        
        var bits = std.ArrayList(u1).init(allocator);
        defer bits.deinit();
        
        // Store first value as-is (32 bits)
        const first_bits = @as(u32, @bitCast(values[0]));
        for (0..32) |i| {
            try bits.append(@intCast((first_bits >> @intCast(31 - i)) & 1));
        }
        
        var prev_bits = first_bits;
        
        for (values[1..]) |val| {
            const curr_bits = @as(u32, @bitCast(val));
            const xor = curr_bits ^ prev_bits;
            
            if (xor == 0) {
                // Same value - single '0' bit
                try bits.append(0);
            } else {
                try bits.append(1);
                
                // Find common prefix
                const leading_zeros = @clz(xor);
                _ = @ctz(xor); // const trailing_zeros = @ctz(xor);
                
                // Encode based on pattern
                if (leading_zeros >= 16) {
                    // Most significant bits unchanged
                    try bits.append(0);
                    for (0..16) |i| {
                        try bits.append(@intCast((xor >> @intCast(i)) & 1));
                    }
                } else {
                    // Full XOR encoding
                    try bits.append(1);
                    for (0..32) |i| {
                        try bits.append(@intCast((xor >> @intCast(31 - i)) & 1));
                    }
                }
            }
            
            prev_bits = curr_bits;
        }
        
        return bitsToBytes(allocator, bits.items);
    }
    
    fn bitsToBytes(allocator: std.mem.Allocator, bits: []const u1) ![]u8 {
        const byte_count = (bits.len + 7) / 8;
        var bytes = try allocator.alloc(u8, byte_count + 4); // +4 for length header
        
        // Store bit count in first 4 bytes
        bytes[0] = @intCast(bits.len >> 24);
        bytes[1] = @intCast((bits.len >> 16) & 0xFF);
        bytes[2] = @intCast((bits.len >> 8) & 0xFF);
        bytes[3] = @intCast(bits.len & 0xFF);
        
        // Pack bits into bytes
        for (0..byte_count) |i| {
            var byte: u8 = 0;
            for (0..8) |j| {
                const bit_idx = i * 8 + j;
                if (bit_idx < bits.len) {
                    byte |= @as(u8, bits[bit_idx]) << @intCast(7 - j);
                }
            }
            bytes[4 + i] = byte;
        }
        
        return bytes;
    }
};

// Simple-8b compression for posting lists - packs multiple integers into 64-bit words
const Simple8b = struct {
    // Selector patterns: (selector_bits, num_values, bits_per_value)
    const patterns = [_]struct { u4, u6, u6 }{
        .{ 0, 60, 1 },   // 60 x 1-bit values
        .{ 1, 30, 2 },   // 30 x 2-bit values
        .{ 2, 20, 3 },   // 20 x 3-bit values
        .{ 3, 15, 4 },   // 15 x 4-bit values
        .{ 4, 12, 5 },   // 12 x 5-bit values
        .{ 5, 10, 6 },   // 10 x 6-bit values
        .{ 6, 8, 7 },    // 8 x 7-bit values
        .{ 7, 7, 8 },    // 7 x 8-bit values
        .{ 8, 6, 10 },   // 6 x 10-bit values
        .{ 9, 5, 12 },   // 5 x 12-bit values
        .{ 10, 4, 15 },  // 4 x 15-bit values
        .{ 11, 3, 20 },  // 3 x 20-bit values
        .{ 12, 2, 30 },  // 2 x 30-bit values
        .{ 13, 1, 60 },  // 1 x 60-bit value
    };
    
    pub fn compress(allocator: std.mem.Allocator, numbers: []const u32) ![]u64 {
        var result = std.ArrayList(u64).init(allocator);
        var i: usize = 0;
        
        while (i < numbers.len) {
            // Find best pattern for next batch
            var best_pattern_idx: usize = 0;
            var best_count: usize = 0;
            
            for (patterns, 0..) |pattern, p_idx| {
                var count: usize = 0;
                const max_val = (@as(u64, 1) << pattern[2]) - 1;
                
                while (count < pattern[1] and i + count < numbers.len) {
                    if (numbers[i + count] > max_val) break;
                    count += 1;
                }
                
                if (count > best_count) {
                    best_count = count;
                    best_pattern_idx = p_idx;
                }
            }
            
            if (best_count == 0) {
                // Number too large, store as-is with special selector
                var word: u64 = 14; // Selector for uncompressed
                word = (word << 60) | @as(u64, numbers[i]);
                try result.append(word);
                i += 1;
            } else {
                // Pack using best pattern
                const pattern = patterns[best_pattern_idx];
                var word: u64 = pattern[0];
                word <<= 60;
                
                for (0..best_count) |j| {
                    const shift = @as(u6, @intCast((pattern[1] - j - 1))) * pattern[2];
                    word |= @as(u64, numbers[i + j]) << shift;
                }
                
                try result.append(word);
                i += best_count;
            }
        }
        
        return result.toOwnedSlice();
    }
};

// Variable Byte (VByte) encoding for compressed posting lists
const VByteEncoder = struct {
    pub fn encode(allocator: std.mem.Allocator, numbers: []const u32) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        
        for (numbers) |num| {
            var n = num;
            while (n >= 128) {
                try result.append(@intCast((n & 0x7F) | 0x80)); // MSB=1 for continuation
                n >>= 7;
            }
            try result.append(@intCast(n & 0x7F)); // MSB=0 for last byte
        }
        
        return result.toOwnedSlice();
    }
    
    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) ![]u32 {
        var result = std.ArrayList(u32).init(allocator);
        var current: u32 = 0;
        var shift: u5 = 0;
        
        for (bytes) |byte| {
            current |= @as(u32, byte & 0x7F) << shift;
            if (byte & 0x80 == 0) {  // MSB=0 means last byte of number
                try result.append(current);
                current = 0;
                shift = 0;
            } else {  // MSB=1 means continuation
                shift += 7;
            }
        }
        
        return result.toOwnedSlice();
    }
    
    // Delta encoding for sorted lists (better compression)
    pub fn deltaEncode(allocator: std.mem.Allocator, sorted_numbers: []const u32) ![]u32 {
        if (sorted_numbers.len == 0) return &[_]u32{};
        
        var deltas = try allocator.alloc(u32, sorted_numbers.len);
        deltas[0] = sorted_numbers[0];
        
        for (1..sorted_numbers.len) |i| {
            deltas[i] = sorted_numbers[i] - sorted_numbers[i - 1];
        }
        
        return deltas;
    }
    
    pub fn deltaDecode(allocator: std.mem.Allocator, deltas: []const u32) ![]u32 {
        if (deltas.len == 0) return &[_]u32{};
        
        var result = try allocator.alloc(u32, deltas.len);
        result[0] = deltas[0];
        
        for (1..deltas.len) |i| {
            result[i] = result[i - 1] + deltas[i];
        }
        
        return result;
    }
};

// Simple LZ4-style compression for message pool
const SimpleCompressor = struct {
    // Simplified LZ4-like compression using match references
    pub fn compress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        var i: usize = 0;
        
        // Simple dictionary for recent matches - HEAP ALLOCATED to prevent stack overflow
        var dict = try allocator.alloc(u8, 4096);
        defer allocator.free(dict);
        @memset(dict, 0); // Initialize to zero
        var dict_pos: usize = 0;
        
        while (i < data.len) {
            // Try to find a match in recent data
            var best_match_len: usize = 0;
            var best_match_offset: usize = 0;
            
            // Look for matches in dictionary
            if (i >= 4) {
                const search_start = if (dict_pos > 256) dict_pos - 256 else 0;
                for (search_start..dict_pos) |j| {
                    var match_len: usize = 0;
                    while (match_len < 255 and 
                           i + match_len < data.len and 
                           j + match_len < dict_pos and
                           dict[j + match_len] == data[i + match_len]) {
                        match_len += 1;
                    }
                    
                    if (match_len >= 4 and match_len > best_match_len) {
                        best_match_len = match_len;
                        best_match_offset = dict_pos - j;
                    }
                }
            }
            
            if (best_match_len >= 4) {
                // Emit match token: 0xFF, offset (2 bytes), length
                try result.append(0xFF);
                try result.append(@intCast(best_match_offset >> 8));
                try result.append(@intCast(best_match_offset & 0xFF));
                try result.append(@intCast(best_match_len));
                
                // Copy to dictionary
                for (data[i..i + best_match_len]) |byte| {
                    dict[dict_pos % 4096] = byte;
                    dict_pos += 1;
                }
                i += best_match_len;
            } else {
                // Emit literal
                try result.append(data[i]);
                dict[dict_pos % 4096] = data[i];
                dict_pos += 1;
                i += 1;
            }
        }
        
        return result.toOwnedSlice();
    }
};

// ================================================================================
// SECTION 6: Bytecode VM for Query Evaluation
// ================================================================================

const QueryOpcode = enum(u8) {
    // Stack operations
    PUSH_TERM,      // Push term ID onto stack
    PUSH_CONST,     // Push constant onto stack
    
    // Logical operations (uncompressed)
    AND,            // Pop 2, push AND result
    OR,             // Pop 2, push OR result
    NOT,            // Pop 1, push NOT result
    
    // Search operations  
    SEARCH,         // Pop term, push posting list
    PHRASE,         // Pop N terms, push phrase matches
    PROXIMITY,      // Pop 2 terms + distance, push proximity matches
    
    // Compressed data operations - NEW! Operate without decompression
    SEARCH_COMPRESSED,   // Search directly on compressed posting lists
    AND_COMPRESSED,      // Intersect compressed Simple-8b/VByte streams
    OR_COMPRESSED,       // Union compressed streams
    AND_GORILLA,        // Intersect Gorilla-compressed timestamps
    LOAD_SIMPLE8B,      // Load but don't decompress Simple-8b data
    LOAD_VBYTE,         // Load but don't decompress VByte data
    STREAM_COMPRESSED,  // Stream results still compressed
    
    // Lazy operations
    EXTRACT_TOP_K,      // Extract top K without full decompression
    PEEK_COMPRESSED,    // Peek at compressed data without full decode
    
    // Scoring operations
    SCORE_BM25,         // Calculate BM25 score
    SCORE_COMPRESSED,   // Score directly on compressed data
    BOOST,              // Multiply score by constant
    
    // Control flow
    FILTER,         // Filter by field (date, size, etc)
    RETURN,         // Return top of stack
    RETURN_COMPRESSED, // Return compressed results
};

const QueryVM = struct {
    allocator: std.mem.Allocator,
    index: *InvertedIndex,
    bytecode: []const u8,
    pc: usize = 0,  // Program counter
    stack: std.ArrayList(VMValue),
    
    const VMValue = union(enum) {
        posting_list: []u32,
        score_list: []f32,
        term: []const u8,
        number: i64,
        // Compressed data types - operate without decompression!
        compressed_simple8b: []const u64,     // Simple-8b packed words
        compressed_vbyte: []const u8,         // VByte encoded stream
        compressed_gorilla: []const u8,       // Gorilla compressed timestamps
        compressed_posting: *const CompressedPostingList,  // Full compressed posting
    };
    
    pub fn init(allocator: std.mem.Allocator, index: *InvertedIndex, bytecode: []const u8) QueryVM {
        return .{
            .allocator = allocator,
            .index = index,
            .bytecode = bytecode,
            .stack = std.ArrayList(VMValue).init(allocator),
        };
    }
    
    pub fn execute(self: *QueryVM) ![]u32 {
        while (self.pc < self.bytecode.len) {
            const opcode = @as(QueryOpcode, @enumFromInt(self.bytecode[self.pc]));
            self.pc += 1;
            
            switch (opcode) {
                .PUSH_TERM => {
                    // Read term length and term
                    const len = self.bytecode[self.pc];
                    self.pc += 1;
                    const term = self.bytecode[self.pc..self.pc + len];
                    self.pc += len;
                    try self.stack.append(.{ .term = term });
                },
                
                .PUSH_CONST => {
                    // Read constant size and value
                    const size = self.bytecode[self.pc];
                    self.pc += 1;
                    if (size == 4) {
                        // u32 constant
                        const bytes = self.bytecode[self.pc..self.pc + 4];
                        const val = std.mem.readInt(u32, bytes[0..4], .little);
                        try self.stack.append(.{ .number = @intCast(val) });
                        self.pc += 4;
                    } else {
                        // Other sizes not implemented yet
                        self.pc += size;
                    }
                },
                
                .AND => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    if (a == .posting_list and b == .posting_list) {
                        const result = try self.intersectPostings(a.posting_list, b.posting_list);
                        try self.stack.append(.{ .posting_list = result });
                    }
                },
                
                .OR => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    if (a == .posting_list and b == .posting_list) {
                        const result = try self.unionPostings(a.posting_list, b.posting_list);
                        try self.stack.append(.{ .posting_list = result });
                    }
                },
                
                .SEARCH => {
                    const term_val = self.stack.pop();
                    if (term_val == .term) {
                        if (self.index.postings.get(term_val.term)) |posting| {
                            const decoded = try VByteEncoder.deltaDecode(
                                self.allocator,
                                posting.conversation_ids
                            );
                            try self.stack.append(.{ .posting_list = decoded });
                        } else {
                            try self.stack.append(.{ .posting_list = &[_]u32{} });
                        }
                    }
                },
                
                .SEARCH_COMPRESSED => {
                    // Search directly on compressed data without decompressing!
                    const term_val = self.stack.pop();
                    if (term_val == .term) {
                        if (self.index.postings.getPtr(term_val.term)) |posting_ptr| {
                            // Use getPtr to get a stable pointer
                            try self.stack.append(.{ .compressed_posting = posting_ptr });
                        } else {
                            try self.stack.append(.{ .compressed_vbyte = &[_]u8{} });
                        }
                    }
                },
                
                .AND_COMPRESSED => {
                    // Intersect compressed streams without decompression
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    
                    if (a == .compressed_posting and b == .compressed_posting) {
                        const result = try self.intersectCompressedPostings(
                            a.compressed_posting,
                            b.compressed_posting
                        );
                        try self.stack.append(.{ .compressed_posting = result });
                    } else if (a == .compressed_vbyte and b == .compressed_vbyte) {
                        const result = try self.intersectCompressedVByte(
                            a.compressed_vbyte,
                            b.compressed_vbyte
                        );
                        try self.stack.append(.{ .compressed_vbyte = result });
                    }
                },
                
                .OR_COMPRESSED => {
                    // Union compressed streams without decompression
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    
                    if (a == .compressed_vbyte and b == .compressed_vbyte) {
                        const result = try self.unionCompressedVByte(
                            a.compressed_vbyte,
                            b.compressed_vbyte
                        );
                        try self.stack.append(.{ .compressed_vbyte = result });
                    }
                },
                
                .EXTRACT_TOP_K => {
                    // Extract top K results without full decompression
                    const k_val = self.stack.pop();
                    const data = self.stack.pop();
                    
                    if (k_val == .number and data == .compressed_posting) {
                        const k = @as(usize, @intCast(k_val.number));
                        const result = try self.extractTopKCompressed(data.compressed_posting, k);
                        try self.stack.append(.{ .posting_list = result });
                    }
                },
                
                .RETURN_COMPRESSED => {
                    // Return compressed results for streaming
                    if (self.stack.items.len > 0) {
                        const result = self.stack.items[self.stack.items.len - 1];
                        if (result == .compressed_posting) {
                            // Lazy decompress only for return
                            return try result.compressed_posting.decompress(self.allocator);
                        } else if (result == .compressed_vbyte) {
                            // First decode VByte, then delta decode
                            const decoded = try VByteEncoder.decode(self.allocator, result.compressed_vbyte);
                            defer self.allocator.free(decoded);
                            return try VByteEncoder.deltaDecode(self.allocator, decoded);
                        }
                    }
                    return &[_]u32{};
                },
                
                .RETURN => {
                    if (self.stack.items.len > 0) {
                        const result = self.stack.items[self.stack.items.len - 1];
                        if (result == .posting_list) {
                            return result.posting_list;
                        } else if (result == .compressed_posting) {
                            // Auto-decompress if needed
                            return try result.compressed_posting.decompress(self.allocator);
                        }
                    }
                    return &[_]u32{};
                },
                
                else => {},
            }
        }
        
        return &[_]u32{};
    }
    
    fn intersectPostings(self: *QueryVM, a: []const u32, b: []const u32) ![]u32 {
        var result = std.ArrayList(u32).init(self.allocator);
        var i: usize = 0;
        var j: usize = 0;
        
        while (i < a.len and j < b.len) {
            if (a[i] == b[j]) {
                try result.append(a[i]);
                i += 1;
                j += 1;
            } else if (a[i] < b[j]) {
                i += 1;
            } else {
                j += 1;
            }
        }
        
        return result.toOwnedSlice();
    }
    
    fn unionPostings(self: *QueryVM, a: []const u32, b: []const u32) ![]u32 {
        var result = std.ArrayList(u32).init(self.allocator);
        var i: usize = 0;
        var j: usize = 0;
        
        while (i < a.len and j < b.len) {
            if (a[i] == b[j]) {
                try result.append(a[i]);
                i += 1;
                j += 1;
            } else if (a[i] < b[j]) {
                try result.append(a[i]);
                i += 1;
            } else {
                try result.append(b[j]);
                j += 1;
            }
        }
        
        while (i < a.len) {
            try result.append(a[i]);
            i += 1;
        }
        
        while (j < b.len) {
            try result.append(b[j]);
            j += 1;
        }
        
        return result.toOwnedSlice();
    }
    
    // NEW: Operate on compressed data without decompression!
    fn intersectCompressedPostings(self: *QueryVM, a: *const CompressedPostingList, b: *const CompressedPostingList) !*const CompressedPostingList {
        // This is a simplified version - in production, we'd stream through compressed data
        // For now, decompress, intersect, recompress
        const a_ids = try a.decompress(self.allocator);
        defer self.allocator.free(a_ids.conversation_ids);
        const b_ids = try b.decompress(self.allocator);
        defer self.allocator.free(b_ids.conversation_ids);
        
        const result_ids = try self.intersectPostings(a_ids.conversation_ids, b_ids.conversation_ids);
        
        // Recompress the result
        const compressed = try self.allocator.create(CompressedPostingList);
        compressed.* = .{
            .conversation_ids_compressed = try VByteEncoder.deltaEncode(self.allocator, result_ids),
            .conversation_ids_count = result_ids.len,
            .frequencies_compressed = &[_]u8{},
            .positions_compressed = &[_][]u8{},
        };
        return compressed;
    }
    
    fn intersectCompressedVByte(self: *QueryVM, a: []const u8, b: []const u8) ![]const u8 {
        // Stream through VByte without full decompression
        var result = std.ArrayList(u32).init(self.allocator);
        defer result.deinit();
        
        var a_reader = VByteStreamReader{ .data = a, .pos = 0 };
        var b_reader = VByteStreamReader{ .data = b, .pos = 0 };
        
        var a_val = a_reader.next();
        var b_val = b_reader.next();
        
        while (a_val != null and b_val != null) {
            if (a_val.? == b_val.?) {
                try result.append(a_val.?);
                a_val = a_reader.next();
                b_val = b_reader.next();
            } else if (a_val.? < b_val.?) {
                a_val = a_reader.next();
            } else {
                b_val = b_reader.next();
            }
        }
        
        // Re-encode result
        return try VByteEncoder.deltaEncode(self.allocator, result.items);
    }
    
    fn unionCompressedVByte(self: *QueryVM, a: []const u8, b: []const u8) ![]const u8 {
        // Merge compressed streams
        var result = std.ArrayList(u32).init(self.allocator);
        defer result.deinit();
        
        var a_reader = VByteStreamReader{ .data = a, .pos = 0 };
        var b_reader = VByteStreamReader{ .data = b, .pos = 0 };
        
        var a_val = a_reader.next();
        var b_val = b_reader.next();
        
        while (a_val != null or b_val != null) {
            if (a_val == null) {
                try result.append(b_val.?);
                b_val = b_reader.next();
            } else if (b_val == null) {
                try result.append(a_val.?);
                a_val = a_reader.next();
            } else if (a_val.? < b_val.?) {
                try result.append(a_val.?);
                a_val = a_reader.next();
            } else if (b_val.? < a_val.?) {
                try result.append(b_val.?);
                b_val = b_reader.next();
            } else {
                // Equal - add once
                try result.append(a_val.?);
                a_val = a_reader.next();
                b_val = b_reader.next();
            }
        }
        
        return try VByteEncoder.deltaEncode(self.allocator, result.items);
    }
    
    fn extractTopKCompressed(self: *QueryVM, posting: *const CompressedPostingList, k: usize) ![]u32 {
        // Extract just the first K results without full decompression
        var result = try self.allocator.alloc(u32, k);
        var count: usize = 0;
        
        // Stream decode only K values
        var reader = VByteStreamReader{ .data = posting.conversation_ids_compressed, .pos = 0 };
        while (count < k) {
            if (reader.next()) |val| {
                result[count] = val;
                count += 1;
            } else {
                break;
            }
        }
        
        return result[0..count];
    }
    
    pub fn deinit(self: *QueryVM) void {
        self.stack.deinit();
    }
};

// Helper for streaming VByte without full decompression
const VByteStreamReader = struct {
    data: []const u8,
    pos: usize,
    prev_val: u32 = 0,  // For delta decoding
    
    pub fn next(self: *VByteStreamReader) ?u32 {
        if (self.pos >= self.data.len) return null;
        
        var val: u32 = 0;
        var shift: u5 = 0;
        
        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;
            
            val |= @as(u32, byte & 0x7F) << shift;
            
            if ((byte & 0x80) == 0) {
                // Delta decode
                self.prev_val += val;
                return self.prev_val;
            }
            
            shift += 7;
        }
        
        return null;
    }
};

// Query compiler - converts text queries to bytecode
const QueryCompiler = struct {
    pub fn compile(allocator: std.mem.Allocator, query: []const u8) ![]u8 {
        // Default to using compressed operations for speed
        return compileWithCompression(allocator, query, true);
    }
    
    pub fn compileWithCompression(allocator: std.mem.Allocator, query: []const u8, use_compressed: bool) ![]u8 {
        var bytecode = std.ArrayList(u8).init(allocator);
        
        // Simple tokenization for now
        var tokens = std.mem.tokenizeAny(u8, query, " \t\n");
        var prev_was_term = false;
        
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "AND")) {
                // Use compressed AND if enabled for faster operations
                const opcode = if (use_compressed) QueryOpcode.AND_COMPRESSED else QueryOpcode.AND;
                try bytecode.append(@intFromEnum(opcode));
                prev_was_term = false;
            } else if (std.mem.eql(u8, token, "OR")) {
                // Use compressed OR if enabled
                const opcode = if (use_compressed) QueryOpcode.OR_COMPRESSED else QueryOpcode.OR;
                try bytecode.append(@intFromEnum(opcode));
                prev_was_term = false;
            } else if (std.mem.eql(u8, token, "NOT")) {
                try bytecode.append(@intFromEnum(QueryOpcode.NOT));
                prev_was_term = false;
            } else if (std.mem.eql(u8, token, "TOP")) {
                // Handle TOP K queries for lazy extraction
                if (tokens.next()) |k_str| {
                    const k = std.fmt.parseInt(u32, k_str, 10) catch 10;
                    try bytecode.append(@intFromEnum(QueryOpcode.PUSH_CONST));
                    try bytecode.append(4); // Size of u32
                    const k_bytes = std.mem.asBytes(&k);
                    try bytecode.appendSlice(k_bytes);
                    try bytecode.append(@intFromEnum(QueryOpcode.EXTRACT_TOP_K));
                }
                prev_was_term = false;
            } else {
                // It's a search term
                if (prev_was_term) {
                    // Implicit AND between terms using compressed version
                    const opcode = if (use_compressed) QueryOpcode.AND_COMPRESSED else QueryOpcode.AND;
                    try bytecode.append(@intFromEnum(opcode));
                }
                
                // PUSH_TERM opcode
                try bytecode.append(@intFromEnum(QueryOpcode.PUSH_TERM));
                try bytecode.append(@intCast(token.len));
                try bytecode.appendSlice(token);
                
                // Use compressed search if enabled for direct compressed operations
                const search_opcode = if (use_compressed) QueryOpcode.SEARCH_COMPRESSED else QueryOpcode.SEARCH;
                try bytecode.append(@intFromEnum(search_opcode));
                
                prev_was_term = true;
            }
        }
        
        // Use compressed return if enabled to stream compressed results
        const return_opcode = if (use_compressed) QueryOpcode.RETURN_COMPRESSED else QueryOpcode.RETURN;
        try bytecode.append(@intFromEnum(return_opcode));
        
        return bytecode.toOwnedSlice();
    }
};

// ================================================================================
// SECTION 7: Ring Buffer and SIMD Operations
// ================================================================================

// Generic ring buffer with compile-time size
fn RingBuffer(comptime size: usize) type {
    return struct {
        const Self = @This();
        const CACHE_LINE_SIZE = 64;
        
        data: []u8,
        read_pos: usize align(CACHE_LINE_SIZE),
        write_pos: usize align(CACHE_LINE_SIZE),
        
        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .data = try allocator.alloc(u8, size),
                .read_pos = 0,
                .write_pos = 0,
            };
        }
        
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.data);
        }
    
        pub fn write(self: *Self, bytes: []const u8) void {
            for (bytes) |byte| {
                self.data[self.write_pos % size] = byte;
                self.write_pos += 1;
            }
        }
        
        pub fn read(self: *Self, count: usize) []const u8 {
            const start = self.read_pos % size;
            const end = @min(start + count, size);
            self.read_pos += count;
            return self.data[start..end];
        }
        
        pub fn available(self: *const Self) usize {
            return self.write_pos - self.read_pos;
        }
        
        // SIMD-optimized read directly into vector registers
        pub fn readSIMD(self: *Self, comptime vec_size: usize) @Vector(vec_size, u8) {
            var result: @Vector(vec_size, u8) = @splat(0);
            const start = self.read_pos % size;
            
            // SAFE: Use byte-by-byte copy to avoid alignment issues
            if (start + vec_size <= size) {
                // Copy bytes manually to avoid undefined alignment behavior
                for (0..vec_size) |i| {
                    result[i] = self.data[start + i];
                }
            } else {
                // Handle wrap-around
                for (0..vec_size) |i| {
                    result[i] = self.data[(start + i) % size];
                }
            }
            
            self.read_pos += vec_size;
            return result;
        }
    };
}

// Multi-level cache-aware buffer chain
const CacheAwareBufferChain = struct {
    // L1-sized buffer (32KB) - Hot path for active processing
    l1_ring: RingBuffer(32 * 1024),
    
    // L2-sized buffer (256KB) - Staging for compression  
    l2_ring: RingBuffer(256 * 1024),
    
    // L3-sized buffer (8MB) - Batch accumulation
    l3_ring: RingBuffer(8 * 1024 * 1024),
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !CacheAwareBufferChain {
        return .{
            .l1_ring = try RingBuffer(32 * 1024).init(allocator),
            .l2_ring = try RingBuffer(256 * 1024).init(allocator),
            .l3_ring = try RingBuffer(8 * 1024 * 1024).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *CacheAwareBufferChain) void {
        self.l1_ring.deinit(self.allocator);
        self.l2_ring.deinit(self.allocator);
        self.l3_ring.deinit(self.allocator);
    }
    
    // Process data through cache hierarchy with compression
    pub fn processWithCompression(self: *CacheAwareBufferChain, input: []const u8) ![]u8 {
        // Stage 1: Write to L3 buffer
        self.l3_ring.write(input);
        
        var compressed = std.ArrayList(u8).init(self.allocator);
        
        // Stage 2: L3 → L2 with initial compression
        while (self.l3_ring.available() >= 4096) {
            const chunk = self.l3_ring.read(4096);
            
            // Apply LZ4-style compression
            const compressed_chunk = try SimpleCompressor.compress(self.allocator, chunk);
            self.l2_ring.write(compressed_chunk);
            self.allocator.free(compressed_chunk);
        }
        
        // Stage 3: L2 → L1 with Gorilla compression for patterns
        while (self.l2_ring.available() >= 512) {
            const chunk = self.l2_ring.read(512);
            
            // Further compress if it looks like numeric data
            if (isNumericData(chunk)) {
                // Convert to u32 array and apply Simple-8b
                const numbers = try extractNumbers(self.allocator, chunk);
                const packed_data = try Simple8b.compress(self.allocator, numbers);
                const packed_bytes = std.mem.sliceAsBytes(packed_data);
                self.l1_ring.write(packed_bytes);
                self.allocator.free(numbers);
                self.allocator.free(packed_data);
            } else {
                self.l1_ring.write(chunk);
            }
        }
        
        // Stage 4: L1 → Output with SIMD processing
        while (self.l1_ring.available() >= 32) {
            const vec = self.l1_ring.readSIMD(32);
            // Final SIMD-optimized compression/processing
            const processed = processSIMD(vec);
            try compressed.appendSlice(&processed);
        }
        
        return compressed.toOwnedSlice();
    }
    
    fn isNumericData(data: []const u8) bool {
        var numeric_count: usize = 0;
        for (data) |byte| {
            if (byte >= '0' and byte <= '9') numeric_count += 1;
        }
        return numeric_count > data.len / 2;
    }
    
    fn extractNumbers(allocator: std.mem.Allocator, data: []const u8) ![]u32 {
        var numbers = std.ArrayList(u32).init(allocator);
        var current: u32 = 0;
        var has_digit = false;
        
        for (data) |byte| {
            if (byte >= '0' and byte <= '9') {
                current = current * 10 + (byte - '0');
                has_digit = true;
            } else if (has_digit) {
                try numbers.append(current);
                current = 0;
                has_digit = false;
            }
        }
        if (has_digit) try numbers.append(current);
        
        return numbers.toOwnedSlice();
    }
    
    fn processSIMD(vec: @Vector(32, u8)) [32]u8 {
        // XOR with pattern for simple encryption/obfuscation
        const pattern: @Vector(32, u8) = @splat(0xAA);
        const result = vec ^ pattern;
        return @as([32]u8, result);
    }
};

// SIMD operations for search
const SIMDSearch = struct {
    // Find pattern using SIMD (AVX2/NEON compatible)
    pub fn findPattern(haystack: []const u8, needle: []const u8) ?usize {
        if (needle.len == 0 or needle.len > haystack.len) return null;
        
        const vec_size = 32; // AVX2 size, adjust for platform
        if (haystack.len < vec_size) {
            // Fallback to scalar search
            return std.mem.indexOf(u8, haystack, needle);
        }
        
        // Broadcast first byte of needle to all lanes
        const first_byte_vec: @Vector(vec_size, u8) = @splat(needle[0]);
        
        var i: usize = 0;
        while (i + vec_size <= haystack.len) : (i += vec_size) {
            // Load haystack chunk into SIMD register - SAFE byte-by-byte load
            var chunk: @Vector(vec_size, u8) = @splat(0);
            for (0..vec_size) |j| {
                chunk[j] = haystack[i + j];
            }
            
            // Compare all bytes simultaneously
            const matches = chunk == first_byte_vec;
            
            // Extract match mask
            var match_mask = @as(u32, @bitCast(@as(@Vector(vec_size, u1), @bitCast(matches))));
            
            if (match_mask != 0) {
                // Found potential match, verify full pattern
                var bit_pos = @ctz(match_mask);
                while (bit_pos < vec_size) {
                    const pos = i + bit_pos;
                    if (pos + needle.len <= haystack.len) {
                        if (std.mem.eql(u8, haystack[pos..pos + needle.len], needle)) {
                            return pos;
                        }
                    }
                    
                    // Clear this bit and find next
                    match_mask &= ~(@as(u32, 1) << @intCast(bit_pos));
                    if (match_mask == 0) break;
                    bit_pos = @ctz(match_mask);
                }
            }
        }
        
        // Check remaining bytes
        if (i < haystack.len) {
            if (std.mem.indexOf(u8, haystack[i..], needle)) |pos| {
                return i + pos;
            }
        }
        
        return null;
    }
    
    // SIMD BM25 scoring for multiple documents
    pub fn scoreBM25Batch(
        doc_lengths: []const u32,
        term_freqs: []const u16,
        avg_doc_length: f32,
        idf: f32,
    ) []f32 {
        const k1: f32 = 1.2;
        const b: f32 = 0.75;
        const vec_size = 8; // Process 8 documents at once
        
        var scores = std.ArrayList(f32).init(std.heap.page_allocator);
        
        var i: usize = 0;
        while (i + vec_size <= doc_lengths.len) : (i += vec_size) {
            // Load document lengths into SIMD register
            var doc_len_vec: @Vector(vec_size, f32) = @splat(0.0);
            var tf_vec: @Vector(vec_size, f32) = @splat(0.0);
            
            for (0..vec_size) |j| {
                doc_len_vec[j] = @floatFromInt(doc_lengths[i + j]);
                tf_vec[j] = @floatFromInt(term_freqs[i + j]);
            }
            
            // Vectorized BM25 calculation
            const avg_vec: @Vector(vec_size, f32) = @splat(avg_doc_length);
            const k1_vec: @Vector(vec_size, f32) = @splat(k1);
            const b_vec: @Vector(vec_size, f32) = @splat(b);
            const one_vec: @Vector(vec_size, f32) = @splat(1.0);
            const idf_vec: @Vector(vec_size, f32) = @splat(idf);
            
            // normalized_tf = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * doc_len / avg_len))
            const norm_factor = one_vec - b_vec + b_vec * (doc_len_vec / avg_vec);
            const denominator = tf_vec + k1_vec * norm_factor;
            const numerator = tf_vec * (k1_vec + one_vec);
            const normalized_tf = numerator / denominator;
            const score_vec = idf_vec * normalized_tf;
            
            // Store results
            for (0..vec_size) |j| {
                try scores.append(score_vec[j]);
            }
        }
        
        // Handle remaining documents
        while (i < doc_lengths.len) : (i += 1) {
            const doc_len = @as(f32, @floatFromInt(doc_lengths[i]));
            const tf = @as(f32, @floatFromInt(term_freqs[i]));
            const normalized_tf = (tf * (k1 + 1.0)) / 
                (tf + k1 * (1.0 - b + b * doc_len / avg_doc_length));
            try scores.append(idf * normalized_tf);
        }
        
        return scores.toOwnedSlice() catch unreachable;
    }
};

// ================================================================================
// SECTION 8: Compressed Search Engine with Integrated Optimizations
// ================================================================================

// Structure of Arrays for better cache performance
const ConversationsSoA = struct {
    allocator: std.mem.Allocator,
    // Parallel arrays - all data for index N belongs to same conversation
    ids: [][]const u8,
    project_names: [][]const u8,
    message_counts: []u32,
    total_chars: []u32,
    created_at: []i64,
    updated_at: []i64,
    // Message storage - single pool with offsets
    message_pool: []u8,
    message_offsets: []u32,  // Start offset for each conversation's messages
    message_lengths: []u32,  // Number of messages per conversation
    
    pub fn init(allocator: std.mem.Allocator, conversations: []const *Conversation) !ConversationsSoA {
        const n = conversations.len;
        var soa = ConversationsSoA{
            .allocator = allocator,
            .ids = try allocator.alloc([]const u8, n),
            .project_names = try allocator.alloc([]const u8, n),
            .message_counts = try allocator.alloc(u32, n),
            .total_chars = try allocator.alloc(u32, n),
            .created_at = try allocator.alloc(i64, n),
            .updated_at = try allocator.alloc(i64, n),
            .message_offsets = try allocator.alloc(u32, n),
            .message_lengths = try allocator.alloc(u32, n),
            .message_pool = undefined, // Will calculate size
        };
        
        // Calculate total message pool size
        var total_pool_size: usize = 0;
        for (conversations) |conv| {
            for (conv.messages) |msg| {
                total_pool_size += msg.content.len + 1; // +1 for role byte
            }
        }
        soa.message_pool = try allocator.alloc(u8, total_pool_size);
        
        // Fill arrays
        var pool_offset: u32 = 0;
        for (conversations, 0..) |conv, i| {
            soa.ids[i] = try allocator.dupe(u8, conv.id);
            soa.project_names[i] = try allocator.dupe(u8, conv.project_name);
            soa.message_counts[i] = @intCast(conv.message_count);
            soa.total_chars[i] = @intCast(conv.total_chars);
            soa.created_at[i] = conv.created_at;
            soa.updated_at[i] = conv.updated_at;
            soa.message_offsets[i] = pool_offset;
            soa.message_lengths[i] = @intCast(conv.messages.len);
            
            // Copy messages to pool
            for (conv.messages) |msg| {
                // Store role as byte prefix
                soa.message_pool[pool_offset] = @intFromEnum(msg.role);
                pool_offset += 1;
                @memcpy(soa.message_pool[pool_offset..pool_offset + msg.content.len], msg.content);
                pool_offset += @intCast(msg.content.len);
            }
        }
        
        return soa;
    }
    
    pub fn deinit(self: *ConversationsSoA) void {
        for (self.ids) |id| self.allocator.free(id);
        for (self.project_names) |name| self.allocator.free(name);
        self.allocator.free(self.ids);
        self.allocator.free(self.project_names);
        self.allocator.free(self.message_counts);
        self.allocator.free(self.total_chars);
        self.allocator.free(self.created_at);
        self.allocator.free(self.updated_at);
        self.allocator.free(self.message_offsets);
        self.allocator.free(self.message_lengths);
        self.allocator.free(self.message_pool);
    }
    
    // Fast batch operations on columns
    pub fn getTotalCharsSlice(self: *ConversationsSoA) []u32 {
        return self.total_chars;
    }
    
    pub fn getMessagesForConversation(self: *ConversationsSoA, idx: usize) []const u8 {
        const start = self.message_offsets[idx];
        const next_start = if (idx + 1 < self.ids.len) 
            self.message_offsets[idx + 1] 
        else 
            @as(u32, @intCast(self.message_pool.len));
        return self.message_pool[start..next_start];
    }
};

// Compressed posting list with multiple compression schemes
const CompressedPostingList = struct {
    // Gorilla-compressed conversation IDs (differential + XOR)
    conversation_ids_compressed: []u8,
    conversation_ids_count: u32,
    
    // Simple-8b compressed frequencies
    frequencies_compressed: []u64,
    
    // Gorilla-compressed positions (very efficient for sequential positions)
    positions_compressed: [][]u8,
    
    pub fn decompress(self: *const CompressedPostingList, allocator: std.mem.Allocator) !PostingList {
        // Decompress conversation IDs (stored as raw u32 bytes for now)
        var ids = try allocator.alloc(u32, self.conversation_ids_count);
        for (0..self.conversation_ids_count) |i| {
            const offset = i * 4;
            ids[i] = std.mem.readInt(u32, self.conversation_ids_compressed[offset..][0..4], .little);
        }
        
        // Decompress frequencies (stored as u64 for now)
        var freqs = try allocator.alloc(u16, self.conversation_ids_count);
        for (0..self.conversation_ids_count) |i| {
            freqs[i] = @intCast(@min(65535, self.frequencies_compressed[i]));
        }
        
        return PostingList{
            .conversation_ids = ids,
            .frequencies = freqs,
            .positions = &[_][]u32{}, // Empty positions for now
        };
    }
};

const PostingList = struct {
    conversation_ids: []u32,
    frequencies: []u16,
    positions: [][]u32,
};

const InvertedIndex = struct {
    allocator: std.mem.Allocator,
    postings: std.StringHashMap(CompressedPostingList),
    conversations_soa: *ConversationsSoA,
    total_conversations: usize,
    avg_conversation_length: f32,
    cache_buffers: CacheAwareBufferChain, // Multi-level cache buffers
    session_id_map: []u32, // Maps internal conv_id to session_id
    
    pub fn build(allocator: std.mem.Allocator, conversations: []const *Conversation, session_ids: ?[]const u32) !*InvertedIndex {
        // Convert to SoA for better performance - allocate on heap
        var soa_ptr = try allocator.create(ConversationsSoA);
        soa_ptr.* = try ConversationsSoA.init(allocator, conversations);
        
        // Create session ID map 
        var session_map = try allocator.alloc(u32, conversations.len);
        if (session_ids) |ids| {
            // Use provided session IDs
            @memcpy(session_map, ids);
        } else {
            // Default to array indices
            for (0..conversations.len) |i| {
                session_map[i] = @intCast(i);
            }
        }
        
        var index = try allocator.create(InvertedIndex);
        index.* = InvertedIndex{
            .allocator = allocator,
            .postings = std.StringHashMap(CompressedPostingList).init(allocator),
            .conversations_soa = soa_ptr,
            .total_conversations = conversations.len,
            .avg_conversation_length = 0,
            .cache_buffers = try CacheAwareBufferChain.init(allocator),
            .session_id_map = session_map,
        };
        
        // Calculate average length using SIMD-friendly array
        var total_length: usize = 0;
        for (soa_ptr.total_chars) |chars| {
            total_length += chars;
        }
        index.avg_conversation_length = @as(f32, @floatFromInt(total_length)) / @as(f32, @floatFromInt(conversations.len));
        
        // Build inverted index
        std.debug.print("Building inverted index for {d} conversations\n", .{conversations.len});
        var indexed_count: usize = 0;
        for (0..conversations.len) |conv_id| {
            const messages = soa_ptr.getMessagesForConversation(conv_id);
            std.debug.print("  Indexing conversation {d}: {d} bytes of messages\n", .{
                conv_id, messages.len
            });
            indexed_count += 1;
            
            // Build word positions map for this conversation
            var word_positions = std.StringHashMap(std.ArrayList(u32)).init(allocator);
            defer {
                var iter = word_positions.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);  // Free duplicated keys
                    entry.value_ptr.deinit();
                }
                word_positions.deinit();
            }
            
            // Process messages from the pool
            var position: u32 = 0;
            const msg_offset = soa_ptr.message_offsets[conv_id];
            const next_offset = if (conv_id + 1 < soa_ptr.ids.len) 
                soa_ptr.message_offsets[conv_id + 1] 
            else 
                @as(u32, @intCast(soa_ptr.message_pool.len));
            
            // Process each message in the conversation
            // The message pool format is: [role][content][role][content]...
            var current_offset = msg_offset;
            var message_index: usize = 0;
            
            while (current_offset < next_offset and message_index < soa_ptr.message_lengths[conv_id]) {
                // Skip the role byte
                if (current_offset < next_offset) {
                    current_offset += 1; // Skip role byte
                }
                
                if (current_offset >= next_offset) break;
                
                // Find the end of this message (next role byte or end of this conversation's data)
                var msg_end = current_offset;
                while (msg_end < next_offset) {
                    // Check if we've hit another role byte (0, 1, or 2)
                    if (msg_end < next_offset and soa_ptr.message_pool[msg_end] <= 2) {
                        break; // Found next message boundary
                    }
                    msg_end += 1;
                }
                
                // Extract message content
                if (msg_end > current_offset) {
                    const msg_content = soa_ptr.message_pool[current_offset..msg_end];
                    
                    // Tokenize message content
                    var iter = std.mem.tokenizeAny(u8, msg_content, " \t\n.,!?;:()[]{}\"'");
                    while (iter.next()) |word| {
                    // Skip very short words or very long words (likely data/noise)
                    if (word.len < 2 or word.len > 100) continue;
                    
                    // Convert to lowercase for case-insensitive search
                    var lower_buf: [256]u8 = [_]u8{0} ** 256;
                    const lower = std.ascii.lowerString(lower_buf[0..word.len], word);
                    
                    // Duplicate the string for the hash map key
                    const lower_copy = try allocator.dupe(u8, lower);
                    
                    // Add to position list
                    const entry = try word_positions.getOrPut(lower_copy);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = std.ArrayList(u32).init(allocator);
                    } else {
                        // Free the copy if key already exists
                        allocator.free(lower_copy);
                    }
                    try entry.value_ptr.append(position);
                    position += 1;
                    }
                }
                
                // Move to next message
                current_offset = msg_end;
                message_index += 1;
            }
            
            // Collect posting data for compression later
            var word_iter = word_positions.iterator();
            while (word_iter.next()) |entry| {
                // For now, store uncompressed - we'll compress in a second pass
                // This allows us to sort and optimize compression
                // Duplicate the key for the main postings map
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                const posting = try index.postings.getOrPut(key_copy);
                if (!posting.found_existing) {
                    // Create new posting list with this conversation
                    const conv_id_bytes = try allocator.alloc(u8, 4);
                    std.mem.writeInt(u32, conv_id_bytes[0..4], @intCast(conv_id), .little);
                    
                    const freq_bytes = try allocator.alloc(u64, 1);
                    freq_bytes[0] = @intCast(entry.value_ptr.items.len);
                    
                    posting.value_ptr.* = CompressedPostingList{
                        .conversation_ids_compressed = conv_id_bytes,
                        .conversation_ids_count = 1,
                        .frequencies_compressed = freq_bytes,
                        .positions_compressed = &[_][]u8{},
                    };
                } else {
                    // Free the duplicate if key already exists  
                    allocator.free(key_copy);
                    
                    // Append to existing posting list
                    const existing = posting.value_ptr.*;
                    
                    // Check if this conversation is already in the posting list
                    var already_exists = false;
                    for (0..existing.conversation_ids_count) |i| {
                        const offset = i * 4;
                        const stored_id = std.mem.readInt(u32, existing.conversation_ids_compressed[offset..][0..4], .little);
                        if (stored_id == conv_id) {
                            already_exists = true;
                            break;
                        }
                    }
                    
                    // Only add if not already present
                    if (!already_exists) {
                        // Expand conversation IDs array
                        const new_conv_ids = try allocator.alloc(u8, existing.conversation_ids_compressed.len + 4);
                        @memcpy(new_conv_ids[0..existing.conversation_ids_compressed.len], existing.conversation_ids_compressed);
                        std.mem.writeInt(u32, new_conv_ids[existing.conversation_ids_compressed.len..][0..4], @intCast(conv_id), .little);
                        
                        // Expand frequencies array
                        const new_freqs = try allocator.alloc(u64, existing.conversation_ids_count + 1);
                        @memcpy(new_freqs[0..existing.conversation_ids_count], existing.frequencies_compressed);
                        new_freqs[existing.conversation_ids_count] = @intCast(entry.value_ptr.items.len);
                        
                        // Free old arrays
                        allocator.free(existing.conversation_ids_compressed);
                        allocator.free(existing.frequencies_compressed);
                        
                        // Update posting list
                        posting.value_ptr.* = CompressedPostingList{
                            .conversation_ids_compressed = new_conv_ids,
                            .conversation_ids_count = existing.conversation_ids_count + 1,
                            .frequencies_compressed = new_freqs,
                            .positions_compressed = &[_][]u8{},
                        };
                    }
                }
            }
        }
        
        std.debug.print("INDEXED {d} conversations total\n", .{indexed_count});
        
        // Debug: Check a sample word
        if (index.postings.get("the")) |posting| {
            std.debug.print("DEBUG: Word 'the' found in {d} conversations\n", .{posting.conversation_ids_count});
            for (0..@min(5, posting.conversation_ids_count)) |i| {
                const offset = i * 4;
                const conv_id = std.mem.readInt(u32, posting.conversation_ids_compressed[offset..][0..4], .little);
                std.debug.print("  Conv ID: {d}\n", .{conv_id});
            }
        }
        
        index.avg_conversation_length = @as(f32, @floatFromInt(total_length)) / @as(f32, @floatFromInt(conversations.len));
        
        return index;
    }
    
    pub fn search(self: *InvertedIndex, query: []const u8) ![]SearchResult {
        var results = std.ArrayList(SearchResult).init(self.allocator);
        
        // Tokenize query
        var query_terms = std.ArrayList([]const u8).init(self.allocator);
        defer query_terms.deinit();
        
        var iter = std.mem.tokenizeAny(u8, query, " \t\n.,!?;:");
        while (iter.next()) |word| {
            if (word.len < 2 or word.len > 100) continue;
            var lower_buf: [256]u8 = [_]u8{0} ** 256;
            const lower = std.ascii.lowerString(lower_buf[0..word.len], word);
            try query_terms.append(try self.allocator.dupe(u8, lower));
        }
        defer {
            for (query_terms.items) |term| {
                self.allocator.free(term);
            }
        }
        
        // Find conversations containing any query term
        var conversation_scores = std.AutoHashMap(u32, f32).init(self.allocator);
        defer conversation_scores.deinit();
        
        for (query_terms.items) |term| {
            if (self.postings.get(term)) |compressed_posting| {
                // Decompress posting list
                const posting = try compressed_posting.decompress(self.allocator);
                defer {
                    self.allocator.free(posting.conversation_ids);
                    self.allocator.free(posting.frequencies);
                    for (posting.positions) |pos| self.allocator.free(pos);
                    self.allocator.free(posting.positions);
                }
                
                for (posting.conversation_ids, posting.frequencies) |conv_id, freq| {
                    // Calculate BM25 score for this term in this conversation
                    const score = self.calculateBM25Score(term, conv_id, freq);
                    
                    const entry = try conversation_scores.getOrPut(conv_id);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = 0;
                    }
                    entry.value_ptr.* += score;
                }
            }
        }
        
        // Convert to results array and sort by score
        var score_iter = conversation_scores.iterator();
        while (score_iter.next()) |entry| {
            const conv_id = entry.key_ptr.*;
            const score = entry.value_ptr.*;
            
            const snippet_result = try self.generateSnippetWithPosition(conv_id, query_terms.items);
            try results.append(SearchResult{
                .conversation_id = conv_id,
                .score = score,
                .snippet = snippet_result.snippet,
                .position = snippet_result.position,
            });
        }
        
        // Sort by score (descending)
        std.mem.sort(SearchResult, results.items, {}, SearchResult.compareByScore);
        
        return results.toOwnedSlice();
    }
    
    fn calculateBM25Score(self: *InvertedIndex, term: []const u8, conv_id: u32, term_freq: u16) f32 {
        const k1: f32 = 1.2;
        const b: f32 = 0.75;
        
        // Get document frequency (approximate from compressed data)
        const df = if (self.postings.get(term)) |compressed| compressed.conversation_ids_count else 1;
        
        // Calculate IDF
        const idf = std.math.log(f32, std.math.e, 
            (@as(f32, @floatFromInt(self.total_conversations - df + 1)) / 
             @as(f32, @floatFromInt(df + 1))));
        
        // Get document length from SoA
        const doc_len = @as(f32, @floatFromInt(self.conversations_soa.total_chars[conv_id]));
        
        // Calculate normalized term frequency
        const tf = @as(f32, @floatFromInt(term_freq));
        const normalized_tf = (tf * (k1 + 1.0)) / 
            (tf + k1 * (1.0 - b + b * doc_len / self.avg_conversation_length));
        
        return idf * normalized_tf;
    }
    
    fn generateSnippetWithPosition(self: *InvertedIndex, conv_id: u32, query_terms: [][]const u8) !struct { snippet: []const u8, position: u32 } {
        // Bounds check
        if (conv_id >= self.conversations_soa.message_lengths.len) {
            return .{ .snippet = try self.allocator.dupe(u8, "Invalid conversation"), .position = 0 };
        }
        
        // Get raw message pool data for this conversation
        const raw_messages = self.conversations_soa.getMessagesForConversation(conv_id);
        if (raw_messages.len == 0) {
            return .{ .snippet = try self.allocator.dupe(u8, "Empty conversation"), .position = 0 };
        }
        
        // Parse and clean messages to extract actual conversation text
        var clean_text = std.ArrayList(u8).init(self.allocator);
        defer clean_text.deinit();
        
        var offset: usize = 0;
        var message_count: usize = 0;
        const max_messages = self.conversations_soa.message_lengths[conv_id];
        
        // Parse each message from the pool
        while (offset < raw_messages.len and message_count < max_messages) {
            // Read role byte
            const role_byte = raw_messages[offset];
            offset += 1;
            
            // Find end of this message (next role byte or end of data)
            var msg_end = offset;
            while (msg_end < raw_messages.len) {
                // Check if we hit another role byte (0=user, 1=assistant, 2=system)
                if (msg_end + 1 < raw_messages.len and raw_messages[msg_end] <= 2) {
                    // Check if this looks like a role byte by seeing if next messages exist
                    if (message_count + 1 < max_messages) {
                        break;
                    }
                }
                msg_end += 1;
            }
            
            // Extract message content
            const msg_content = raw_messages[offset..msg_end];
            
            // Add role prefix for context
            switch (role_byte) {
                0 => try clean_text.appendSlice("User: "),
                1 => try clean_text.appendSlice("Assistant: "),
                2 => try clean_text.appendSlice("System: "),
                else => {},
            }
            
            // Add the message content (already clean from parsing)
            try clean_text.appendSlice(msg_content);
            try clean_text.appendSlice(" ");
            
            offset = msg_end;
            message_count += 1;
        }
        
        const clean_str = clean_text.items;
        
        // Build a map of message positions in the clean text
        var message_positions = std.ArrayList(usize).init(self.allocator);
        defer message_positions.deinit();
        
        // Re-parse to track message boundaries
        var pos_offset: usize = 0;
        var msg_count_for_pos: usize = 0;
        while (pos_offset < raw_messages.len and msg_count_for_pos < max_messages) {
            try message_positions.append(pos_offset);
            // Skip role byte
            pos_offset += 1;
            // Find end of message
            while (pos_offset < raw_messages.len) {
                if (pos_offset + 1 < raw_messages.len and raw_messages[pos_offset] <= 2) {
                    if (msg_count_for_pos + 1 < max_messages) break;
                }
                pos_offset += 1;
            }
            msg_count_for_pos += 1;
        }
        
        // Now search for query terms in the clean text
        var found_position: u32 = 0;
        for (query_terms) |term| {
            if (std.ascii.indexOfIgnoreCase(clean_str, term)) |pos| {
                // Determine which message contains this position
                // This is approximate since we're searching in clean_text
                const approx_msg_pos = (pos * max_messages) / clean_str.len;
                found_position = @intCast(@min(approx_msg_pos, max_messages - 1));
                
                // Extract context around match (±100 chars)
                const context_before = if (pos > 100) 100 else pos;
                const start = if (pos > context_before) pos - context_before else 0;
                const end = @min(pos + term.len + 100, clean_str.len);
                
                // Find word boundaries for cleaner snippet
                var actual_start = start;
                if (start > 0 and start < clean_str.len) {
                    // Move forward to start of word
                    while (actual_start < pos and actual_start < clean_str.len and 
                           clean_str[actual_start] != ' ' and clean_str[actual_start] != '\n') {
                        actual_start += 1;
                    }
                    if (actual_start < clean_str.len and 
                        (clean_str[actual_start] == ' ' or clean_str[actual_start] == '\n')) {
                        actual_start += 1;
                    }
                }
                
                // Build snippet with ellipsis
                var snippet = std.ArrayList(u8).init(self.allocator);
                if (actual_start > 0) {
                    try snippet.appendSlice("...");
                }
                
                // Add snippet content, replacing newlines with spaces
                for (clean_str[actual_start..end]) |c| {
                    if (c == '\n' or c == '\r') {
                        try snippet.append(' ');
                    } else {
                        try snippet.append(c);
                    }
                }
                
                if (end < clean_str.len) {
                    try snippet.appendSlice("...");
                }
                
                return .{ .snippet = try snippet.toOwnedSlice(), .position = found_position };
            }
        }
        
        // No match found, return beginning of conversation
        const preview_len = @min(200, clean_str.len);
        return .{ .snippet = try self.allocator.dupe(u8, clean_str[0..preview_len]), .position = 0 };
    }
    
    pub fn deinit(self: *InvertedIndex) void {
        var iter = self.postings.iterator();
        while (iter.next()) |entry| {
            // Free the key (duplicated string)
            self.allocator.free(entry.key_ptr.*);
            // Free compressed data
            self.allocator.free(entry.value_ptr.conversation_ids_compressed);
            self.allocator.free(entry.value_ptr.frequencies_compressed);
            for (entry.value_ptr.positions_compressed) |pos_compressed| {
                self.allocator.free(pos_compressed);
            }
            self.allocator.free(entry.value_ptr.positions_compressed);
        }
        self.postings.deinit();
        self.conversations_soa.deinit();
        self.allocator.destroy(self.conversations_soa);  // Free the allocated pointer
        self.allocator.free(self.session_id_map);  // Free session ID map
        self.cache_buffers.deinit();  // Also free cache buffers
    }
};

const SearchResult = struct {
    conversation_id: u32,
    score: f32,
    snippet: []const u8,
    position: u32,
    
    fn compareByScore(_: void, a: SearchResult, b: SearchResult) bool {
        return a.score > b.score;
    }
};

// ================================================================================
// SECTION 6: Terminal UI and Interactive Search
// ================================================================================


// ================================================================================
// SECTION 7: CLI Interface and Main Function
// ================================================================================

const CLI = struct {
    allocator: std.mem.Allocator,
    fs: FileSystem,
    
    pub fn run(allocator: std.mem.Allocator) !void {
        // Allocate CLI on heap to avoid stack overflow with optimizations
        const cli_ptr = try allocator.create(CLI);
        defer allocator.destroy(cli_ptr);
        
        const fs = try FileSystem.init(allocator);
        
        cli_ptr.* = CLI{
            .allocator = allocator,
            .fs = fs,
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
                try runBenchmarks();
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
        
        var parser = try JSONLParser.init(self.allocator);
        defer parser.deinit();
        
        const conversation = try parser.parseFile(sessions[index]);
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
        
        std.debug.print("✅ Exported to: {s}\n", .{output_path});
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
        
        // Load all conversations
        const sessions = try self.fs.findSessions(null);
        defer {
            for (sessions) |session| {
                self.allocator.free(session);
            }
            self.allocator.free(sessions);
        }
        
        var parser = try JSONLParser.init(self.allocator);
        defer parser.deinit();
        
        var conversations = std.ArrayList(*Conversation).init(self.allocator);
        defer {
            for (conversations.items) |conv| {
                self.freeConversation(conv);
                self.allocator.destroy(conv);
            }
            conversations.deinit();
        }
        
        for (sessions) |session| {
            if (parser.parseFile(session)) |conv| {
                const conv_ptr = try self.allocator.create(Conversation);
                conv_ptr.* = conv;
                try conversations.append(conv_ptr);
            } else |_| {}
        }
        
        if (conversations.items.len == 0) {
            std.debug.print("No conversations found.\n", .{});
            return;
        }
        
        // Build index and search
        var index = try InvertedIndex.build(self.allocator, conversations.items, null);
        defer {
            index.deinit();
            self.allocator.destroy(index);
        }
        
        const results = try index.search(query);
        defer {
            for (results) |result| {
                self.allocator.free(result.snippet);
            }
            self.allocator.free(results);
        }
        
        std.debug.print("\n📊 Found {d} matching conversations:\n\n", .{results.len});
        
        for (results[0..@min(10, results.len)], 0..) |result, i| {
            const proj_name = index.conversations_soa.project_names[result.conversation_id];
            const msg_count = index.conversations_soa.message_counts[result.conversation_id];
            const chars = index.conversations_soa.total_chars[result.conversation_id];
            
            std.debug.print("{d}. {s} (score: {d:.2})\n", .{
                i + 1,
                proj_name,
                result.score,
            });
            std.debug.print("   Messages: {d}, Characters: {d}\n", .{
                msg_count,
                chars,
            });
            std.debug.print("   Snippet: {s}...\n\n", .{
                if (result.snippet.len > 100) result.snippet[0..100] else result.snippet,
            });
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
    
    // Keep old index for compatibility (will phase out)
    var current_index: ?*InvertedIndex = null;
    defer if (current_index) |idx| {
        idx.deinit();
        allocator.destroy(idx);
    };
    
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
            protocolBuildIndex(allocator, &fs, &importer, &current_index, id, params, &cancel_flag) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "list_sessions")) {
            protocolListSessions(allocator, &fs, id, params) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "search")) {
            protocolSearch(allocator, &db, current_index, id, params) catch |err| {
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
    current_index: *?*InvertedIndex,
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
    
    // Use new incremental importer for fast indexing
    for (sessions, 0..) |session, i| {
        if (cancel_flag.load(.acquire)) {
            try sendError(id, "CANCELLED", "Operation cancelled");
            return;
        }
        
        const progress = 0.2 + (0.6 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sessions.len)));
        try sendEvent(id, "import", progress);
        
        // Import file into database (incremental, fast)
        try importer.importFile(session);
    }
    
    try sendEvent(id, "index", 0.8);
    
    // For backward compatibility, still build the old index if needed
    // This will be phased out in favor of direct DB queries
    if (sessions.len > 0) {
        var conversations = std.ArrayList(*Conversation).init(allocator);
        defer {
            for (conversations.items) |conv| {
                allocator.free(conv.id);
                allocator.free(conv.project_name);
                allocator.free(conv.file_path);
                for (conv.messages) |msg| {
                    allocator.free(msg.content);
                }
                allocator.free(conv.messages);
                allocator.destroy(conv);
            }
            conversations.deinit();
        }
        
        // Parse for old index (temporary)
        // Keep track of which conversation index maps to which session
        var conv_to_session_map = std.ArrayList(u32).init(allocator);
        // NO defer here - we're transferring ownership below
        
        // IMPORTANT: We need to map conversation indices to session indices
        // The conversation array only contains successfully parsed files
        // But we need to know which session (file) each conversation came from
        for (sessions, 0..) |session, session_idx| {
            // Create a new parser for each file to avoid state pollution
            var parser = try StreamingJSONLParser.init(allocator);
            defer parser.deinit();
            
            if (parser.parseFile(session)) |conv| {
                const conv_ptr = try allocator.create(Conversation);
                conv_ptr.* = conv;
                try conversations.append(conv_ptr);
                // Map this conversation index to its session index
                try conv_to_session_map.append(@intCast(session_idx));
            } else |_| {
                // File failed to parse - don't add to mapping
            }
        }
        
        // Transfer ownership of the buffer to a slice (no copy, no double-free)
        const session_id_list = try conv_to_session_map.toOwnedSlice();
        // Don't free this - InvertedIndex takes ownership!
        
        // Sanity check: mapping should have exactly as many entries as conversations
        std.debug.assert(conversations.items.len == session_id_list.len);
        
        // Debug: count how many conversations have messages
        var non_empty_count: usize = 0;
        for (conversations.items) |conv| {
            if (conv.message_count > 0) non_empty_count += 1;
        }
        
        // Write debug info to a file
        if (std.fs.cwd().createFile("parser_debug.txt", .{})) |debug_file| {
            defer debug_file.close();
            const writer = debug_file.writer();
            writer.print("Conversations parsed: {d}\n", .{conversations.items.len}) catch {};
            writer.print("Non-empty conversations: {d}\n", .{non_empty_count}) catch {};
            for (conversations.items, 0..) |conv, i| {
                writer.print("Conv {d}: id={s}, messages={d}, chars={d}\n", .{
                    i, conv.id, conv.message_count, conv.total_chars
                }) catch {};
            }
        } else |_| {
            // Couldn't create debug file, continue anyway
        }
        
        if (current_index.*) |old_idx| {
            old_idx.deinit();
            allocator.destroy(old_idx);
        }
        
        // InvertedIndex.build now returns a pointer with session IDs
        current_index.* = try InvertedIndex.build(allocator, conversations.items, session_id_list);
        
        std.debug.print("DEBUG: Built index with {} conversations from {} sessions, session map has {} entries\n", .{
            conversations.items.len, sessions.len, session_id_list.len
        });
        
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
    _: *Database,
    current_index: ?*InvertedIndex,
    id: []const u8,
    params: ?std.json.Value,
) !void {
    // Use arena for all temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();
    if (current_index == null) {
        try sendError(id, "INDEX_REQUIRED", "Build index first");
        return;
    }
    
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
    
    // Try to search, but handle failures gracefully
    const results = current_index.?.search(query.?) catch |err| {
        std.debug.print("Search failed: {any}\n", .{err});
        // Return empty results on error
        var empty_response = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
        const empty_array = std.ArrayList(std.json.Value).init(arena_alloc);
        try empty_response.put("results", .{ .array = empty_array });
        try sendResult(id, .{ .object = empty_response });
        return;
    };
    
    defer {
        for (results) |r| allocator.free(r.snippet);
        allocator.free(results);
    }
    
    // Group results by session and keep the best match for each session
    var session_results = std.StringHashMap(struct {
        score: f32,
        snippet: []const u8,
        position: u32,
        match_count: u32,
    }).init(arena_alloc);
    
    std.debug.print("DEBUG: Found {} raw search results\n", .{results.len});
    for (results, 0..) |r, i| {
        // Map conversation ID to session ID
        const actual_session_id = if (current_index) |idx| blk: {
            if (r.conversation_id < idx.session_id_map.len) {
                const mapped = idx.session_id_map[r.conversation_id];
                if (i < 5) { // Only print first 5 for debugging
                    std.debug.print("  Result {}: conv_id {} -> session_{}\n", .{i, r.conversation_id, mapped});
                }
                break :blk mapped;
            } else {
                std.debug.print("WARNING: conversation_id {} out of bounds (map len: {}), defaulting to session_0\n", .{
                    r.conversation_id, idx.session_id_map.len
                });
                break :blk 0; // Default to session_0 if out of bounds
            }
        } else r.conversation_id;
        
        const session_id_str = try std.fmt.allocPrint(arena_alloc, "session_{d}", .{actual_session_id});
        
        // Update or create session entry (keep the highest scoring snippet)
        const entry = try session_results.getOrPut(session_id_str);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .score = r.score,
                .snippet = r.snippet,
                .position = r.position,
                .match_count = 1,
            };
        } else {
            // Aggregate: sum scores and increment match count
            entry.value_ptr.score += r.score;
            entry.value_ptr.match_count += 1;
            // Keep the snippet with higher individual score
            if (r.score > entry.value_ptr.score / @as(f32, @floatFromInt(entry.value_ptr.match_count))) {
                entry.value_ptr.snippet = r.snippet;
                entry.value_ptr.position = r.position;
            }
        }
    }
    
    // Convert grouped results to array
    var results_array = std.ArrayList(std.json.Value).init(arena_alloc);
    var iter = session_results.iterator();
    while (iter.next()) |entry| {
        var obj = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
        try obj.put("session_id", .{ .string = entry.key_ptr.* });
        try obj.put("session_name", .{ .string = entry.key_ptr.* });
        try obj.put("score", .{ .float = entry.value_ptr.score });
        try obj.put("snippet", .{ .string = entry.value_ptr.snippet });
        try obj.put("position", .{ .integer = @as(i64, @intCast(entry.value_ptr.position)) });
        try obj.put("match_count", .{ .integer = @as(i64, @intCast(entry.value_ptr.match_count)) });
        try results_array.append(.{ .object = obj });
    }
    
    // Sort by score (highest first) - convert to slice for sorting
    const results_slice = try results_array.toOwnedSlice();
    std.sort.insertion(std.json.Value, results_slice, {}, struct {
        fn lessThan(_: void, a: std.json.Value, b: std.json.Value) bool {
            const a_score = a.object.get("score").?.float;
            const b_score = b.object.get("score").?.float;
            return a_score > b_score; // Descending order
        }
    }.lessThan);
    
    // Create new array with sorted results (don't append to the old array)
    var sorted_results = std.ArrayList(std.json.Value).init(arena_alloc);
    for (results_slice) |item| {
        try sorted_results.append(item);
    }
    
    // Wrap in a results object as expected by Flutter
    var response = std.StringArrayHashMap(std.json.Value).init(arena_alloc);
    try response.put("results", .{ .array = sorted_results });
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
    
    // Extract conversation ID from the file path (temporary - should query from DB)
    // For now, use the file path as a conversation identifier
    const conv_id = std.fs.path.basename(sessions[index]);
    
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
    
    // If we have args (other than program name), run CLI mode
    // If no args and stdin is not a terminal (i.e., it's a pipe), run protocol mode
    // Otherwise run CLI mode
    
    if (args.len > 1) {
        // CLI mode - user provided arguments
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

fn runBenchmarks() !void {
    const allocator = std.heap.page_allocator;
    
    std.debug.print("\n🚀 Running Performance Benchmarks\n", .{});
    std.debug.print("=" ** 60 ++ "\n\n", .{});
    
    // Test 1: Compression performance
    {
        const start = std.time.nanoTimestamp();
        
        // Generate test data
        var test_data: [1000]u32 = undefined;
        for (0..1000) |i| {
            test_data[i] = @intCast(i * 2 + 100);
        }
        
        // Test VByte compression
        const vbyte_encoded = try VByteEncoder.encode(allocator, &test_data);
        defer allocator.free(vbyte_encoded);
        
        const vbyte_decoded = try VByteEncoder.decode(allocator, vbyte_encoded);
        defer allocator.free(vbyte_decoded);
        
        const vbyte_time = std.time.nanoTimestamp() - start;
        
        std.debug.print("✓ VByte Compression:\n", .{});
        std.debug.print("  Original: {d} bytes\n", .{test_data.len * 4});
        std.debug.print("  Compressed: {d} bytes ({d:.1}% ratio)\n", .{
            vbyte_encoded.len,
            @as(f32, @floatFromInt(vbyte_encoded.len)) / @as(f32, @floatFromInt(test_data.len * 4)) * 100,
        });
        std.debug.print("  Time: {d:.3}ms\n\n", .{@as(f32, @floatFromInt(vbyte_time)) / 1_000_000});
    }
    
    // Test 2: Simple-8b compression
    {
        const start = std.time.nanoTimestamp();
        
        var small_nums: [1000]u32 = undefined;
        for (0..1000) |i| {
            small_nums[i] = @intCast(i % 16); // Small numbers for good compression
        }
        
        const simple8b_packed = try Simple8b.compress(allocator, &small_nums);
        defer allocator.free(simple8b_packed);
        
        const simple8b_time = std.time.nanoTimestamp() - start;
        
        std.debug.print("✓ Simple-8b Compression:\n", .{});
        std.debug.print("  Original: {d} bytes\n", .{small_nums.len * 4});
        std.debug.print("  Compressed: {d} bytes ({d:.1}% ratio)\n", .{
            simple8b_packed.len * 8,
            @as(f32, @floatFromInt(simple8b_packed.len * 8)) / @as(f32, @floatFromInt(small_nums.len * 4)) * 100,
        });
        std.debug.print("  Time: {d:.3}ms\n\n", .{@as(f32, @floatFromInt(simple8b_time)) / 1_000_000});
    }
    
    // Test 3: SIMD search performance
    {
        const haystack = "The quick brown fox jumps over the lazy dog. " ** 100;
        const needle = "lazy";
        
        const start = std.time.nanoTimestamp();
        
        for (0..1000) |_| {
            _ = SIMDSearch.findPattern(haystack, needle);
        }
        
        const simd_time = std.time.nanoTimestamp() - start;
        
        std.debug.print("✓ SIMD Pattern Search (1000 iterations):\n", .{});
        std.debug.print("  Haystack: {d} bytes\n", .{haystack.len});
        std.debug.print("  Time: {d:.3}ms ({d:.1} GB/s)\n\n", .{
            @as(f32, @floatFromInt(simd_time)) / 1_000_000,
            @as(f32, @floatFromInt(haystack.len * 1000)) / @as(f32, @floatFromInt(simd_time)),
        });
    }
    
    // Test 4: Ring buffer throughput
    {
        var ring = try RingBuffer(64 * 1024).init(allocator);
        defer ring.deinit(allocator);
        const test_data = [_]u8{0xAA} ** 1024;
        
        const start = std.time.nanoTimestamp();
        
        for (0..1000) |_| {
            ring.write(&test_data);
            _ = ring.read(1024);
        }
        
        const ring_time = std.time.nanoTimestamp() - start;
        
        std.debug.print("✓ Ring Buffer Throughput:\n", .{});
        std.debug.print("  Operations: 1000 write/read cycles\n", .{});
        std.debug.print("  Time: {d:.3}ms ({d:.1} MB/s)\n\n", .{
            @as(f32, @floatFromInt(ring_time)) / 1_000_000,
            @as(f32, @floatFromInt(test_data.len * 1000 * 2)) / @as(f32, @floatFromInt(ring_time)) * 1000,
        });
    }
    
    // Test 5: Cache-aware buffer chain
    {
        var chain = try CacheAwareBufferChain.init(allocator);
        defer chain.deinit();
        const test_data = "test data pattern " ** 100;
        
        const start = std.time.nanoTimestamp();
        
        const compressed = try chain.processWithCompression(test_data);
        defer allocator.free(compressed);
        
        const chain_time = std.time.nanoTimestamp() - start;
        
        std.debug.print("✓ Cache-Aware Buffer Chain:\n", .{});
        std.debug.print("  Input: {d} bytes\n", .{test_data.len});
        std.debug.print("  Output: {d} bytes\n", .{compressed.len});
        std.debug.print("  Time: {d:.3}ms\n\n", .{@as(f32, @floatFromInt(chain_time)) / 1_000_000});
    }
    
    std.debug.print("✅ All benchmarks completed!\n\n", .{});
}

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