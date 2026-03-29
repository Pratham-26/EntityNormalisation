const std = @import("std");

pub fn fnv1a(data: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (data) |byte| {
        hash ^= byte;
        hash *%= 1099511628211;
    }
    return hash;
}

pub fn fnv1a32(data: []const u8) u32 {
    var hash: u32 = 2166136261;
    for (data) |byte| {
        hash ^= byte;
        hash *%= 16777619;
    }
    return hash;
}

pub fn xxHash64(data: []const u8) u64 {
    return std.hash.XxHash64.hash(0, data);
}

pub fn xxHash64WithSeed(seed: u64, data: []const u8) u64 {
    return std.hash.XxHash64.hash(seed, data);
}

test "xxHash64 basic" {
    const empty = xxHash64("");
    try std.testing.expectEqual(@as(u64, 0xef46db3751d8e999), empty);

    const hello = xxHash64("hello");
    try std.testing.expect(hello != 0);
}

test "xxHash64 consistency" {
    const data = "test data for hashing";
    const h1 = xxHash64(data);
    const h2 = xxHash64(data);
    try std.testing.expectEqual(h1, h2);
}

test "xxHash64WithSeed" {
    const data = "test";
    const h1 = xxHash64WithSeed(0, data);
    const h2 = xxHash64WithSeed(1, data);
    try std.testing.expect(h1 != h2);
}

test "fnv1a basic" {
    const empty = fnv1a("");
    try std.testing.expectEqual(@as(u64, 14695981039346656037), empty);

    const hello = fnv1a("hello");
    try std.testing.expect(hello != 0);
}

test "fnv1a consistency" {
    const data = "test data for hashing";
    const h1 = fnv1a(data);
    const h2 = fnv1a(data);
    try std.testing.expectEqual(h1, h2);
}

test "fnv1a different inputs" {
    const h1 = fnv1a("hello");
    const h2 = fnv1a("world");
    try std.testing.expect(h1 != h2);
}
