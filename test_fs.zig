const std = @import("std");

const FileSystem = struct {
    allocator: std.mem.Allocator,
    claude_dir: []const u8,
    output_dir: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) !FileSystem {
        std.debug.print("FileSystem.init: Getting HOME...\n", .{});
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        std.debug.print("FileSystem.init: HOME = {s}\n", .{home});
        
        const claude_dir = try std.fmt.allocPrint(allocator, "{s}/.claude/projects", .{home});
        const output_dir = try allocator.dupe(u8, "./test-output");
        
        return FileSystem{
            .allocator = allocator,
            .claude_dir = claude_dir,
            .output_dir = output_dir,
        };
    }
    
    pub fn deinit(self: *FileSystem) void {
        self.allocator.free(self.claude_dir);
        self.allocator.free(self.output_dir);
    }
};

pub fn main() !void {
    std.debug.print("Starting...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("About to call FileSystem.init...\n", .{});
    var fs = try FileSystem.init(allocator);
    defer fs.deinit();
    
    std.debug.print("Success! claude_dir = {s}\n", .{fs.claude_dir});
}