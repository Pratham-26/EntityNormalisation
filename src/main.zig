const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Entity Normalisation\n", .{});
}

test "simple test" {
    try std.testing.expect(true);
}
