const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EMParams = struct {
    m_probs: []f64,
    u_probs: []f64,
    field_names: [][]const u8,

    pub fn init(allocator: Allocator, num_fields: usize) !EMParams {
        const m_probs = try allocator.alloc(f64, num_fields);
        const u_probs = try allocator.alloc(f64, num_fields);
        const field_names = try allocator.alloc([]const u8, num_fields);

        @memset(m_probs, 0.9);
        @memset(u_probs, 0.05);
        @memset(field_names, "");

        return .{
            .m_probs = m_probs,
            .u_probs = u_probs,
            .field_names = field_names,
        };
    }

    pub fn deinit(self: *EMParams, allocator: Allocator) void {
        allocator.free(self.m_probs);
        allocator.free(self.u_probs);
        for (self.field_names) |name| {
            allocator.free(name);
        }
        allocator.free(self.field_names);
    }
};

pub const WeightTable = struct {
    match_weights: []f64,
    unmatch_weights: []f64,
    field_names: [][]const u8,

    pub fn init(allocator: Allocator, params: *const EMParams) !WeightTable {
        const num_fields = params.m_probs.len;
        const match_weights = try allocator.alloc(f64, num_fields);
        const unmatch_weights = try allocator.alloc(f64, num_fields);
        const field_names = try allocator.alloc([]const u8, num_fields);

        for (0..num_fields) |i| {
            const m = params.m_probs[i];
            const u = params.u_probs[i];

            const u_safe = if (u < 1e-10) 1e-10 else u;
            const m_safe = if (m < 1e-10) 1e-10 else m;
            const one_minus_m = 1.0 - m_safe;
            const one_minus_u = 1.0 - u_safe;
            const one_minus_u_safe = if (one_minus_u < 1e-10) 1e-10 else one_minus_u;
            const one_minus_m_safe = if (one_minus_m < 1e-10) 1e-10 else one_minus_m;

            match_weights[i] = @log2(m_safe / u_safe);
            unmatch_weights[i] = @log2(one_minus_m_safe / one_minus_u_safe);

            const owned_name = try allocator.dupe(u8, params.field_names[i]);
            field_names[i] = owned_name;
        }

        return .{
            .match_weights = match_weights,
            .unmatch_weights = unmatch_weights,
            .field_names = field_names,
        };
    }

    pub fn deinit(self: *WeightTable, allocator: Allocator) void {
        allocator.free(self.match_weights);
        allocator.free(self.unmatch_weights);
        for (self.field_names) |name| {
            allocator.free(name);
        }
        allocator.free(self.field_names);
    }

    pub fn getMatchWeight(self: *const WeightTable, field_idx: usize) f64 {
        if (field_idx >= self.match_weights.len) return 0.0;
        return self.match_weights[field_idx];
    }

    pub fn getUnmatchWeight(self: *const WeightTable, field_idx: usize) f64 {
        if (field_idx >= self.unmatch_weights.len) return 0.0;
        return self.unmatch_weights[field_idx];
    }
};

pub const PairScore = struct {
    left_id: u32,
    right_id: u32,
    total_weight: f64,
    field_weights: []f64,

    pub fn deinit(self: *PairScore, allocator: Allocator) void {
        allocator.free(self.field_weights);
    }
};

pub fn scorePair(
    gamma: []const u8,
    weights: *const WeightTable,
) f64 {
    var total: f64 = 0.0;
    const num_fields = @min(gamma.len, weights.match_weights.len);

    for (0..num_fields) |i| {
        const g = gamma[i];
        if (g == 1) {
            total += weights.match_weights[i];
        } else if (g == 0) {
            total += weights.unmatch_weights[i];
        }
    }

    return total;
}

pub fn scorePairDetailed(
    gamma: []const u8,
    weights: *const WeightTable,
    allocator: Allocator,
) !PairScore {
    const num_fields = @min(gamma.len, weights.match_weights.len);
    const field_weights = try allocator.alloc(f64, num_fields);

    var total: f64 = 0.0;
    for (0..num_fields) |i| {
        const g = gamma[i];
        if (g == 1) {
            field_weights[i] = weights.match_weights[i];
        } else if (g == 0) {
            field_weights[i] = weights.unmatch_weights[i];
        } else {
            field_weights[i] = 0.0;
        }
        total += field_weights[i];
    }

    return .{
        .left_id = 0,
        .right_id = 0,
        .total_weight = total,
        .field_weights = field_weights,
    };
}

test "WeightTable init and get weights" {
    const allocator = std.testing.allocator;

    var params = try EMParams.init(allocator, 3);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.field_names[0] = try allocator.dupe(u8, "name");

    var weights = try WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    const match_w = weights.getMatchWeight(0);
    const expected = @log2(0.9 / 0.1);
    try std.testing.expectApproxEqAbs(expected, match_w, 0.0001);
}

test "scorePair with agreement" {
    const allocator = std.testing.allocator;

    var params = try EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    const gamma = [_]u8{ 1, 1 };
    const score = scorePair(&gamma, &weights);

    const expected = @log2(0.9 / 0.1) + @log2(0.8 / 0.2);
    try std.testing.expectApproxEqAbs(expected, score, 0.0001);
}

test "scorePair with mixed agreement" {
    const allocator = std.testing.allocator;

    var params = try EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    const gamma = [_]u8{ 1, 0 };
    const score = scorePair(&gamma, &weights);

    const expected = @log2(0.9 / 0.1) + @log2(0.2 / 0.8);
    try std.testing.expectApproxEqAbs(expected, score, 0.0001);
}

test "scorePairDetailed" {
    const allocator = std.testing.allocator;

    var params = try EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    const gamma = [_]u8{ 1, 0 };
    var result = try scorePairDetailed(&gamma, &weights, allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.field_weights.len);
    try std.testing.expectApproxEqAbs(@log2(0.9 / 0.1), result.field_weights[0], 0.0001);
    try std.testing.expectApproxEqAbs(@log2(0.2 / 0.8), result.field_weights[1], 0.0001);
}
