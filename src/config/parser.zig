const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const ParseError = error{
    InvalidJson,
    MissingField,
    InvalidValue,
    OutOfMemory,
};

fn parseNullLogic(value: std.json.Value) ?types.NullLogic {
    if (value != .string) return null;
    const str = value.string;
    if (std.mem.eql(u8, str, "ignore")) return .ignore;
    if (std.mem.eql(u8, str, "penalize")) return .penalize;
    if (std.mem.eql(u8, str, "neutral")) return .neutral;
    if (std.mem.eql(u8, str, "conditional")) return .conditional;
    return null;
}

fn parseComparisonLogic(value: std.json.Value) ?types.ComparisonLogic {
    if (value != .string) return null;
    const str = value.string;
    if (std.mem.eql(u8, str, "exact")) return .exact;
    if (std.mem.eql(u8, str, "levenshtein")) return .levenshtein;
    if (std.mem.eql(u8, str, "jaro_winkler")) return .jaro_winkler;
    if (std.mem.eql(u8, str, "date")) return .date;
    if (std.mem.eql(u8, str, "categorical")) return .categorical;
    return null;
}

fn parseComparisonParams(allocator: Allocator, obj: std.json.ObjectMap) ParseError!types.ComparisonParams {
    var params: types.ComparisonParams = .{};

    if (obj.get("threshold")) |val| {
        if (val == .float) {
            params.threshold = val.float;
        } else if (val == .integer) {
            params.threshold = @floatFromInt(val.integer);
        }
    }

    if (obj.get("null_logic")) |val| {
        if (parseNullLogic(val)) |logic| {
            params.null_logic = logic;
        } else {
            return ParseError.InvalidValue;
        }
    }

    if (obj.get("case_sensitive")) |val| {
        if (val == .bool) {
            params.case_sensitive = val.bool;
        }
    }

    if (obj.get("tolerance_days")) |val| {
        if (val == .integer) {
            params.tolerance_days = @intCast(val.integer);
        } else if (val == .float) {
            params.tolerance_days = @intFromFloat(val.float);
        }
    }

    if (obj.get("format")) |val| {
        if (val == .string) {
            params.format = try allocator.dupe(u8, val.string);
        }
    }

    if (obj.get("prefix_weight")) |val| {
        if (val == .float) {
            params.prefix_weight = val.float;
        } else if (val == .integer) {
            params.prefix_weight = @floatFromInt(val.integer);
        }
    }

    return params;
}

fn parseComparison(allocator: Allocator, obj: std.json.ObjectMap) ParseError!types.Comparison {
    const column_val = obj.get("column") orelse return ParseError.MissingField;
    if (column_val != .string) return ParseError.InvalidValue;

    const logic_val = obj.get("logic") orelse return ParseError.MissingField;
    const logic = parseComparisonLogic(logic_val) orelse return ParseError.InvalidValue;

    var comparison: types.Comparison = .{
        .column = try allocator.dupe(u8, column_val.string),
        .logic = logic,
    };

    if (obj.get("params")) |val| {
        if (val == .object) {
            comparison.params = try parseComparisonParams(allocator, val.object);
        }
    }

    if (obj.get("use_frequency_weighting")) |val| {
        if (val == .bool) {
            comparison.use_frequency_weighting = val.bool;
        }
    }

    if (obj.get("m_prior")) |val| {
        if (val == .float) {
            comparison.m_prior = val.float;
        } else if (val == .integer) {
            comparison.m_prior = @floatFromInt(val.integer);
        }
    }

    if (obj.get("u_prior")) |val| {
        if (val == .float) {
            comparison.u_prior = val.float;
        } else if (val == .integer) {
            comparison.u_prior = @floatFromInt(val.integer);
        }
    }

    return comparison;
}

fn parseStringArray(allocator: Allocator, arr: std.json.Array) ParseError![][]const u8 {
    var result = try allocator.alloc([]const u8, arr.items.len);
    errdefer allocator.free(result);

    for (arr.items, 0..) |item, i| {
        if (item != .string) return ParseError.InvalidValue;
        result[i] = try allocator.dupe(u8, item.string);
    }

    return result;
}

fn parseBlockingPass(allocator: Allocator, obj: std.json.ObjectMap) ParseError!types.BlockingPass {
    const keys_val = obj.get("keys") orelse return ParseError.MissingField;
    if (keys_val != .array) return ParseError.InvalidValue;

    const keys = try parseStringArray(allocator, keys_val.array);
    errdefer {
        for (keys) |key| allocator.free(key);
        allocator.free(keys);
    }

    var pass: types.BlockingPass = .{
        .keys = keys,
    };

    if (obj.get("max_block_size")) |val| {
        if (val == .integer) {
            pass.max_block_size = @intCast(val.integer);
        } else if (val == .float) {
            pass.max_block_size = @intFromFloat(val.float);
        }
    }

    if (obj.get("fallback_keys")) |val| {
        if (val == .array) {
            pass.fallback_keys = try parseStringArray(allocator, val.array);
        }
    }

    if (obj.get("fallback_logic")) |val| {
        if (val == .string) {
            pass.fallback_logic = try allocator.dupe(u8, val.string);
        }
    }

    return pass;
}

