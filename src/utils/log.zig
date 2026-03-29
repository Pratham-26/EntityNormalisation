const std = @import("std");

pub const Level = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
};

var current_level: Level = .info;

pub fn setLevel(level: Level) void {
    current_level = level;
}

pub fn debug(comptime message: []const u8, args: anytype) void {
    if (@intFromEnum(current_level) <= @intFromEnum(Level.debug)) {
        std.log.debug(message, args);
    }
}

pub fn info(comptime message: []const u8, args: anytype) void {
    if (@intFromEnum(current_level) <= @intFromEnum(Level.info)) {
        std.log.info(message, args);
    }
}

pub fn warn(comptime message: []const u8, args: anytype) void {
    if (@intFromEnum(current_level) <= @intFromEnum(Level.warn)) {
        std.log.warn(message, args);
    }
}

pub fn err(comptime message: []const u8, args: anytype) void {
    if (@intFromEnum(current_level) <= @intFromEnum(Level.err)) {
        std.log.err(message, args);
    }
}

test "Level ordering" {
    try std.testing.expect(@intFromEnum(Level.debug) < @intFromEnum(Level.info));
    try std.testing.expect(@intFromEnum(Level.info) < @intFromEnum(Level.warn));
    try std.testing.expect(@intFromEnum(Level.warn) < @intFromEnum(Level.err));
}
