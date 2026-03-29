const std = @import("std");
const Allocator = std.mem.Allocator;
const hash = @import("../utils/hash.zig");

pub const FrequencyTable = struct {
    counts: std.HashMap(u64, usize, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    total_values: usize,

    pub fn init(allocator: Allocator) FrequencyTable {
        return .{
            .counts = std.HashMap(u64, usize, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .total_values = 0,
        };
    }

    pub fn deinit(self: *FrequencyTable) void {
        self.counts.deinit();
    }

    pub fn addValue(self: *FrequencyTable, value: []const u8) !void {
        const h = hash.fnv1a(value);
        const gop = try self.counts.getOrPut(h);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.value_ptr.* = 1;
        }
        self.total_values += 1;
    }

    pub fn addValueHash(self: *FrequencyTable, value_hash: u64) !void {
        const gop = try self.counts.getOrPut(value_hash);
        if (gop.found_existing) {
            gop.value_ptr.* += 1;
        } else {
            gop.value_ptr.* = 1;
        }
        self.total_values += 1;
    }

    pub fn getFrequency(self: *const FrequencyTable, value: []const u8) f64 {
        const h = hash.fnv1a(value);
        return self.getFrequencyHash(h);
    }

    pub fn getFrequencyHash(self: *const FrequencyTable, value_hash: u64) f64 {
        if (self.total_values == 0) return 1.0;
        const count = self.counts.get(value_hash) orelse 1;
        return @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(self.total_values));
    }

    pub fn getCount(self: *const FrequencyTable, value: []const u8) usize {
        const h = hash.fnv1a(value);
        return self.counts.get(h) orelse 0;
    }

    pub fn computeInformativeness(self: *const FrequencyTable, value: []const u8) f64 {
        const freq = self.getFrequency(value);
        if (freq <= 0.0) return 0.0;
        return -@log2(freq);
    }

    pub fn computeInformativenessHash(self: *const FrequencyTable, value_hash: u64) f64 {
        const freq = self.getFrequencyHash(value_hash);
        if (freq <= 0.0) return 0.0;
        return -@log2(freq);
    }

    pub fn getMinInformativeness(self: *const FrequencyTable) f64 {
        if (self.total_values == 0) return 0.0;
        const max_freq = 1.0;
        return -@log2(max_freq);
    }

    pub fn getMaxInformativeness(self: *const FrequencyTable) f64 {
        if (self.total_values == 0) return 0.0;
        const min_freq = 1.0 / @as(f64, @floatFromInt(self.total_values));
        return -@log2(min_freq);
    }
};

pub fn adjustWeightForFrequency(
    base_weight: f64,
    value: []const u8,
    freq_table: *const FrequencyTable,
) f64 {
    return adjustWeightForFrequencyAlpha(base_weight, value, freq_table, 0.3);
}

pub fn adjustWeightForFrequencyAlpha(
    base_weight: f64,
    value: []const u8,
    freq_table: *const FrequencyTable,
    alpha: f64,
) f64 {
    if (value.len == 0) return base_weight;
    const informativeness = freq_table.computeInformativeness(value);
    return base_weight * (1.0 + alpha * informativeness);
}

pub fn adjustWeightForFrequencyHash(
    base_weight: f64,
    value_hash: u64,
    freq_table: *const FrequencyTable,
) f64 {
    return adjustWeightForFrequencyHashAlpha(base_weight, value_hash, freq_table, 0.3);
}

pub fn adjustWeightForFrequencyHashAlpha(
    base_weight: f64,
    value_hash: u64,
    freq_table: *const FrequencyTable,
    alpha: f64,
) f64 {
    const informativeness = freq_table.computeInformativenessHash(value_hash);
    return base_weight * (1.0 + alpha * informativeness);
}

test "FrequencyTable add and get frequency" {
    const allocator = std.testing.allocator;
    var table = FrequencyTable.init(allocator);
    defer table.deinit();

    try table.addValue("john");
    try table.addValue("john");
    try table.addValue("jane");

    const freq_john = table.getFrequency("john");
    try std.testing.expectApproxEqAbs(2.0 / 3.0, freq_john, 0.0001);

    const freq_jane = table.getFrequency("jane");
    try std.testing.expectApproxEqAbs(1.0 / 3.0, freq_jane, 0.0001);
}

test "FrequencyTable compute informativeness" {
    const allocator = std.testing.allocator;
    var table = FrequencyTable.init(allocator);
    defer table.deinit();

    try table.addValue("unique");

    const info = table.computeInformativeness("unique");
    try std.testing.expectApproxEqAbs(0.0, info, 0.0001);
}

test "FrequencyTable informativeness for rare value" {
    const allocator = std.testing.allocator;
    var table = FrequencyTable.init(allocator);
    defer table.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try table.addValue("common");
    }
    try table.addValue("rare");

    const info_rare = table.computeInformativeness("rare");
    const info_common = table.computeInformativeness("common");

    try std.testing.expect(info_rare > info_common);
}

test "adjustWeightForFrequency boosts rare values" {
    const allocator = std.testing.allocator;
    var table = FrequencyTable.init(allocator);
    defer table.deinit();

    try table.addValue("common");
    try table.addValue("common");
    try table.addValue("rare");

    const base_weight = 5.0;
    const adjusted_common = adjustWeightForFrequency(base_weight, "common", &table);
    const adjusted_rare = adjustWeightForFrequency(base_weight, "rare", &table);

    try std.testing.expect(adjusted_rare > adjusted_common);
    try std.testing.expect(adjusted_common > base_weight);
}

test "adjustWeightForFrequency handles empty value" {
    const allocator = std.testing.allocator;
    var table = FrequencyTable.init(allocator);
    defer table.deinit();

    try table.addValue("test");

    const base_weight = 5.0;
    const adjusted = adjustWeightForFrequency(base_weight, "", &table);

    try std.testing.expectEqual(base_weight, adjusted);
}
