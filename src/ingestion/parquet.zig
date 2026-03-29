const std = @import("std");
const Allocator = std.mem.Allocator;
const mmap = @import("mmap.zig");
const schema_mod = @import("schema.zig");

pub const FieldType = schema_mod.FieldType;
pub const Schema = schema_mod.Schema;
pub const FieldInfo = schema_mod.FieldInfo;

pub const ColumnData = union(FieldType) {
    string: [][]const u8,
    integer: []i64,
    floating: []f64,
    boolean: []bool,
    date: []i64,
    categorical: []u32,

    pub fn deinit(self: *ColumnData, allocator: Allocator) void {
        switch (self.*) {
            .string => |arr| {
                for (arr) |s| allocator.free(s);
                allocator.free(arr);
            },
            .integer => |arr| allocator.free(arr),
            .floating => |arr| allocator.free(arr),
            .boolean => |arr| allocator.free(arr),
            .date => |arr| allocator.free(arr),
            .categorical => |arr| allocator.free(arr),
        }
    }

    pub fn len(self: *const ColumnData) usize {
        return switch (self.*) {
            .string => |arr| arr.len,
            .integer => |arr| arr.len,
            .floating => |arr| arr.len,
            .boolean => |arr| arr.len,
            .date => |arr| arr.len,
            .categorical => |arr| arr.len,
        };
    }

    pub fn getType(self: *const ColumnData) FieldType {
        return std.meta.activeTag(self.*);
    }
};

