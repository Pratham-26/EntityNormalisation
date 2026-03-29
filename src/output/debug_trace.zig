const std = @import("std");
const Allocator = std.mem.Allocator;

pub const DebugTraceRecord = struct {
    left_id: u64,
    right_id: u64,
    total_score: f64,
    field_scores: []const f64,
    field_names: []const []const u8,
};

pub const DebugTraceWriter = struct {
    file: std.fs.File,
    writer: std.fs.File.Writer,
    field_names: []const []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u8, field_names: []const []const u8) !DebugTraceWriter {
        const file = try std.fs.cwd().createFile(path, .{
            .truncate = true,
        });

        var owned_names = try allocator.alloc([]const u8, field_names.len);
        for (field_names, 0..) |name, i| {
            owned_names[i] = try allocator.dupe(u8, name);
        }

        return .{
            .file = file,
            .writer = file.writer(),
            .field_names = owned_names,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DebugTraceWriter) void {
        for (self.field_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.field_names);
        self.file.close();
    }

    pub fn writeHeader(self: *DebugTraceWriter) !void {
        try self.writer.writeAll("left_id,right_id,total_score");
        for (self.field_names) |name| {
            try self.writer.print(",{s}_score", .{name});
        }
        try self.writer.writeAll("\n");
    }

    pub fn writeRecord(self: *DebugTraceWriter, record: *const DebugTraceRecord) !void {
        try self.writer.print("{d},{d},{d:.6}", .{
            record.left_id,
            record.right_id,
            record.total_score,
        });

        const scores = if (record.field_scores.len > 0) record.field_scores else &[_]f64{};
        for (scores) |score| {
            try self.writer.print(",{d:.6}", .{score});
        }

        if (self.field_names.len > scores.len) {
            var i = scores.len;
            while (i < self.field_names.len) : (i += 1) {
                try self.writer.writeAll(",0.000000");
            }
        }

        try self.writer.writeAll("\n");
    }
};

test "DebugTraceWriter write and read" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const field_names = [_][]const u8{ "name", "dob", "address" };
    const test_path = "test_debug_trace.csv";

    var writer = try DebugTraceWriter.init(allocator, test_path, &field_names);
    defer {
        writer.deinit();
        std.fs.cwd().deleteFile(test_path) catch {};
    }

    try writer.writeHeader();

    const field_scores = [_]f64{ 0.95, 1.0, 0.8 };
    const record = DebugTraceRecord{
        .left_id = 1,
        .right_id = 2,
        .total_score = 12.5,
        .field_scores = &field_scores,
        .field_names = &field_names,
    };

    try writer.writeRecord(&record);
}
