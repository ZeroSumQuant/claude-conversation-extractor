const std = @import("std");

const TestStruct = struct {
    pub fn run(allocator: std.mem.Allocator) !void {
        std.debug.print("TestStruct.run called\n", .{});
        _ = allocator;
    }
};

pub fn main() !void {
    std.debug.print("Starting...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("About to call TestStruct.run...\n", .{});
    try TestStruct.run(allocator);
    std.debug.print("Done!\n", .{});
}