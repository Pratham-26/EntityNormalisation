const std = @import("std");
const Allocator = std.mem.Allocator;
const fellegi_sunter = @import("fellegi_sunter.zig");

pub const PairBatch = struct {
    left_ids: []u32,
    right_ids: []u32,
    gammas: [][]u8,
    scores: []f64,

    pub fn init(allocator: Allocator, batch_size: usize, num_fields: usize) !PairBatch {
        const left_ids = try allocator.alloc(u32, batch_size);
        const right_ids = try allocator.alloc(u32, batch_size);
        const gammas = try allocator.alloc([]u8, batch_size);
        const scores = try allocator.alloc(f64, batch_size);

        @memset(left_ids, 0);
        @memset(right_ids, 0);
        @memset(scores, 0.0);

        for (0..batch_size) |i| {
            gammas[i] = try allocator.alloc(u8, num_fields);
            @memset(gammas[i], 2);
        }

        return .{
            .left_ids = left_ids,
            .right_ids = right_ids,
            .gammas = gammas,
            .scores = scores,
        };
    }

    pub fn deinit(self: *PairBatch, allocator: Allocator) void {
        allocator.free(self.left_ids);
        allocator.free(self.right_ids);
        for (self.gammas) |gamma| {
            allocator.free(gamma);
        }
        allocator.free(self.gammas);
        allocator.free(self.scores);
    }

    pub fn size(self: *const PairBatch) usize {
        return self.left_ids.len;
    }
};

pub fn scoreBatchSIMD(
    batch: *PairBatch,
    weights: *const fellegi_sunter.WeightTable,
    allocator: Allocator,
) !void {
    const batch_size = batch.size();
    const remainder = batch_size % 8;
    const simd_batches = (batch_size - remainder) / 8;

    for (0..simd_batches) |b| {
        const start = b * 8;
        var gammas_arr: [8][]const u8 = undefined;
        for (0..8) |j| {
            gammas_arr[j] = batch.gammas[start + j];
        }
        const results = score8Pairs(gammas_arr, weights);
        for (0..8) |j| {
            batch.scores[start + j] = results[j];
        }
    }

    const remainder_start = simd_batches * 8;
    if (remainder > 0) {
        var gammas_arr: [8][]const u8 = undefined;
        var valid_mask: @Vector(8, bool) = @splat(false);
        for (0..remainder) |j| {
            gammas_arr[j] = batch.gammas[remainder_start + j];
            valid_mask[j] = true;
        }
        for (remainder..8) |j| {
            gammas_arr[j] = &[_]u8{};
        }
        const results = score8Pairs(gammas_arr, weights);
        for (0..remainder) |j| {
            if (valid_mask[j]) {
                batch.scores[remainder_start + j] = results[j];
            }
        }
    }

    _ = allocator;
}

pub fn score8Pairs(
    gammas: [8][]const u8,
    weights: *const fellegi_sunter.WeightTable,
) @Vector(8, f64) {
    var totals: @Vector(8, f64) = @splat(0.0);

    const num_fields = if (gammas[0].len > 0) gammas[0].len else 0;
    if (num_fields == 0) return totals;

    const effective_fields = @min(num_fields, weights.match_weights.len);

    for (0..effective_fields) |field_idx| {
        var gamma_vals: @Vector(8, u8) = @splat(2);

        inline for (0..8) |i| {
            if (field_idx < gammas[i].len) {
                gamma_vals[i] = gammas[i][field_idx];
            }
        }

        const match_weight = weights.match_weights[field_idx];
        const unmatch_weight = weights.unmatch_weights[field_idx];

        const match_vec: @Vector(8, f64) = @splat(match_weight);
        const unmatch_vec: @Vector(8, f64) = @splat(unmatch_weight);
        const zero_vec: @Vector(8, f64) = @splat(0.0);

        const is_match = gamma_vals == @as(@Vector(8, u8), @splat(@as(u8, 1)));
        const is_unmatch = gamma_vals == @as(@Vector(8, u8), @splat(@as(u8, 0)));

        const match_contrib: @Vector(8, f64) = @select(f64, is_match, match_vec, zero_vec);
        const unmatch_contrib: @Vector(8, f64) = @select(f64, is_unmatch, unmatch_vec, zero_vec);

        totals = totals + match_contrib + unmatch_contrib;
    }

    return totals;
}

