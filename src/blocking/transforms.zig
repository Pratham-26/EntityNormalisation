const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Transform = enum {
    none,
    prefix_3,
    prefix_4,
    soundex,
    metaphone,
    year,
    month,
};

pub fn applyTransform(value: []const u8, transform: Transform, allocator: Allocator) ![]u8 {
    if (value.len == 0) {
        return allocator.dupe(u8, "");
    }

    switch (transform) {
        .none => return allocator.dupe(u8, value),
        .prefix_3 => return applyPrefix(value, 3, allocator),
        .prefix_4 => return applyPrefix(value, 4, allocator),
        .soundex => return applySoundex(value, allocator),
        .metaphone => return applyMetaphone(value, allocator),
        .year => return extractYear(value, allocator),
        .month => return extractMonth(value, allocator),
    }
}

fn applyPrefix(value: []const u8, len: usize, allocator: Allocator) ![]u8 {
    const actual_len = @min(len, value.len);
    const result = try allocator.alloc(u8, actual_len);
    for (0..actual_len) |i| {
        result[i] = std.ascii.toUpper(value[i]);
    }
    return result;
}

fn applySoundex(value: []const u8, allocator: Allocator) ![]u8 {
    const clean = std.mem.trim(u8, value, &std.ascii.whitespace);
    if (clean.len == 0) {
        return allocator.dupe(u8, "0000");
    }

    var result = try allocator.alloc(u8, 4);
    @memset(result, '0');

    result[0] = std.ascii.toUpper(clean[0]);

    var write_idx: usize = 1;
    var prev_code: u8 = getSoundexCode(clean[0]);

    for (clean[1..]) |c| {
        if (write_idx >= 4) break;

        const upper_c = std.ascii.toUpper(c);
        if (!std.ascii.isAlphabetic(upper_c)) continue;

        const code = getSoundexCode(upper_c);
        if (code != 0 and code != prev_code) {
            result[write_idx] = '0' + code;
            write_idx += 1;
        }
        prev_code = code;
    }

    return result;
}

fn getSoundexCode(c: u8) u8 {
    return switch (std.ascii.toUpper(c)) {
        'B', 'F', 'P', 'V' => 1,
        'C', 'G', 'J', 'K', 'Q', 'S', 'X', 'Z' => 2,
        'D', 'T' => 3,
        'L' => 4,
        'M', 'N' => 5,
        'R' => 6,
        else => 0,
    };
}

fn applyMetaphone(value: []const u8, allocator: Allocator) ![]u8 {
    const clean = std.mem.trim(u8, value, &std.ascii.whitespace);
    if (clean.len == 0) {
        return allocator.dupe(u8, "");
    }

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    const len = clean.len;

    while (i < len and result.items.len < 6) {
        const c = std.ascii.toUpper(clean[i]);
        const next = if (i + 1 < len) std.ascii.toUpper(clean[i + 1]) else 0;
        const prev = if (i > 0) std.ascii.toUpper(clean[i - 1]) else 0;

        switch (c) {
            'A', 'E', 'I', 'O', 'U' => {
                if (i == 0) {
                    try result.append(c);
                }
                i += 1;
            },
            'B' => {
                if (!(i + 1 < len and next == 'B')) {
                    try result.append('B');
                }
                i += 1;
            },
            'C' => {
                if (i + 1 < len and next == 'H') {
                    try result.append('X');
                    i += 2;
                } else if (i + 1 < len and (next == 'I' or next == 'E' or next == 'Y')) {
                    try result.append('S');
                    i += 1;
                } else {
                    try result.append('K');
                    i += 1;
                }
            },
            'D' => {
                if (i + 2 < len and next == 'G' and (std.ascii.toUpper(clean[i + 2]) == 'E' or std.ascii.toUpper(clean[i + 2]) == 'Y' or std.ascii.toUpper(clean[i + 2]) == 'I')) {
                    try result.append('J');
                    i += 2;
                } else {
                    try result.append('T');
                    i += 1;
                }
            },
            'F' => {
                try result.append('F');
                i += 1;
            },
            'G' => {
                if (i + 1 < len and next == 'H') {
                    if (i + 2 < len) {
                        try result.append('F');
                    }
                    i += 2;
                } else if (i + 1 < len and (next == 'I' or next == 'E' or next == 'Y')) {
                    try result.append('J');
                    i += 1;
                } else if (!(i + 1 < len and next == 'N')) {
                    try result.append('K');
                    i += 1;
                } else {
                    i += 1;
                }
            },
            'H' => {
                if (i == 0 or std.ascii.isAlphabetic(prev)) {
                    try result.append('H');
                }
                i += 1;
            },
            'J' => {
                try result.append('J');
                i += 1;
            },
            'K' => {
                if (i == 0 or prev != 'C') {
                    try result.append('K');
                }
                i += 1;
            },
            'L' => {
                try result.append('L');
                i += 1;
            },
            'M' => {
                try result.append('M');
                i += 1;
            },
            'N' => {
                try result.append('N');
                i += 1;
            },
            'P' => {
                if (i + 1 < len and next == 'H') {
                    try result.append('F');
                    i += 2;
                } else {
                    try result.append('P');
                    i += 1;
                }
            },
            'Q' => {
                try result.append('K');
                i += 1;
            },
            'R' => {
                try result.append('R');
                i += 1;
            },
            'S' => {
                if (i + 1 < len and next == 'H') {
                    try result.append('X');
                    i += 2;
                } else if (i + 2 < len and next == 'C' and std.ascii.toUpper(clean[i + 2]) == 'H') {
                    try result.append('X');
                    i += 3;
                } else {
                    try result.append('S');
                    i += 1;
                }
            },
            'T' => {
                if (i + 1 < len and next == 'H') {
                    try result.append('0');
                    i += 2;
                } else if (i + 2 < len and next == 'I' and (std.ascii.toUpper(clean[i + 2]) == 'O' or std.ascii.toUpper(clean[i + 2]) == 'A')) {
                    try result.append('X');
                    i += 1;
                } else {
                    try result.append('T');
                    i += 1;
                }
            },
            'V' => {
                try result.append('F');
                i += 1;
            },
            'W', 'Y' => {
                if (i + 1 < len and std.ascii.isAlphabetic(next)) {
                    try result.append(c);
                }
                i += 1;
            },
            'X' => {
                try result.append('K');
                try result.append('S');
                i += 1;
            },
            'Z' => {
                try result.append('S');
                i += 1;
            },
            else => i += 1,
        }
    }

    return result.toOwnedSlice();
}

