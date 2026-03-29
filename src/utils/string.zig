const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn toUpper(allocator: Allocator, s: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

pub fn toLower(allocator: Allocator, s: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, &std.ascii.whitespace);
}

pub fn prefix(s: []const u8, len: usize) []const u8 {
    if (len >= s.len) {
        return s;
    }
    return s[0..len];
}

pub fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "toUpper" {
    const result = try toUpper(std.testing.allocator, "hello");
    defer std.testing.allocator.free(result);
    try std.testing.expect(eql(result, "HELLO"));
}

test "toLower" {
    const result = try toLower(std.testing.allocator, "HELLO");
    defer std.testing.allocator.free(result);
    try std.testing.expect(eql(result, "hello"));
}

test "trim" {
    try std.testing.expect(eql(trim("  hello  "), "hello"));
    try std.testing.expect(eql(trim("\thello\n"), "hello"));
    try std.testing.expect(eql(trim("hello"), "hello"));
    try std.testing.expect(eql(trim(""), ""));
}

test "prefix" {
    try std.testing.expect(eql(prefix("hello", 3), "hel"));
    try std.testing.expect(eql(prefix("hello", 10), "hello"));
    try std.testing.expect(eql(prefix("hello", 0), ""));
}

test "eql" {
    try std.testing.expect(eql("abc", "abc"));
    try std.testing.expect(!eql("abc", "ABC"));
    try std.testing.expect(!eql("abc", "abcd"));
}
