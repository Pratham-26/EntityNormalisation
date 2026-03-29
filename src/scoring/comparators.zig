const std = @import("std");
const types = @import("../config/types.zig");

pub const CompareResult = struct {
    score: f64,
    is_null: bool,
};

pub const Value = union(enum) {
    str: []const u8,
    int: i64,
    float: f64,
    cat: u32,
    date: i64,
    null_val: void,
};

fn handleNullLogic(params: *const types.ComparisonParams, both_null: bool) CompareResult {
    return switch (params.null_logic) {
        .ignore => .{ .score = 0.0, .is_null = true },
        .penalize => .{ .score = 0.0, .is_null = false },
        .neutral => .{ .score = 0.5, .is_null = false },
        .conditional => if (both_null)
            .{ .score = 0.0, .is_null = false }
        else
            .{ .score = 0.5, .is_null = false },
    };
}

fn isNullOrEmpty(str: []const u8) bool {
    return str.len == 0;
}

fn toLowerChar(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') {
        return c + 32;
    }
    return c;
}

fn stringsEqualCaseInsensitive(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (toLowerChar(ca) != toLowerChar(cb)) return false;
    }
    return true;
}

pub fn exact(a: []const u8, b: []const u8, params: *const types.ComparisonParams) CompareResult {
    const a_null = isNullOrEmpty(a);
    const b_null = isNullOrEmpty(b);

    if (a_null or b_null) {
        return handleNullLogic(params, a_null and b_null);
    }

    const equal = if (params.case_sensitive)
        std.mem.eql(u8, a, b)
    else
        stringsEqualCaseInsensitive(a, b);

    return .{ .score = if (equal) 1.0 else 0.0, .is_null = false };
}

pub fn levenshtein(a: []const u8, b: []const u8, params: *const types.ComparisonParams) CompareResult {
    const a_null = isNullOrEmpty(a);
    const b_null = isNullOrEmpty(b);

    if (a_null or b_null) {
        return handleNullLogic(params, a_null and b_null);
    }

    const distance = computeLevenshteinDistance(a, b);
    const max_len = @max(a.len, b.len);

    if (max_len == 0) {
        return .{ .score = 1.0, .is_null = false };
    }

    const similarity = 1.0 - (@as(f64, @floatFromInt(distance)) / @as(f64, @floatFromInt(max_len)));
    const threshold = params.threshold orelse 0.0;

    return .{ .score = if (similarity >= threshold) 1.0 else similarity, .is_null = false };
}

fn computeLevenshteinDistance(a: []const u8, b: []const u8) usize {
    const m = a.len;
    const n = b.len;

    if (m == 0) return n;
    if (n == 0) return m;

    var prev_row: [256]usize = undefined;
    var curr_row: [256]usize = undefined;

    if (n + 1 > prev_row.len) {
        var i: usize = 0;
        while (i <= n) : (i += 1) {
            prev_row[0] = i;
        }
    }

    for (0..n + 1) |j| {
        prev_row[j] = j;
    }

    for (0..m) |i| {
        curr_row[0] = i + 1;

        for (0..n) |j| {
            const cost: usize = if (a[i] == b[j]) 0 else 1;
            curr_row[j + 1] = @min(
                @min(prev_row[j + 1] + 1, curr_row[j] + 1),
                prev_row[j] + cost,
            );
        }

        for (0..n + 1) |j| {
            prev_row[j] = curr_row[j];
        }
    }

    return prev_row[n];
}

pub fn jaroWinkler(a: []const u8, b: []const u8, params: *const types.ComparisonParams) CompareResult {
    const a_null = isNullOrEmpty(a);
    const b_null = isNullOrEmpty(b);

    if (a_null or b_null) {
        return handleNullLogic(params, a_null and b_null);
    }

    const similarity = computeJaroWinkler(a, b, params);
    const threshold = params.threshold orelse 0.0;

    return .{ .score = if (similarity >= threshold) 1.0 else similarity, .is_null = false };
}

fn computeJaroWinkler(a: []const u8, b: []const u8, params: *const types.ComparisonParams) f64 {
    const jaro_sim = computeJaro(a, b);

    if (jaro_sim == 0.0) return 0.0;

    const prefix_len = commonPrefixLength(a, b);
    const prefix_weight = params.prefix_weight orelse 0.1;

    const winkler_adjustment = @as(f64, @floatFromInt(@min(prefix_len, 4))) * prefix_weight;

    return @min(1.0, jaro_sim + winkler_adjustment * (1.0 - jaro_sim));
}

fn computeJaro(a: []const u8, b: []const u8) f64 {
    const len_a = a.len;
    const len_b = b.len;

    if (len_a == 0 and len_b == 0) return 1.0;
    if (len_a == 0 or len_b == 0) return 0.0;

    const match_distance = @max(len_a, len_b) / 2 - 1;
    var a_matched: [256]bool = @splat(false);
    var b_matched: [256]bool = @splat(false);

    var matches: usize = 0;
    var transpositions: usize = 0;

    for (0..len_a) |i| {
        const start = if (i > match_distance) i - match_distance else 0;
        const end = @min(i + match_distance + 1, len_b);

        var j: usize = start;
        while (j < end) : (j += 1) {
            if (b_matched[j] or a[i] != b[j]) continue;
            a_matched[i] = true;
            b_matched[j] = true;
            matches += 1;
            break;
        }
    }

    if (matches == 0) return 0.0;

    var k: usize = 0;
    for (0..len_a) |i| {
        if (!a_matched[i]) continue;
        while (!b_matched[k]) : (k += 1) {}
        if (a[i] != b[k]) transpositions += 1;
        k += 1;
    }

    const m_f64 = @as(f64, @floatFromInt(matches));
    const t_f64 = @as(f64, @floatFromInt(transpositions)) / 2.0;

    return (m_f64 / @as(f64, @floatFromInt(len_a)) +
        m_f64 / @as(f64, @floatFromInt(len_b)) +
        (m_f64 - t_f64) / m_f64) / 3.0;
}

