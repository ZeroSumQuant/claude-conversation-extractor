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
// SECTION 2: File System Operations (Port of find_sessions)
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
        
        const search_dir = if (project_path) |proj|
            try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.claude_dir, proj })
        else
            self.claude_dir;
        
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
        return try self.parseFileStreaming(file_path);
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
        
        // Parse each JSONL line
        while (lines.next()) |line| {
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
            }
        }
        
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
        
        // Check if this is a message entry
        const entry_type = obj.get("type") orelse return null;
        if (entry_type != .string) return null;
        
        const type_str = entry_type.string;
        if (!std.mem.eql(u8, type_str, "user") and !std.mem.eql(u8, type_str, "assistant")) {
            return null;
        }
        
        // Get the message object
        const msg_obj = obj.get("message") orelse return null;
        if (msg_obj != .object) return null;
        
        // Extract role
        var role: Role = .user;
        if (msg_obj.object.get("role")) |role_val| {
            if (role_val == .string) {
                if (std.mem.eql(u8, role_val.string, "user")) {
                    role = .user;
                } else if (std.mem.eql(u8, role_val.string, "assistant")) {
                    role = .assistant;
                } else if (std.mem.eql(u8, role_val.string, "system")) {
                    role = .system;
                }
            }
        }
        
        // Extract content
        var content_builder = std.ArrayList(u8).init(self.allocator);
        errdefer content_builder.deinit();
        
        if (msg_obj.object.get("content")) |content_val| {
            try self.extractContent(content_val, &content_builder);
        }
        
        // Extract timestamp if available
        var timestamp: ?i64 = null;
        if (obj.get("created_at")) |ts| {
            if (ts == .integer) {
                timestamp = ts.integer;
            }
        }
        
        // Extract tool calls and responses if present
        var tool_calls: ?[]ToolCall = null;
        const tool_responses: ?[]ToolResponse = null;
        
        // Look for tool_calls in the message
        if (msg_obj.object.get("tool_calls")) |tools| {
            if (tools == .array) {
                var calls = std.ArrayList(ToolCall).init(self.allocator);
                for (tools.array.items) |tool| {
                    if (tool == .object) {
                        const tool_name = if (tool.object.get("name")) |n|
                            if (n == .string) try self.allocator.dupe(u8, n.string) else "unknown"
                        else "unknown";
                        
                        const params = if (tool.object.get("parameters")) |p|
                            try std.json.stringifyAlloc(self.allocator, p, .{})
                        else try self.allocator.dupe(u8, "{}");
                        
                        try calls.append(.{
                            .tool_name = tool_name,
                            .parameters = params,
                            .result = null,
                        });
                    }
                }
                if (calls.items.len > 0) {
                    tool_calls = try calls.toOwnedSlice();
                }
            }
        }
        
        const content_str = try content_builder.toOwnedSlice();
        
        return Message{
            .role = role,
            .content = content_str,
            .timestamp = timestamp,
            .tool_calls = tool_calls,
            .tool_responses = tool_responses,
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
        // Decompress conversation IDs
        const ids_as_i64 = try allocator.alloc(i64, self.conversation_ids_count);
        defer allocator.free(ids_as_i64);
        
        // TODO: Implement Gorilla decompression
        var ids = try allocator.alloc(u32, self.conversation_ids_count);
        for (0..self.conversation_ids_count) |i| {
            ids[i] = @intCast(i); // Placeholder
        }
        
        return PostingList{
            .conversation_ids = ids,
            .frequencies = &[_]u16{}, // TODO
            .positions = &[_][]u32{}, // TODO
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
    
    pub fn build(allocator: std.mem.Allocator, conversations: []const *Conversation) !*InvertedIndex {
        // Convert to SoA for better performance
        var soa = try ConversationsSoA.init(allocator, conversations);
        
        var index = try allocator.create(InvertedIndex);
        index.* = InvertedIndex{
            .allocator = allocator,
            .postings = std.StringHashMap(CompressedPostingList).init(allocator),
            .conversations_soa = &soa,
            .total_conversations = conversations.len,
            .avg_conversation_length = 0,
            .cache_buffers = try CacheAwareBufferChain.init(allocator),
        };
        
        // Calculate average length using SIMD-friendly array
        var total_length: usize = 0;
        for (soa.total_chars) |chars| {
            total_length += chars;
        }
        index.avg_conversation_length = @as(f32, @floatFromInt(total_length)) / @as(f32, @floatFromInt(conversations.len));
        
        // Build inverted index
        for (0..conversations.len) |conv_id| {
            _ = soa.getMessagesForConversation(conv_id);
            
            // Build word positions map for this conversation
            var word_positions = std.StringHashMap(std.ArrayList(u32)).init(allocator);
            defer {
                var iter = word_positions.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit();
                }
                word_positions.deinit();
            }
            
            // Process messages from the pool
            var position: u32 = 0;
            var msg_offset = soa.message_offsets[conv_id];
            const next_offset = if (conv_id + 1 < soa.ids.len) 
                soa.message_offsets[conv_id + 1] 
            else 
                @as(u32, @intCast(soa.message_pool.len));
            
            // Skip role bytes and tokenize content
            while (msg_offset < next_offset) {
                msg_offset += 1; // Skip role byte
                
                // Find end of current message (next role byte or end)
                var msg_end = msg_offset;
                while (msg_end < next_offset and msg_end + 1 < next_offset) {
                    if (soa.message_pool[msg_end] <= 2) break; // Found next role byte
                    msg_end += 1;
                }
                
                const msg_content = soa.message_pool[msg_offset..msg_end];
                
                // Tokenize message content
                var iter = std.mem.tokenizeAny(u8, msg_content, " \t\n.,!?;:()[]{}\"'");
                while (iter.next()) |word| {
                    // Skip very short words
                    if (word.len < 2) continue;
                    
                    // Convert to lowercase for case-insensitive search
                    var lower_buf: [256]u8 = [_]u8{0} ** 256;
                    const lower = std.ascii.lowerString(&lower_buf, word);
                    
                    // Add to position list
                    const entry = try word_positions.getOrPut(lower);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = std.ArrayList(u32).init(allocator);
                    }
                    try entry.value_ptr.append(position);
                    position += 1;
                }
                
                msg_offset = msg_end;
            }
            
            // Collect posting data for compression later
            var word_iter = word_positions.iterator();
            while (word_iter.next()) |entry| {
                // For now, store uncompressed - we'll compress in a second pass
                // This allows us to sort and optimize compression
                const posting = try index.postings.getOrPut(entry.key_ptr.*);
                if (!posting.found_existing) {
                    posting.value_ptr.* = CompressedPostingList{
                        .conversation_ids_compressed = &[_]u8{},
                        .conversation_ids_count = 0,
                        .frequencies_compressed = &[_]u64{},
                        .positions_compressed = &[_][]u8{},
                    };
                }
                
                // TODO: Accumulate and compress in batches
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
            if (word.len < 2) continue;
            var lower_buf: [256]u8 = [_]u8{0} ** 256;
            const lower = std.ascii.lowerString(&lower_buf, word);
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
            
            try results.append(SearchResult{
                .conversation_id = conv_id,
                .score = score,
                .snippet = try self.generateSnippet(conv_id, query_terms.items),
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
    
    fn generateSnippet(self: *InvertedIndex, conv_id: u32, query_terms: [][]const u8) ![]const u8 {
        _ = query_terms;
        // Get first part of conversation messages from pool
        const messages = self.conversations_soa.getMessagesForConversation(conv_id);
        const max_len = @min(200, messages.len);
        return try self.allocator.dupe(u8, messages[0..max_len]);
    }
    
    pub fn deinit(self: *InvertedIndex) void {
        var iter = self.postings.iterator();
        while (iter.next()) |entry| {
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
    }
};

const SearchResult = struct {
    conversation_id: u32,
    score: f32,
    snippet: []const u8,
    
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
        var index = try InvertedIndex.build(self.allocator, conversations.items);
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
            protocolBuildIndex(allocator, &fs, &current_index, id, params, &cancel_flag) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "list_sessions")) {
            protocolListSessions(allocator, &fs, id, params) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "search")) {
            protocolSearch(allocator, current_index, id, params) catch |err| {
                try sendError(id, "INTERNAL_ERROR", @errorName(err));
            };
        } else if (std.mem.eql(u8, method, "extract")) {
            protocolExtract(allocator, &fs, id, params) catch |err| {
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
    try stdout.print(
        \\{{"type":"hello","core_version":"{s}","protocol":{d},"capabilities":["index","search","extract","list"]}}
    ++ "\n", .{ CoreVersion, ProtocolVersion });
}

fn sendEvent(id: []const u8, stage: []const u8, progress: f32) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\{{"id":"{s}","type":"event","stage":"{s}","progress":{d:.2}}}
    ++ "\n", .{ id, stage, progress });
}

fn sendResult(id: []const u8, data: std.json.Value) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\{{"id":"{s}","type":"result","data":
    , .{id});
    try std.json.stringify(data, .{}, stdout);
    try stdout.print("}}\n", .{});
}

fn sendError(id: []const u8, code: []const u8, message: []const u8) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\{{"id":"{s}","type":"error","error":{{"code":"{s}","message":"{s}"}}}}
    ++ "\n", .{ id, code, message });
}

