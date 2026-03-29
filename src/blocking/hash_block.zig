const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../config/types.zig");
const hash = @import("../utils/hash.zig");
const transforms = @import("transforms.zig");

pub const Block = struct {
    hash: u64,
    record_ids: std.ArrayList(u32),
    fallback_applied: bool = false,

    pub fn init(allocator: Allocator, h: u64) Block {
        return .{
            .hash = h,
            .record_ids = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Block) void {
        self.record_ids.deinit();
    }
};

pub const BlockMap = std.HashMap(u64, Block, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage);

pub const Blocker = struct {
    blocks: BlockMap,
    config: *const types.BlockingPass,
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: *const types.BlockingPass) Blocker {
        return .{
            .blocks = BlockMap.init(allocator),
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Blocker) void {
        var iter = self.blocks.iterator();
        while (iter.next()) |entry| {
            var block = entry.value_ptr;
            block.deinit();
        }
        self.blocks.deinit();
    }

    pub fn addRecord(self: *Blocker, record_id: u32, values: []const []const u8) !void {
        if (values.len == 0) return;

        var combined = std.ArrayList(u8).init(self.allocator);
        defer combined.deinit();

        for (values, 0..) |val, i| {
            if (i > 0) {
                try combined.append('\x00');
            }
            try combined.appendSlice(val);
        }

        const block_hash = hash.xxHash64(combined.items);

        const entry = try self.blocks.getOrPut(block_hash);
        if (!entry.found_existing) {
            entry.value_ptr.* = Block.init(self.allocator, block_hash);
        }
        try entry.value_ptr.record_ids.append(record_id);
    }

    pub fn addRecordWithTransform(self: *Blocker, record_id: u32, key_specs: []const struct { base: []const u8, transform: transforms.Transform }, row: std.StringHashMap([]const u8)) !void {
        var transformed_values = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (transformed_values.items) |val| {
                self.allocator.free(val);
            }
            transformed_values.deinit();
        }

        for (key_specs) |spec| {
            if (row.get(spec.base)) |value| {
                const transformed = try transforms.applyTransform(value, spec.transform, self.allocator);
                try transformed_values.append(transformed);
            }
        }

        if (transformed_values.items.len > 0) {
            try self.addRecord(record_id, transformed_values.items);
        }
    }

    pub fn getBlocks(self: *const Blocker) []const Block {
        const BlockSlice = struct {
            items: []const Block,

            pub fn init(map: *const BlockMap, allocator: Allocator) !@This() {
                var list = std.ArrayList(Block).init(allocator);
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    try list.append(entry.value_ptr.*);
                }
                return .{ .items = list.items };
            }
        };
        _ = BlockSlice;
        var list = std.ArrayList(Block).init(self.allocator);
        var iter = self.blocks.iterator();
        while (iter.next()) |entry| {
            try list.append(entry.value_ptr.*);
        }
        return list.items;
    }

    pub fn getBlockCount(self: *const Blocker) usize {
        return self.blocks.count();
    }

    pub fn getRecordCount(self: *const Blocker) usize {
        var count: usize = 0;
        var iter = self.blocks.iterator();
        while (iter.next()) |entry| {
            count += entry.value_ptr.record_ids.items.len;
        }
        return count;
    }

    pub fn getOversizedBlocks(self: *const Blocker, max_size: u32) []u64 {
        var list = std.ArrayList(u64).init(self.allocator);
        var iter = self.blocks.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.record_ids.items.len > max_size) {
                list.append(entry.key_ptr.*) catch {};
            }
        }
        return list.items;
    }

    pub fn getBlock(self: *const Blocker, h: u64) ?*const Block {
        return self.blocks.getPtr(h);
    }

    pub fn getBlockMut(self: *Blocker, h: u64) ?*Block {
        return self.blocks.getPtr(h);
    }

    pub fn markFallback(self: *Blocker, h: u64) void {
        if (self.blocks.getPtr(h)) |block| {
            block.fallback_applied = true;
        }
    }
};

test "Blocker basic operations" {
    const config = types.BlockingPass{
        .keys = @constCast(&[_][]const u8{"name"}),
        .max_block_size = 1000,
        .fallback_logic = "secondary",
    };

    var blocker = Blocker.init(std.testing.allocator, &config);
    defer blocker.deinit();

    try blocker.addRecord(1, &[_][]const u8{"John"});
    try blocker.addRecord(2, &[_][]const u8{"John"});
    try blocker.addRecord(3, &[_][]const u8{"Jane"});

    try std.testing.expectEqual(@as(usize, 2), blocker.getBlockCount());
}

test "Blocker oversized detection" {
    const config = types.BlockingPass{
        .keys = @constCast(&[_][]const u8{"name"}),
        .max_block_size = 2,
        .fallback_logic = "secondary",
    };

    var blocker = Blocker.init(std.testing.allocator, &config);
    defer blocker.deinit();

    try blocker.addRecord(1, &[_][]const u8{"John"});
    try blocker.addRecord(2, &[_][]const u8{"John"});
    try blocker.addRecord(3, &[_][]const u8{"John"});

    const oversized = blocker.getOversizedBlocks(2);
    try std.testing.expectEqual(@as(usize, 1), oversized.len);
}
