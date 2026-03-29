const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../config/types.zig");
const hash_block = @import("hash_block.zig");
const Block = hash_block.Block;
const Blocker = hash_block.Blocker;

pub const SkewHandler = struct {
    max_block_size: u32,
    fallback_keys: ?[][]const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, max_size: u32, fallback_keys: ?[][]const u8) SkewHandler {
        return .{
            .max_block_size = max_size,
            .fallback_keys = fallback_keys,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SkewHandler) void {
        if (self.fallback_keys) |keys| {
            for (keys) |key| {
                self.allocator.free(key);
            }
            self.allocator.free(keys);
        }
    }

    pub fn needsFallback(self: *const SkewHandler, block: *const Block) bool {
        return block.record_ids.items.len > self.max_block_size;
    }

    pub fn applyFallback(self: *SkewHandler, blocker: *Blocker, oversized_hash: u64) !void {
        const block = blocker.getBlock(oversized_hash) orelse return error.BlockNotFound;

        if (!self.needsFallback(block)) return;

        if (self.fallback_keys == null or self.fallback_keys.?.len == 0) {
            try self.applyDefaultFallback(blocker, oversized_hash);
            return;
        }

        try self.applyKeyedFallback(blocker, oversized_hash);
    }

    fn applyDefaultFallback(self: *SkewHandler, blocker: *Blocker, oversized_hash: u64) !void {
        const block = blocker.getBlockMut(oversized_hash) orelse return;

        var record_ids = try self.allocator.dupe(u32, block.record_ids.items);
        defer self.allocator.free(record_ids);

        block.record_ids.clearRetainingCapacity();

        const chunk_size = self.max_block_size / 2;
        if (chunk_size == 0) return;

        var chunk_idx: u32 = 0;
        var i: usize = 0;
        while (i < record_ids.len) {
            const end = @min(i + chunk_size, record_ids.len);

            var new_block = hash_block.Block.init(self.allocator, oversized_hash);
            errdefer new_block.deinit();

            for (record_ids[i..end]) |record_id| {
                try new_block.record_ids.append(record_id);
            }

            const suffix_hash = self.computeChunkHash(oversized_hash, chunk_idx);
            const entry = try blocker.blocks.getOrPut(suffix_hash);
            if (entry.found_existing) {
                entry.value_ptr.deinit();
            }
            entry.value_ptr.* = new_block;
            entry.value_ptr.fallback_applied = true;

            i = end;
            chunk_idx += 1;
        }

        blocker.markFallback(oversized_hash);
    }

    fn applyKeyedFallback(self: *SkewHandler, blocker: *Blocker, oversized_hash: u64) !void {
        _ = self;
        _ = blocker;
        _ = oversized_hash;
        return error.NotImplemented;
    }

    fn computeChunkHash(self: *const SkewHandler, base_hash: u64, chunk_idx: u32) u64 {
        _ = self;
        var buf: [12]u8 = undefined;
        std.mem.writeInt(u64, buf[0..8], base_hash, .little);
        std.mem.writeInt(u32, buf[8..12], chunk_idx, .little);
        const std_hash = std.hash.Wyhash.init(0);
        return std_hash.final();
    }

    pub fn findOversizedBlocks(self: *const SkewHandler, blocker: *const Blocker, allocator: Allocator) ![]u64 {
        var list = std.ArrayList(u64).init(allocator);
        errdefer list.deinit();

        var iter = blocker.blocks.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.record_ids.items.len > self.max_block_size) {
                try list.append(entry.key_ptr.*);
            }
        }

        return list.toOwnedSlice();
    }

    pub fn processAllOversized(self: *SkewHandler, blocker: *Blocker) !usize {
        var processed: usize = 0;

        const oversized = try self.findOversizedBlocks(blocker, self.allocator);
        defer self.allocator.free(oversized);

        for (oversized) |hash_val| {
            try self.applyFallback(blocker, hash_val);
            processed += 1;
        }

        return processed;
    }

    pub fn getSkewMetrics(self: *const SkewHandler, blocker: *const Blocker) SkewMetrics {
        var metrics = SkewMetrics{};

        var iter = blocker.blocks.iterator();
        while (iter.next()) |entry| {
            const size = entry.value_ptr.record_ids.items.len;
            metrics.total_blocks += 1;
            metrics.total_records += size;

            if (size > self.max_block_size) {
                metrics.oversized_blocks += 1;
                metrics.records_in_oversized += size;
            }

            if (size > metrics.max_block_size) {
                metrics.max_block_size = size;
            }

            if (metrics.min_block_size == 0 or size < metrics.min_block_size) {
                metrics.min_block_size = size;
            }
        }

        if (metrics.total_blocks > 0) {
            metrics.avg_block_size = @as(f64, @floatFromInt(metrics.total_records)) / @as(f64, @floatFromInt(metrics.total_blocks));
        }

        return metrics;
    }

    pub fn shouldUseFallback(self: *const SkewHandler, blocker: *const Blocker) bool {
        var iter = blocker.blocks.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.record_ids.items.len > self.max_block_size) {
                return true;
            }
        }
        return false;
    }

    pub fn fromConfig(allocator: Allocator, config: *const types.BlockingPass) SkewHandler {
        var fallback_keys: ?[][]const u8 = null;

        if (config.fallback_keys) |keys| {
            var copied = allocator.alloc([]const u8, keys.len) catch return init(allocator, config.max_block_size, null);
            var success = true;
            for (keys, 0..) |key, i| {
                copied[i] = allocator.dupe(u8, key) catch {
                    success = false;
                    break;
                };
            }
            if (success) {
                fallback_keys = copied;
            } else {
                for (copied[0..@min(keys.len, copied.len)]) |k| {
                    if (k.len > 0) allocator.free(k);
                }
                allocator.free(copied);
            }
        }

        return init(allocator, config.max_block_size, fallback_keys);
    }
};

pub const SkewMetrics = struct {
    total_blocks: usize = 0,
    total_records: usize = 0,
    oversized_blocks: usize = 0,
    records_in_oversized: usize = 0,
    max_block_size: usize = 0,
    min_block_size: usize = 0,
    avg_block_size: f64 = 0,
};

test "SkewHandler needsFallback" {
    const allocator = std.testing.allocator;
    var handler = SkewHandler.init(allocator, 10, null);

    var block = Block.init(allocator, 12345);
    defer block.deinit();

    try block.record_ids.appendSlice(&[_]u32{ 1, 2, 3, 4, 5 });
    try std.testing.expect(!handler.needsFallback(&block));

    for (6..15) |i| {
        try block.record_ids.append(@intCast(i));
    }
    try std.testing.expect(handler.needsFallback(&block));
}

test "SkewHandler from config" {
    const allocator = std.testing.allocator;
    const config = types.BlockingPass{
        .keys = @constCast(&[_][]const u8{"name"}),
        .max_block_size = 500,
        .fallback_logic = "secondary",
    };

    var handler = SkewHandler.fromConfig(allocator, &config);
    defer handler.deinit();

    try std.testing.expectEqual(@as(u32, 500), handler.max_block_size);
}
