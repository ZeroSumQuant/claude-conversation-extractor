const std = @import("std");

const FileSystem = struct {
    allocator: std.mem.Allocator,
    claude_dir: []const u8,
    output_dir: []const u8,
    
    pub fn init(allocator: std.mem.Allocator) !FileSystem {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        
        const claude_dir = try std.fmt.allocPrint(allocator, "{s}/.claude/projects", .{home});
        const output_dir = try allocator.dupe(u8, "./claude-logs");
        
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

const CLI = struct {
    allocator: std.mem.Allocator,
    fs: FileSystem,
    
    pub fn run(allocator: std.mem.Allocator) !void {
        std.debug.print("CLI.run starting...\n", .{});
        
        std.debug.print("Initializing FileSystem...\n", .{});
        var cli = CLI{
            .allocator = allocator,
            .fs = try FileSystem.init(allocator),
        };
        defer cli.fs.deinit();
        std.debug.print("FileSystem initialized\n", .{});
        
        std.debug.print("Getting args...\n", .{});
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        std.debug.print("Got {} args\n", .{args.len});
        
        std.debug.print("CLI.run completed\n", .{});
    }
};

pub fn main() !void {
    std.debug.print("Starting extractor...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Initialized allocator...\n", .{});
    
    CLI.run(allocator) catch |err| {
        std.debug.print("Error: {any}\n", .{err});
        std.process.exit(1);
    };
}