fn protocolBuildIndex(
    allocator: std.mem.Allocator,
    fs: *FileSystem,
    current_index: *?*InvertedIndex,
    id: []const u8,
    params: ?std.json.Value,
    cancel_flag: *std.atomic.Value(bool),
) !void {
    cancel_flag.store(false, .release);
    
    const root = if (params) |p| blk: {
        if (p.object.get("root")) |r| {
            if (r == .string) break :blk r.string;
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
    
    try sendEvent(id, "parse", 0.2);
    
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
    
    var parser = try StreamingJSONLParser.init(allocator);
    defer parser.deinit();
    
    for (sessions, 0..) |session, i| {
        if (cancel_flag.load(.acquire)) {
            try sendError(id, "CANCELLED", "Operation cancelled");
            return;
        }
        
        const progress = 0.2 + (0.4 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sessions.len)));
        try sendEvent(id, "parse", progress);
        
        if (parser.parseFile(session)) |conv| {
            const conv_ptr = try allocator.create(Conversation);
            conv_ptr.* = conv;
            try conversations.append(conv_ptr);
        } else |_| {}
    }
    
    try sendEvent(id, "index", 0.7);
    
    if (current_index.*) |old_idx| {
        old_idx.deinit();
        allocator.destroy(old_idx);
    }
    
    // InvertedIndex.build now returns a pointer
    current_index.* = try InvertedIndex.build(allocator, conversations.items);
    
    try sendEvent(id, "complete", 1.0);
    
    var result = std.StringArrayHashMap(std.json.Value).init(allocator);
    try result.put("status", .{ .string = "ok" });
    try result.put("conversations", .{ .integer = @intCast(conversations.items.len) });
    try sendResult(id, .{ .object = result });
}

