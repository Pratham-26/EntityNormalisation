const std = @import("std");
const Allocator = std.mem.Allocator;
const hash = @import("../utils/hash.zig");

pub const InvertedIndex = struct {
    index: std.HashMap(u64, std.ArrayList(u32), std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    pub fn init(allocator: Allocator) InvertedIndex {
        return .{
            .index = std.HashMap(u64, std.ArrayList(u32), std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InvertedIndex) void {
        var iter = self.index.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.index.deinit();
    }

    pub fn add(self: *InvertedIndex, value: []const u8, record_id: u32) !void {
        const h = hash.xxHash64(value);

        const entry = try self.index.getOrPut(h);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.ArrayList(u32).init(self.allocator);
        }
        try entry.value_ptr.append(record_id);
    }

    pub fn addWithHash(self: *InvertedIndex, h: u64, record_id: u32) !void {
        const entry = try self.index.getOrPut(h);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.ArrayList(u32).init(self.allocator);
        }
        try entry.value_ptr.append(record_id);
    }

    pub fn lookup(self: *const InvertedIndex, value: []const u8) ?[]const u32 {
        const h = hash.xxHash64(value);
        return self.lookupHash(h);
    }

    pub fn lookupHash(self: *const InvertedIndex, h: u64) ?[]const u32 {
        if (self.index.getPtr(h)) |list| {
            return list.items;
        }
        return null;
    }

    pub fn lookupOwned(self: *const InvertedIndex, value: []const u8, allocator: Allocator) ?[]u32 {
        const h = hash.xxHash64(value);
        if (self.index.getPtr(h)) |list| {
            return allocator.dupe(u32, list.items) catch null;
        }
        return null;
    }

    pub fn contains(self: *const InvertedIndex, value: []const u8) bool {
        const h = hash.xxHash64(value);
        return self.index.contains(h);
    }

    pub fn size(self: *const InvertedIndex) usize {
        return self.index.count();
    }

    pub fn totalRecords(self: *const InvertedIndex) usize {
        var count: usize = 0;
        var iter = self.index.iterator();
        while (iter.next()) |entry| {
            count += entry.value_ptr.items.len;
        }
        return count;
    }

    pub fn clear(self: *InvertedIndex) void {
        var iter = self.index.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.index.clearRetainingCapacity();
    }

    pub const Iterator = struct {
        map_iter: std.HashMap(u64, std.ArrayList(u32), std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).Iterator,

        pub fn next(self: *Iterator) ?struct { hash: u64, record_ids: []const u32 } {
            if (self.map_iter.next()) |entry| {
                return .{
                    .hash = entry.key_ptr.*,
                    .record_ids = entry.value_ptr.items,
                };
            }
            return null;
        }
    };

    pub fn iterator(self: *const InvertedIndex) Iterator {
        return .{
            .map_iter = self.index.iterator(),
        };
    }

    pub fn merge(self: *InvertedIndex, other: *const InvertedIndex) !void {
        var iter = other.index.iterator();
        while (iter.next()) |entry| {
            const h = entry.key_ptr.*;
            const other_records = entry.value_ptr.items;

            const existing = try self.index.getOrPut(h);
            if (!existing.found_existing) {
                existing.value_ptr.* = std.ArrayList(u32).init(self.allocator);
            }

            for (other_records) |record_id| {
                try existing.value_ptr.append(record_id);
            }
        }
    }

    pub fn removeValue(self: *InvertedIndex, value: []const u8) bool {
        const h = hash.xxHash64(value);
        if (self.index.fetchRemove(h)) |removed| {
            removed.value.deinit();
            return true;
        }
        return false;
    }

    pub fn getStats(self: *const InvertedIndex) IndexStats {
        var stats = IndexStats{};
        var iter = self.index.iterator();
        while (iter.next()) |entry| {
            stats.num_keys += 1;
            const len = entry.value_ptr.items.len;
            stats.total_records += len;
            if (len > stats.max_bucket_size) {
                stats.max_bucket_size = len;
            }
            if (stats.min_bucket_size == 0 or len < stats.min_bucket_size) {
                stats.min_bucket_size = len;
            }
        }
        if (stats.num_keys > 0) {
            stats.avg_bucket_size = @as(f64, @floatFromInt(stats.total_records)) / @as(f64, @floatFromInt(stats.num_keys));
        }
        return stats;
    }
};

pub const IndexStats = struct {
    num_keys: usize = 0,
    total_records: usize = 0,
    max_bucket_size: usize = 0,
    min_bucket_size: usize = 0,
    avg_bucket_size: f64 = 0,
};

test "InvertedIndex basic operations" {
    var idx = InvertedIndex.init(std.testing.allocator);
    defer idx.deinit();

    try idx.add("John", 1);
    try idx.add("John", 2);
    try idx.add("Jane", 3);

    const john_records = idx.lookup("John");
    try std.testing.expect(john_records != null);
    try std.testing.expectEqual(@as(usize, 2), john_records.?.len);

    const jane_records = idx.lookup("Jane");
    try std.testing.expect(jane_records != null);
    try std.testing.expectEqual(@as(usize, 1), jane_records.?.len);

    try std.testing.expect(idx.contains("John"));
    try std.testing.expect(!idx.contains("Bob"));

    try std.testing.expectEqual(@as(usize, 2), idx.size());
    try std.testing.expectEqual(@as(usize, 3), idx.totalRecords());
}

test "InvertedIndex stats" {
    var idx = InvertedIndex.init(std.testing.allocator);
    defer idx.deinit();

    try idx.add("A", 1);
    try idx.add("A", 2);
    try idx.add("A", 3);
    try idx.add("B", 4);

    const stats = idx.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.num_keys);
    try std.testing.expectEqual(@as(usize, 4), stats.total_records);
    try std.testing.expectEqual(@as(usize, 3), stats.max_bucket_size);
}
