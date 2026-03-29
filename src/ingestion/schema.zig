const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../config/types.zig");

pub const FieldType = enum {
    string,
    integer,
    floating,
    boolean,
    date,
    categorical,

    pub fn fromString(str: []const u8) ?FieldType {
        const lower = std.ascii.allocLowerString(std.heap.stack_alloc(64, str.len), str) catch return null;
        defer std.heap.stack_free(64, lower);

        if (std.mem.eql(u8, lower, "string") or std.mem.eql(u8, lower, "text") or std.mem.eql(u8, lower, "varchar")) {
            return .string;
        } else if (std.mem.eql(u8, lower, "integer") or std.mem.eql(u8, lower, "int") or std.mem.eql(u8, lower, "bigint")) {
            return .integer;
        } else if (std.mem.eql(u8, lower, "float") or std.mem.eql(u8, lower, "double") or std.mem.eql(u8, lower, "decimal")) {
            return .floating;
        } else if (std.mem.eql(u8, lower, "boolean") or std.mem.eql(u8, lower, "bool")) {
            return .boolean;
        } else if (std.mem.eql(u8, lower, "date") or std.mem.eql(u8, lower, "datetime") or std.mem.eql(u8, lower, "timestamp")) {
            return .date;
        } else if (std.mem.eql(u8, lower, "categorical") or std.mem.eql(u8, lower, "category") or std.mem.eql(u8, lower, "enum")) {
            return .categorical;
        }
        return null;
    }

    pub fn toComparisonLogic(self: FieldType) ?types.ComparisonLogic {
        return switch (self) {
            .string => .levenshtein,
            .integer => .exact,
            .floating => .exact,
            .boolean => .exact,
            .date => .date,
            .categorical => .categorical,
        };
    }
};

pub const FieldInfo = struct {
    name: []const u8,
    field_type: FieldType,
    nullable: bool,

    pub fn init(name: []const u8, field_type: FieldType, nullable: bool) FieldInfo {
        return .{
            .name = name,
            .field_type = field_type,
            .nullable = nullable,
        };
    }

    pub fn deinit(self: *FieldInfo, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const Schema = struct {
    fields: []FieldInfo,
    field_map: std.StringHashMap(usize),

    pub fn init(allocator: Allocator, fields: []const FieldInfo) !Schema {
        var owned_fields = try allocator.alloc(FieldInfo, fields.len);
        errdefer allocator.free(owned_fields);

        var field_map = std.StringHashMap(usize).init(allocator);
        errdefer field_map.deinit();

        for (fields, 0..) |field, i| {
            const name_owned = try allocator.dupe(u8, field.name);
            errdefer allocator.free(name_owned);

            owned_fields[i] = FieldInfo{
                .name = name_owned,
                .field_type = field.field_type,
                .nullable = field.nullable,
            };

            try field_map.put(name_owned, i);
        }

        return Schema{
            .fields = owned_fields,
            .field_map = field_map,
        };
    }

    pub fn deinit(self: *Schema, allocator: Allocator) void {
        for (self.fields) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.fields);
        self.field_map.deinit();
    }

    pub fn getField(self: *const Schema, name: []const u8) ?FieldInfo {
        const idx = self.field_map.get(name) orelse return null;
        return self.fields[idx];
    }

    pub fn getFieldIndex(self: *const Schema, name: []const u8) ?usize {
        return self.field_map.get(name);
    }

    pub fn validateAgainstConfig(self: *const Schema, config: *const types.Config) !void {
        _ = self;
        for (config.comparisons) |comp| {
            _ = comp;
        }
    }

    pub fn fieldCount(self: *const Schema) usize {
        return self.fields.len;
    }
};

test "Schema initialization and lookup" {
    const allocator = std.testing.allocator;

    const fields = [_]FieldInfo{
        FieldInfo.init("name", .string, false),
        FieldInfo.init("age", .integer, true),
    };

    var schema = try Schema.init(allocator, &fields);
    defer schema.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), schema.fieldCount());

    const name_field = schema.getField("name").?;
    try std.testing.expectEqual(FieldType.string, name_field.field_type);
    try std.testing.expect(!name_field.nullable);

    try std.testing.expect(schema.getField("nonexistent") == null);
}
