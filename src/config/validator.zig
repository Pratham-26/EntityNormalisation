const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const ValidationError = struct {
    field: []const u8,
    message: []const u8,
};

pub const ValidationResult = struct {
    valid: bool,
    errors: []ValidationError,

    pub fn deinit(self: *ValidationResult, allocator: Allocator) void {
        for (self.errors) |err| {
            allocator.free(err.field);
            allocator.free(err.message);
        }
        allocator.free(self.errors);
    }
};

fn addError(errors: *std.ArrayList(ValidationError), allocator: Allocator, field: []const u8, message: []const u8) !void {
    try errors.append(.{
        .field = try allocator.dupe(u8, field),
        .message = try allocator.dupe(u8, message),
    });
}

pub fn validate(config: *const types.Config, allocator: Allocator) ValidationResult {
    var errors = std.ArrayList(ValidationError).init(allocator);
    errdefer {
        for (errors.items) |err| {
            allocator.free(err.field);
            allocator.free(err.message);
        }
        errors.deinit();
    }

    if (config.entity_name.len == 0) {
        addError(&errors, allocator, "entity_name", "must not be empty") catch {
            return .{ .valid = false, .errors = &.{} };
        };
    }

    if (config.comparisons.len == 0) {
        addError(&errors, allocator, "comparisons", "must have at least one entry") catch {
            return .{ .valid = false, .errors = &.{} };
        };
    }

    for (config.comparisons, 0..) |comp, i| {
        if (comp.column.len == 0) {
            var buf: [64]u8 = undefined;
            const field_name = std.fmt.bufPrint(&buf, "comparisons[{}].column", .{i}) catch "comparisons.column";
            addError(&errors, allocator, field_name, "must not be empty") catch {
                return .{ .valid = false, .errors = &.{} };
            };
        }

        if (comp.m_prior) |m| {
            if (m <= 0 or m >= 1) {
                var buf: [64]u8 = undefined;
                const field_name = std.fmt.bufPrint(&buf, "comparisons[{}].m_prior", .{i}) catch "comparisons.m_prior";
                addError(&errors, allocator, field_name, "must be in range (0, 1)") catch {
                    return .{ .valid = false, .errors = &.{} };
                };
            }
        }

        if (comp.u_prior) |u| {
            if (u <= 0 or u >= 1) {
                var buf: [64]u8 = undefined;
                const field_name = std.fmt.bufPrint(&buf, "comparisons[{}].u_prior", .{i}) catch "comparisons.u_prior";
                addError(&errors, allocator, field_name, "must be in range (0, 1)") catch {
                    return .{ .valid = false, .errors = &.{} };
                };
            }
        }
    }

    if (config.blocking.len == 0) {
        addError(&errors, allocator, "blocking", "must have at least one entry") catch {
            return .{ .valid = false, .errors = &.{} };
        };
    }

    for (config.blocking, 0..) |block, i| {
        if (block.max_block_size == 0) {
            var buf: [64]u8 = undefined;
            const field_name = std.fmt.bufPrint(&buf, "blocking[{}].max_block_size", .{i}) catch "blocking.max_block_size";
            addError(&errors, allocator, field_name, "must be greater than 0") catch {
                return .{ .valid = false, .errors = &.{} };
            };
        }
    }

    if (config.output.threshold_match <= config.output.threshold_review) {
        addError(&errors, allocator, "output.threshold_match", "must be greater than threshold_review") catch {
            return .{ .valid = false, .errors = &.{} };
        };
    }

    if (config.priors.convergence_threshold <= 0) {
        addError(&errors, allocator, "priors.convergence_threshold", "must be greater than 0") catch {
            return .{ .valid = false, .errors = &.{} };
        };
    }

    return .{
        .valid = errors.items.len == 0,
        .errors = errors.toOwnedSlice() catch @as([]ValidationError, &.{}),
    };
}