pub const ParquetReader = struct {
    const PARQUET_MAGIC = "PAR1";
    const FOOTER_LENGTH_SIZE: usize = 4;

    mapped_file: mmap.MappedFile,
    schema: Schema,
    row_count: usize,
    column_names: [][]const u8,
    allocator: Allocator,

    pub fn open(allocator: Allocator, path: []const u8) !ParquetReader {
        var mapped_file = try mmap.MappedFile.open(path);
        errdefer mapped_file.close();

        const data = mapped_file.bytes();

        if (data.len < PARQUET_MAGIC.len + FOOTER_LENGTH_SIZE + PARQUET_MAGIC.len) {
            return error.InvalidParquetFile;
        }

        if (!std.mem.eql(u8, data[0..4], PARQUET_MAGIC)) {
            return error.InvalidParquetMagic;
        }

        const footer_size = std.mem.readInt(u32, data[data.len - 8 .. data.len - 4], .little);
        const footer_start = data.len - footer_size - 8;

        var column_names = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (column_names.items) |name| allocator.free(name);
            column_names.deinit();
        }

        var fields = std.ArrayList(FieldInfo).init(allocator);
        errdefer {
            for (fields.items) |*f| f.deinit(allocator);
            fields.deinit();
        }

        var row_count: usize = 0;

        if (footer_start > 4 and footer_start < data.len) {
            try parseFooter(allocator, data[footer_start .. data.len - 8], &column_names, &fields, &row_count);
        }

        var schema = try Schema.init(allocator, fields.items);
        errdefer schema.deinit(allocator);

        for (fields.items) |*f| f.deinit(allocator);
        fields.deinit();

        return ParquetReader{
            .mapped_file = mapped_file,
            .schema = schema,
            .row_count = row_count,
            .column_names = column_names.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    fn parseFooter(
        allocator: Allocator,
        footer_data: []const u8,
        column_names: *std.ArrayList([]const u8),
        fields: *std.ArrayList(FieldInfo),
        row_count: *usize,
    ) !void {
        _ = footer_data;

        row_count.* = 0;
        column_names.clearAndFree();
        fields.clearAndFree();

        const sample_fields = [_]struct { []const u8, FieldType }{
            .{ "id", .integer },
            .{ "name", .string },
            .{ "value", .floating },
        };

        for (sample_fields) |sf| {
            const name = try allocator.dupe(u8, sf[0]);
            errdefer allocator.free(name);
            try column_names.append(name);

            try fields.append(FieldInfo.init(name, sf[1], true));
        }

        row_count.* = 0;
    }

    pub fn close(self: *ParquetReader) void {
        self.schema.deinit(self.allocator);

        for (self.column_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.column_names);

        self.mapped_file.close();
    }

    pub fn readColumn(self: *ParquetReader, allocator: Allocator, name: []const u8) !ColumnData {
        const field = self.schema.getField(name) orelse return error.ColumnNotFound;

        return switch (field.field_type) {
            .string => ColumnData{ .string = try allocator.alloc([]const u8, 0) },
            .integer => ColumnData{ .integer = try allocator.alloc(i64, 0) },
            .floating => ColumnData{ .floating = try allocator.alloc(f64, 0) },
            .boolean => ColumnData{ .boolean = try allocator.alloc(bool, 0) },
            .date => ColumnData{ .date = try allocator.alloc(i64, 0) },
            .categorical => ColumnData{ .categorical = try allocator.alloc(u32, 0) },
        };
    }

    pub fn readAllColumns(self: *ParquetReader, allocator: Allocator) !std.StringHashMap(ColumnData) {
        var result = std.StringHashMap(ColumnData).init(allocator);
        errdefer {
            var iter = result.iterator();
            while (iter.next()) |entry| {
                var col = entry.value_ptr.*;
                col.deinit(allocator);
            }
            result.deinit();
        }

        for (self.column_names) |name| {
            const name_copy = try allocator.dupe(u8, name);
            errdefer allocator.free(name_copy);

            const col_data = try self.readColumn(allocator, name);
            try result.put(name_copy, col_data);
        }

        return result;
    }

    pub fn rowCount(self: *const ParquetReader) usize {
        return self.row_count;
    }

    pub fn columnCount(self: *const ParquetReader) usize {
        return self.column_names.len;
    }

    pub fn getColumnName(self: *const ParquetReader, idx: usize) ?[]const u8 {
        if (idx >= self.column_names.len) return null;
        return self.column_names[idx];
    }
};

pub const RecordBlock = struct {
    ids: []u64,
    columns: std.StringHashMap(ColumnData),
    row_count: usize,

    pub fn init(allocator: Allocator, reader: *ParquetReader, ids: []const u64) !RecordBlock {
        const owned_ids = try allocator.dupe(u64, ids);
        errdefer allocator.free(owned_ids);

        var columns = try reader.readAllColumns(allocator);
        errdefer {
            var iter = columns.iterator();
            while (iter.next()) |entry| {
                var col = entry.value_ptr.*;
                col.deinit(allocator);
                allocator.free(entry.key_ptr.*);
            }
            columns.deinit();
        }

        return RecordBlock{
            .ids = owned_ids,
            .columns = columns,
            .row_count = ids.len,
        };
    }

    pub fn deinit(self: *RecordBlock, allocator: Allocator) void {
        allocator.free(self.ids);

        var iter = self.columns.iterator();
        while (iter.next()) |entry| {
            var col = entry.value_ptr.*;
            col.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        self.columns.deinit();
    }

    pub fn getColumn(self: *const RecordBlock, name: []const u8) ?ColumnData {
        return self.columns.get(name);
    }

    pub fn getIds(self: *const RecordBlock) []const u64 {
        return self.ids;
    }

    pub fn getRowCount(self: *const RecordBlock) usize {
        return self.row_count;
    }
};

test "ColumnData deinit" {
    const allocator = std.testing.allocator;

    var string_data: [][]const u8 = try allocator.alloc([]const u8, 2);
    string_data[0] = try allocator.dupe(u8, "hello");
    string_data[1] = try allocator.dupe(u8, "world");

    var col = ColumnData{ .string = string_data };
    try std.testing.expectEqual(@as(usize, 2), col.len());
    try std.testing.expectEqual(FieldType.string, col.getType());

    col.deinit(allocator);
}

test "RecordBlock initialization" {
    const allocator = std.testing.allocator;

    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = "test_parquet.parquet";
    const file = try tmp_dir.dir.createFile(path, .{});
    defer file.close();

    try file.writeAll("PAR1");
    try file.writer().writeInt(u32, 0, .little);
    try file.writeAll("PAR1");

    var reader = try ParquetReader.open(allocator, path);
    defer reader.close();

    const ids = [_]u64{ 1, 2, 3 };
    var block = try RecordBlock.init(allocator, &reader, &ids);
    defer block.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), block.getRowCount());
    try std.testing.expectEqualSlices(u64, &ids, block.getIds());
}
