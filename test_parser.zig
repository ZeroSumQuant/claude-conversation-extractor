const std = @import("std");
const extractor = @import("extractor.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Find JSONL files
    const claude_dir = try std.fs.openDirAbsolute("/Users/dustinkirby/.claude/projects/-Users-dustinkirby", .{ .iterate = true });
    var iter = claude_dir.iterate();
    
    var parser = try extractor.StreamingJSONLParser.init(allocator);
    defer parser.deinit();
    
    var file_count: usize = 0;
    var success_count: usize = 0;
    var total_messages: usize = 0;
    
    std.debug.print("Testing JSONL parser on Claude conversation files...\n", .{});
    
    while (try iter.next()) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".jsonl")) continue;
        if (file_count >= 5) break; // Test first 5 files
        
        file_count += 1;
        
        const full_path = try std.fmt.allocPrint(allocator, "/Users/dustinkirby/.claude/projects/-Users-dustinkirby/{s}", .{entry.name});
        defer allocator.free(full_path);
        
        std.debug.print("\n[{d}] Testing file: {s}\n", .{file_count, entry.name});
        
        // Reset parser for each file
        parser.reset();
        
        if (parser.parseFile(full_path)) |conv| {
            success_count += 1;
            total_messages += conv.message_count;
            std.debug.print("  ✓ SUCCESS: ID={s}, Messages={d}, Chars={d}\n", .{
                conv.id, conv.message_count, conv.total_chars
            });
            
            // Free conversation data
            allocator.free(conv.id);
            allocator.free(conv.project_name);
            allocator.free(conv.file_path);
            for (conv.messages) |msg| {
                allocator.free(msg.content);
            }
            allocator.free(conv.messages);
        } else |err| {
            std.debug.print("  ✗ FAILED: {any}\n", .{err});
        }
    }
    
    std.debug.print("\n=== SUMMARY ===\n", .{});
    std.debug.print("Files tested: {d}\n", .{file_count});
    std.debug.print("Successfully parsed: {d}\n", .{success_count});
    std.debug.print("Total messages: {d}\n", .{total_messages});
    std.debug.print("Average messages per file: {d}\n", .{if (success_count > 0) total_messages / success_count else 0});
}