fn protocolListSessions(
    allocator: std.mem.Allocator,
    fs: *FileSystem,
    id: []const u8,
    params: ?std.json.Value,
) !void {
    const root = if (params) |p| blk: {
        if (p.object.get("root")) |r| {
            if (r == .string) break :blk r.string;
        }
        break :blk null;
    } else null;
    
    const sessions = try fs.findSessions(root);
    defer {
        for (sessions) |session| allocator.free(session);
        allocator.free(sessions);
    }
    
    var sessions_array = std.ArrayList(std.json.Value).init(allocator);
    defer sessions_array.deinit();
    
    for (sessions, 0..) |session, i| {
        var obj = std.StringArrayHashMap(std.json.Value).init(allocator);
        
        const id_str = try std.fmt.allocPrint(allocator, "session_{d}", .{i});
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
    current_index: ?*InvertedIndex,
    id: []const u8,
    params: ?std.json.Value,
) !void {
    if (current_index == null) {
        try sendError(id, "INDEX_REQUIRED", "Build index first");
        return;
    }
    
    const query = if (params) |p| blk: {
        if (p.object.get("q")) |q| {
            if (q == .string) break :blk q.string;
        }
        if (p.object.get("query")) |q2| {  // alias
            if (q2 == .string) break :blk q2.string;
        }
        break :blk null;
    } else null;
    
    if (query == null) {
        try sendError(id, "INVALID_PARAMS", "Missing query");
        return;
    }
    
    const results = try current_index.?.search(query.?);
    defer {
        for (results) |r| allocator.free(r.snippet);
        allocator.free(results);
    }
    
    var results_array = std.ArrayList(std.json.Value).init(allocator);
    defer results_array.deinit();
    
    for (results[0..@min(100, results.len)]) |r| {
        var obj = std.StringArrayHashMap(std.json.Value).init(allocator);
        
        const id_str = try std.fmt.allocPrint(allocator, "{d}", .{r.conversation_id});
        try obj.put("id", .{ .string = id_str });
        try obj.put("score", .{ .float = r.score });
        try obj.put("snippet", .{ .string = r.snippet });
        try results_array.append(.{ .object = obj });
    }
    
    try sendResult(id, .{ .array = results_array });
}

fn protocolExtract(
    allocator: std.mem.Allocator,
    fs: *FileSystem,
    id: []const u8,
    params: ?std.json.Value,
) !void {
    const session_id = if (params) |p| blk: {
        if (p.object.get("session_id")) |s| {
            if (s == .string) break :blk s.string;
        }
        break :blk null;
    } else null;
    
    if (session_id == null) {
        try sendError(id, "INVALID_PARAMS", "Missing session_id");
        return;
    }
    
    const format_str = if (params) |p| blk: {
        if (p.object.get("format")) |f| {
            if (f == .string) break :blk f.string;
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
    try result.put("path", .{ .string = output_path });
    try result.put("format", .{ .string = format_str });
    try sendResult(id, .{ .object = result });
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