fn extractYear(value: []const u8, allocator: Allocator) ![]u8 {
    const clean = std.mem.trim(u8, value, &std.ascii.whitespace);

    if (clean.len >= 4) {
        if (std.mem.indexOf(u8, clean, "-")) |sep| {
            const year_part = clean[0..@min(sep, 4)];
            if (isDigits(year_part)) {
                return allocator.dupe(u8, year_part);
            }
        }

        if (isDigits(clean[0..4])) {
            return allocator.dupe(u8, clean[0..4]);
        }
    }

    var i: usize = 0;
    while (i + 4 <= clean.len) : (i += 1) {
        if (isDigits(clean[i .. i + 4])) {
            const year = std.fmt.parseInt(u32, clean[i .. i + 4], 10) catch continue;
            if (year >= 1900 and year <= 2100) {
                return allocator.dupe(u8, clean[i .. i + 4]);
            }
        }
    }

    return allocator.dupe(u8, "");
}

fn extractMonth(value: []const u8, allocator: Allocator) ![]u8 {
    const clean = std.mem.trim(u8, value, &std.ascii.whitespace);

    var parts = std.mem.splitAny(u8, clean, "-/");
    if (parts.next()) |first| {
        if (first.len == 4 and isDigits(first)) {
            if (parts.next()) |month| {
                if (month.len >= 2 and isDigits(month[0..2])) {
                    return allocator.dupe(u8, month[0..2]);
                }
            }
        } else if (first.len >= 1 and first.len <= 2 and isDigits(first)) {
            return allocator.dupe(u8, first);
        }
    }

    return allocator.dupe(u8, "");
}

fn isDigits(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return s.len > 0;
}

pub fn parseTransform(key_name: []const u8) struct { base: []const u8, transform: Transform } {
    const prefixes = [_]struct { []const u8, Transform }{
        .{ "prefix_3:", .prefix_3 },
        .{ "prefix_4:", .prefix_4 },
        .{ "soundex:", .soundex },
        .{ "metaphone:", .metaphone },
        .{ "year:", .year },
        .{ "month:", .month },
    };

    for (prefixes) |entry| {
        if (std.mem.startsWith(u8, key_name, entry[0])) {
            return .{
                .base = key_name[entry[0].len..],
                .transform = entry[1],
            };
        }
    }

    return .{
        .base = key_name,
        .transform = .none,
    };
}

test "applyTransform none" {
    const result = try applyTransform("hello", .none, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "applyTransform prefix_3" {
    const result = try applyTransform("hello", .prefix_3, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("HEL", result);
}

test "applyTransform prefix_4" {
    const result = try applyTransform("hello", .prefix_4, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("HELL", result);
}

test "applyTransform soundex" {
    const result = try applyTransform("Robert", .soundex, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("R163", result);
}

test "applyTransform year" {
    const result = try applyTransform("2023-05-15", .year, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("2023", result);
}

test "applyTransform month" {
    const result = try applyTransform("2023-05-15", .month, std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("05", result);
}

test "parseTransform" {
    const t1 = parseTransform("prefix_3:name");
    try std.testing.expectEqual(Transform.prefix_3, t1.transform);
    try std.testing.expectEqualStrings("name", t1.base);

    const t2 = parseTransform("name");
    try std.testing.expectEqual(Transform.none, t2.transform);
    try std.testing.expectEqualStrings("name", t2.base);
}