pub fn score4Pairs(
    gammas: [4][]const u8,
    weights: *const fellegi_sunter.WeightTable,
) @Vector(4, f64) {
    var totals: @Vector(4, f64) = @splat(0.0);

    const num_fields = if (gammas[0].len > 0) gammas[0].len else 0;
    if (num_fields == 0) return totals;

    const effective_fields = @min(num_fields, weights.match_weights.len);

    for (0..effective_fields) |field_idx| {
        var gamma_vals: @Vector(4, u8) = @splat(2);

        inline for (0..4) |i| {
            if (field_idx < gammas[i].len) {
                gamma_vals[i] = gammas[i][field_idx];
            }
        }

        const match_weight = weights.match_weights[field_idx];
        const unmatch_weight = weights.unmatch_weights[field_idx];

        const match_vec: @Vector(4, f64) = @splat(match_weight);
        const unmatch_vec: @Vector(4, f64) = @splat(unmatch_weight);
        const zero_vec: @Vector(4, f64) = @splat(0.0);

        const is_match = gamma_vals == @as(@Vector(4, u8), @splat(@as(u8, 1)));
        const is_unmatch = gamma_vals == @as(@Vector(4, u8), @splat(@as(u8, 0)));

        const match_contrib: @Vector(4, f64) = @select(f64, is_match, match_vec, zero_vec);
        const unmatch_contrib: @Vector(4, f64) = @select(f64, is_unmatch, unmatch_vec, zero_vec);

        totals = totals + match_contrib + unmatch_contrib;
    }

    return totals;
}

pub fn scoreBatchScalar(
    batch: *PairBatch,
    weights: *const fellegi_sunter.WeightTable,
) void {
    for (0..batch.size()) |i| {
        batch.scores[i] = fellegi_sunter.scorePair(batch.gammas[i], weights);
    }
}

test "score8Pairs basic" {
    const allocator = std.testing.allocator;

    var params = try fellegi_sunter.EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try fellegi_sunter.WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    var gammas: [8][]const u8 = undefined;
    var gamma_storage: [8][2]u8 = undefined;

    for (0..8) |i| {
        gamma_storage[i] = [_]u8{ 1, 1 };
        gammas[i] = &gamma_storage[i];
    }

    const results = score8Pairs(gammas, &weights);

    const expected = @log2(0.9 / 0.1) + @log2(0.8 / 0.2);
    for (0..8) |i| {
        try std.testing.expectApproxEqAbs(expected, results[i], 0.0001);
    }
}