fn parsePriors(obj: std.json.ObjectMap) types.Priors {
    var priors: types.Priors = .{};

    if (obj.get("convergence_threshold")) |val| {
        if (val == .float) {
            priors.convergence_threshold = val.float;
        } else if (val == .integer) {
            priors.convergence_threshold = @floatFromInt(val.integer);
        }
    }

    if (obj.get("max_iterations")) |val| {
        if (val == .integer) {
            priors.max_iterations = @intCast(val.integer);
        } else if (val == .float) {
            priors.max_iterations = @intFromFloat(val.float);
        }
    }

    if (obj.get("sample_size")) |val| {
        if (val == .integer) {
            priors.sample_size = @intCast(val.integer);
        } else if (val == .float) {
            priors.sample_size = @intFromFloat(val.float);
        }
    }

    if (obj.get("initial_m")) |val| {
        if (val == .float) {
            priors.initial_m = val.float;
        } else if (val == .integer) {
            priors.initial_m = @floatFromInt(val.integer);
        }
    }

    if (obj.get("initial_u")) |val| {
        if (val == .float) {
            priors.initial_u = val.float;
        } else if (val == .integer) {
            priors.initial_u = @floatFromInt(val.integer);
        }
    }

    return priors;
}

fn parseOutputConfig(allocator: Allocator, obj: std.json.ObjectMap) ParseError!types.OutputConfig {
    var config: types.OutputConfig = .{
        .format = try allocator.dupe(u8, "csv"),
        .path = try allocator.dupe(u8, "./output"),
    };
    errdefer {
        allocator.free(config.format);
        allocator.free(config.path);
    }

    if (obj.get("format")) |val| {
        if (val == .string) {
            allocator.free(config.format);
            config.format = try allocator.dupe(u8, val.string);
        }
    }

    if (obj.get("path")) |val| {
        if (val == .string) {
            allocator.free(config.path);
            config.path = try allocator.dupe(u8, val.string);
        }
    }

    if (obj.get("include_debug_trace")) |val| {
        if (val == .bool) {
            config.include_debug_trace = val.bool;
        }
    }

    if (obj.get("threshold_match")) |val| {
        if (val == .float) {
            config.threshold_match = val.float;
        } else if (val == .integer) {
            config.threshold_match = @floatFromInt(val.integer);
        }
    }

    if (obj.get("threshold_review")) |val| {
        if (val == .float) {
            config.threshold_review = val.float;
        } else if (val == .integer) {
            config.threshold_review = @floatFromInt(val.integer);
        }
    }

    if (obj.get("cohesion_threshold")) |val| {
        if (val == .float) {
            config.cohesion_threshold = val.float;
        } else if (val == .integer) {
            config.cohesion_threshold = @floatFromInt(val.integer);
        }
    }

    return config;
}

pub fn parse(allocator: Allocator, json_bytes: []const u8) ParseError!types.Config {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, json_bytes, .{}) catch |err| {
        return switch (err) {
            error.OutOfMemory => ParseError.OutOfMemory,
            else => ParseError.InvalidJson,
        };
    };

    if (parsed != .object) return ParseError.InvalidJson;
    const root = parsed.object;

    const entity_name_val = root.get("entity_name") orelse return ParseError.MissingField;
    if (entity_name_val != .string) return ParseError.InvalidValue;
    const entity_name = try allocator.dupe(u8, entity_name_val.string);
    errdefer allocator.free(entity_name);

    var config: types.Config = .{
        .entity_name = entity_name,
        .comparisons = &.{},
        .blocking = &.{},
    };
    errdefer config.deinit(allocator);

    if (root.get("priors")) |val| {
        if (val == .object) {
            config.priors = parsePriors(val.object);
        }
    }

    if (root.get("comparisons")) |val| {
        if (val != .array) return ParseError.InvalidValue;
        var comparisons = try allocator.alloc(types.Comparison, val.array.items.len);
        errdefer allocator.free(comparisons);
        for (val.array.items, 0..) |item, i| {
            if (item != .object) return ParseError.InvalidValue;
            comparisons[i] = try parseComparison(allocator, item.object);
        }
        config.comparisons = comparisons;
    } else {
        return ParseError.MissingField;
    }

    if (root.get("blocking")) |val| {
        if (val != .array) return ParseError.InvalidValue;
        var blocking = try allocator.alloc(types.BlockingPass, val.array.items.len);
        errdefer allocator.free(blocking);
        for (val.array.items, 0..) |item, i| {
            if (item != .object) return ParseError.InvalidValue;
            blocking[i] = try parseBlockingPass(allocator, item.object);
        }
        config.blocking = blocking;
    } else {
        return ParseError.MissingField;
    }

    if (root.get("output")) |val| {
        if (val == .object) {
            config.output = try parseOutputConfig(allocator, val.object);
        }
    } else {
        config.output = try parseOutputConfig(allocator, .{});
    }

    return config;
}

pub fn parseFile(allocator: Allocator, path: []const u8) !types.Config {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(contents);

    return parse(allocator, contents);
}
