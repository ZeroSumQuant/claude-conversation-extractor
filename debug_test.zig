const std = @import("std");

pub fn main() !void {
    std.debug.print("Starting test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Getting HOME env var...\n", .{});
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
        std.debug.print("Error getting HOME: {any}\n", .{err});
        return err;
    };
    defer allocator.free(home);
    
    std.debug.print("HOME = {s}\n", .{home});
    std.debug.print("Test completed successfully\n", .{});
}