fn commonPrefixLength(a: []const u8, b: []const u8) usize {
    const min_len = @min(a.len, b.len);
    var i: usize = 0;
    while (i < min_len and a[i] == b[i]) : (i += 1) {}
    return i;
}

pub fn dateCompare(a: i64, b: i64, params: *const types.ComparisonParams) CompareResult {
    const a_null = (a == 0);
    const b_null = (b == 0);

    if (a_null or b_null) {
        return handleNullLogic(params, a_null and b_null);
    }

    const diff = @abs(a - b);
    const tolerance = params.tolerance_days orelse 0;

    return .{ .score = if (diff <= tolerance) 1.0 else 0.0, .is_null = false };
}

pub fn categorical(a: u32, b: u32, params: *const types.ComparisonParams) CompareResult {
    const a_null = (a == 0);
    const b_null = (b == 0);

    if (a_null or b_null) {
        return handleNullLogic(params, a_null and b_null);
    }

    return .{ .score = if (a == b) 1.0 else 0.0, .is_null = false };
}

pub fn compare(
    a_val: Value,
    b_val: Value,
    logic: types.ComparisonLogic,
    params: *const types.ComparisonParams,
) CompareResult {
    switch (logic) {
        .exact => {
            const a_str = switch (a_val) {
                .str => |s| s,
                else => "",
            };
            const b_str = switch (b_val) {
                .str => |s| s,
                else => "",
            };
            return exact(a_str, b_str, params);
        },
        .levenshtein => {
            const a_str = switch (a_val) {
                .str => |s| s,
                else => "",
            };
            const b_str = switch (b_val) {
                .str => |s| s,
                else => "",
            };
            return levenshtein(a_str, b_str, params);
        },
        .jaro_winkler => {
            const a_str = switch (a_val) {
                .str => |s| s,
                else => "",
            };
            const b_str = switch (b_val) {
                .str => |s| s,
                else => "",
            };
            return jaroWinkler(a_str, b_str, params);
        },
        .date => {
            const a_date = switch (a_val) {
                .date => |d| d,
                .int => |i| i,
                else => 0,
            };
            const b_date = switch (b_val) {
                .date => |d| d,
                .int => |i| i,
                else => 0,
            };
            return dateCompare(a_date, b_date, params);
        },
        .categorical => {
            const a_cat: u32 = switch (a_val) {
                .cat => |c| c,
                .int => |i| @intCast(i),
                else => 0,
            };
            const b_cat: u32 = switch (b_val) {
                .cat => |c| c,
                .int => |i| @intCast(i),
                else => 0,
            };
            return categorical(a_cat, b_cat, params);
        },
    }
}

test "exact comparison" {
    const params = types.ComparisonParams{ .case_sensitive = true };
    const result = exact("hello", "hello", &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
    try std.testing.expectEqual(false, result.is_null);
}

test "exact comparison case insensitive" {
    const params = types.ComparisonParams{ .case_sensitive = false };
    const result = exact("Hello", "HELLO", &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}

test "exact comparison no match" {
    const params = types.ComparisonParams{ .case_sensitive = true };
    const result = exact("hello", "world", &params);
    try std.testing.expectEqual(@as(f64, 0.0), result.score);
}

test "exact comparison with null" {
    const params = types.ComparisonParams{ .null_logic = .neutral };
    const result = exact("", "hello", &params);
    try std.testing.expectEqual(@as(f64, 0.5), result.score);
    try std.testing.expectEqual(false, result.is_null);
}

test "levenshtein identical strings" {
    const params = types.ComparisonParams{};
    const result = levenshtein("kitten", "kitten", &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}

test "levenshtein one edit" {
    const params = types.ComparisonParams{ .threshold = 0.7 };
    const result = levenshtein("kitten", "kitten", &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}

test "jaro winkler identical" {
    const params = types.ComparisonParams{};
    const result = jaroWinkler("martha", "martha", &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}

test "jaro winkler similar" {
    const params = types.ComparisonParams{};
    const result = jaroWinkler("martha", "marhta", &params);
    try std.testing.expect(result.score > 0.8);
}

test "date comparison within tolerance" {
    const params = types.ComparisonParams{ .tolerance_days = 5 };
    const result = dateCompare(100, 103, &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}

test "date comparison outside tolerance" {
    const params = types.ComparisonParams{ .tolerance_days = 2 };
    const result = dateCompare(100, 110, &params);
    try std.testing.expectEqual(@as(f64, 0.0), result.score);
}

test "categorical match" {
    const params = types.ComparisonParams{};
    const result = categorical(5, 5, &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}

test "categorical no match" {
    const params = types.ComparisonParams{};
    const result = categorical(5, 10, &params);
    try std.testing.expectEqual(@as(f64, 0.0), result.score);
}

test "compare function exact" {
    const params = types.ComparisonParams{ .case_sensitive = true };
    const a = Value{ .str = "test" };
    const b = Value{ .str = "test" };
    const result = compare(a, b, .exact, &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}

test "compare function categorical" {
    const params = types.ComparisonParams{};
    const a = Value{ .cat = 42 };
    const b = Value{ .cat = 42 };
    const result = compare(a, b, .categorical, &params);
    try std.testing.expectEqual(@as(f64, 1.0), result.score);
}
