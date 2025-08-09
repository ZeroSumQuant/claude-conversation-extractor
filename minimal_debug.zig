const std = @import("std");

pub fn main() !void {
    std.debug.print("Starting extractor...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Initialized allocator...\n", .{});
    
    // Test just the basic function call that's causing the crash
    testFunction(allocator) catch |err| {
        std.debug.print("Error: {any}\n", .{err});
        std.process.exit(1);
    };
}

fn testFunction(allocator: std.mem.Allocator) !void {
    std.debug.print("testFunction starting...\n", .{});
    
    // Test HOME environment variable access
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    std.debug.print("HOME: {s}\n", .{home});
    
    // Test argument parsing
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    std.debug.print("Got {} args\n", .{args.len});
    
    std.debug.print("testFunction completed\n", .{});
}