test "score8Pairs mixed patterns" {
    const allocator = std.testing.allocator;

    var params = try fellegi_sunter.EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try fellegi_sunter.WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    var gammas: [8][]const u8 = undefined;
    var gamma_storage: [8][2]u8 = undefined;

    gamma_storage[0] = [_]u8{ 1, 1 };
    gamma_storage[1] = [_]u8{ 0, 0 };
    gamma_storage[2] = [_]u8{ 1, 0 };
    gamma_storage[3] = [_]u8{ 0, 1 };
    gamma_storage[4] = [_]u8{ 2, 1 };
    gamma_storage[5] = [_]u8{ 1, 2 };
    gamma_storage[6] = [_]u8{ 2, 2 };
    gamma_storage[7] = [_]u8{ 0, 0 };

    for (0..8) |i| {
        gammas[i] = &gamma_storage[i];
    }

    const results = score8Pairs(gammas, &weights);

    const expected_match_match = @log2(0.9 / 0.1) + @log2(0.8 / 0.2);
    const expected_unmatch_unmatch = @log2(0.1 / 0.9) + @log2(0.2 / 0.8);
    const expected_match_unmatch = @log2(0.9 / 0.1) + @log2(0.2 / 0.8);
    const expected_unmatch_match = @log2(0.1 / 0.9) + @log2(0.8 / 0.2);
    const expected_missing_match = @log2(0.8 / 0.2);
    const expected_match_missing = @log2(0.9 / 0.1);
    const expected_missing_missing = 0.0;

    try std.testing.expectApproxEqAbs(expected_match_match, results[0], 0.0001);
    try std.testing.expectApproxEqAbs(expected_unmatch_unmatch, results[1], 0.0001);
    try std.testing.expectApproxEqAbs(expected_match_unmatch, results[2], 0.0001);
    try std.testing.expectApproxEqAbs(expected_unmatch_match, results[3], 0.0001);
    try std.testing.expectApproxEqAbs(expected_missing_match, results[4], 0.0001);
    try std.testing.expectApproxEqAbs(expected_match_missing, results[5], 0.0001);
    try std.testing.expectApproxEqAbs(expected_missing_missing, results[6], 0.0001);
    try std.testing.expectApproxEqAbs(expected_unmatch_unmatch, results[7], 0.0001);
}

test "PairBatch init and deinit" {
    const allocator = std.testing.allocator;

    var batch = try PairBatch.init(allocator, 16, 3);
    defer batch.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 16), batch.size());
    try std.testing.expectEqual(@as(usize, 16), batch.gammas.len);
    try std.testing.expectEqual(@as(usize, 3), batch.gammas[0].len);
}

test "scoreBatchSIMD" {
    const allocator = std.testing.allocator;

    var params = try fellegi_sunter.EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try fellegi_sunter.WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    var batch = try PairBatch.init(allocator, 16, 2);
    defer batch.deinit(allocator);

    for (0..16) |i| {
        batch.gammas[i][0] = 1;
        batch.gammas[i][1] = 1;
    }

    try scoreBatchSIMD(&batch, &weights, allocator);

    const expected = @log2(0.9 / 0.1) + @log2(0.8 / 0.2);
    for (0..16) |i| {
        try std.testing.expectApproxEqAbs(expected, batch.scores[i], 0.0001);
    }
}

test "scoreBatchSIMD with non-multiple of 8" {
    const allocator = std.testing.allocator;

    var params = try fellegi_sunter.EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try fellegi_sunter.WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    var batch = try PairBatch.init(allocator, 13, 2);
    defer batch.deinit(allocator);

    for (0..13) |i| {
        batch.gammas[i][0] = 1;
        batch.gammas[i][1] = 0;
    }

    try scoreBatchSIMD(&batch, &weights, allocator);

    const expected = @log2(0.9 / 0.1) + @log2(0.2 / 0.8);
    for (0..13) |i| {
        try std.testing.expectApproxEqAbs(expected, batch.scores[i], 0.0001);
    }
}

test "score4Pairs basic" {
    const allocator = std.testing.allocator;

    var params = try fellegi_sunter.EMParams.init(allocator, 2);
    defer params.deinit(allocator);

    params.m_probs[0] = 0.9;
    params.u_probs[0] = 0.1;
    params.m_probs[1] = 0.8;
    params.u_probs[1] = 0.2;

    var weights = try fellegi_sunter.WeightTable.init(allocator, &params);
    defer weights.deinit(allocator);

    var gammas: [4][]const u8 = undefined;
    var gamma_storage: [4][2]u8 = undefined;

    for (0..4) |i| {
        gamma_storage[i] = [_]u8{ 1, 1 };
        gammas[i] = &gamma_storage[i];
    }

    const results = score4Pairs(gammas, &weights);

    const expected = @log2(0.9 / 0.1) + @log2(0.8 / 0.2);
    for (0..4) |i| {
        try std.testing.expectApproxEqAbs(expected, results[i], 0.0001);
    }
}
