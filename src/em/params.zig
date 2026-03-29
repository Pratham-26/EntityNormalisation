const std = @import("std");
const Allocator = std.mem.Allocator;

pub const FieldParams = struct {
    m: f64,
    u: f64,

    pub fn init(m_prior: f64, u_prior: f64) FieldParams {
        return .{
            .m = @max(0.001, @min(0.999, m_prior)),
            .u = @max(0.001, @min(0.999, u_prior)),
        };
    }
};

pub const EMParams = struct {
    fields: []FieldParams,
    field_names: [][]const u8,

    pub fn init(allocator: Allocator, num_fields: usize) !EMParams {
        const fields = try allocator.alloc(FieldParams, num_fields);
        @memset(fields, FieldParams{ .m = 0.9, .u = 0.05 });

        const field_names = try allocator.alloc([]const u8, num_fields);
        @memset(field_names, &.{});

        return .{
            .fields = fields,
            .field_names = field_names,
        };
    }

    pub fn deinit(self: *EMParams, allocator: Allocator) void {
        for (self.field_names) |name| {
            if (name.len > 0) {
                allocator.free(name);
            }
        }
        allocator.free(self.field_names);
        allocator.free(self.fields);
    }

    pub fn setField(self: *EMParams, index: usize, name: []const u8, m: f64, u: f64) void {
        _ = name;
        if (index < self.fields.len) {
            self.fields[index] = FieldParams.init(m, u);
        }
    }

    pub fn getField(self: *const EMParams, name: []const u8) ?FieldParams {
        for (self.field_names, 0..) |field_name, i| {
            if (std.mem.eql(u8, field_name, name)) {
                return self.fields[i];
            }
        }
        return null;
    }

    pub fn clone(self: *const EMParams, allocator: Allocator) !EMParams {
        var copy = try EMParams.init(allocator, self.fields.len);
        @memcpy(copy.fields, self.fields);
        for (self.field_names, 0..) |name, i| {
            if (name.len > 0) {
                copy.field_names[i] = try allocator.dupe(u8, name);
            }
        }
        return copy;
    }

    pub fn maxDelta(self: *const EMParams, other: *const EMParams) struct { delta_m: f64, delta_u: f64 } {
        var max_delta_m: f64 = 0.0;
        var max_delta_u: f64 = 0.0;

        for (self.fields, other.fields) |self_field, other_field| {
            max_delta_m = @max(max_delta_m, @abs(self_field.m - other_field.m));
            max_delta_u = @max(max_delta_u, @abs(self_field.u - other_field.u));
        }

        return .{ .delta_m = max_delta_m, .delta_u = max_delta_u };
    }
};
