const std = @import("std");

const FileSystem = struct {
    allocator: std.mem.Allocator,
    claude_dir: []const u8,
    output_dir: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) !FileSystem {
        std.debug.print("FileSystem.init starting...\n", .{});
        
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        std.debug.print("Got HOME: {s}\n", .{home});
        
        // Build ~/.claude/projects path
        const claude_dir = try std.fmt.allocPrint(allocator, "{s}/.claude/projects", .{home});
        std.debug.print("Claude dir: {s}\n", .{claude_dir});
        
        // Try to create output directory in order of preference
        var output_dirs = std.ArrayList([]const u8).init(allocator);
        defer {
            for (output_dirs.items) |dir| {
                if (!std.mem.eql(u8, dir, "./claude-logs")) {
                    allocator.free(dir);
                }
            }
            output_dirs.deinit();
        }
        
        std.debug.print("Creating output dir list...\n", .{});
        try output_dirs.append(try std.fmt.allocPrint(allocator, "{s}/Desktop/Claude logs", .{home}));
        try output_dirs.append(try std.fmt.allocPrint(allocator, "{s}/Documents/Claude logs", .{home}));
        try output_dirs.append(try std.fmt.allocPrint(allocator, "{s}/Claude logs", .{home}));
        try output_dirs.append("./claude-logs");
        std.debug.print("Output dirs created\n", .{});
        
        var output_dir: []const u8 = "./claude-logs";
        var output_dir_allocated = false;
        
        std.debug.print("Testing output directories...\n", .{});
        for (output_dirs.items) |dir| {
            std.debug.print("Trying directory: {s}\n", .{dir});
            std.fs.makeDirAbsolute(dir) catch |err| {
                std.debug.print("makeDirAbsolute error: {any}\n", .{err});
                switch (err) {
                    error.PathAlreadyExists => {},
                    else => continue,
                }
            };
            
            // Test write permissions
            const test_path = try std.fmt.allocPrint(allocator, "{s}/.test", .{dir});
            defer allocator.free(test_path);
            std.debug.print("Testing write to: {s}\n", .{test_path});
            
            if (std.fs.createFileAbsolute(test_path, .{})) |file| {
                std.debug.print("File created successfully\n", .{});
                file.close();
                std.fs.deleteFileAbsolute(test_path) catch {};
                // Duplicate the string if it's not the literal
                if (!std.mem.eql(u8, dir, "./claude-logs")) {
                    output_dir = try allocator.dupe(u8, dir);
                    output_dir_allocated = true;
                } else {
                    output_dir = dir;
                }
                break;
            } else |file_err| {
                std.debug.print("File creation error: {any}\n", .{file_err});
                continue;
            }
        }
        
        std.debug.print("Selected output dir: {s}\n", .{output_dir});
        
        // Ensure output directory exists
        std.fs.makeDirAbsolute(output_dir) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            }
        };
        
        std.debug.print("📁 Claude directory: {s}\n", .{claude_dir});
        std.debug.print("📁 Output directory: {s}\n", .{output_dir});
        
        return FileSystem{
            .allocator = allocator,
            .claude_dir = claude_dir,
            .output_dir = if (output_dir_allocated) output_dir else try allocator.dupe(u8, output_dir),
        };
    }
    
    pub fn deinit(self: *FileSystem) void {
        self.allocator.free(self.claude_dir);
        self.allocator.free(self.output_dir);
    }
};

pub fn main() !void {
    std.debug.print("Starting FileSystem test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Initializing FileSystem...\n", .{});
    var fs = FileSystem.init(allocator) catch |err| {
        std.debug.print("FileSystem.init error: {any}\n", .{err});
        return err;
    };
    defer fs.deinit();
    
    std.debug.print("FileSystem test completed successfully\n", .{});
}