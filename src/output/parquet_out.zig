const std = @import("std");

pub const LinkageRecord = struct {
    source_id: u64,
    golden_record_id: u64,
    cluster_size: u32,
    match_score: f64,
};

pub const ParquetWriter = struct {
    file: std.fs.File,
    writer: std.fs.File.Writer,

    pub fn init(path: []const u8) !ParquetWriter {
        const file = try std.fs.cwd().createFile(path, .{
            .truncate = true,
        });
        return .{
            .file = file,
            .writer = file.writer(),
        };
    }

    pub fn deinit(self: *ParquetWriter) void {
        self.file.close();
    }

    pub fn writeRecords(self: *ParquetWriter, records: []const LinkageRecord) !void {
        try self.writer.writeAll("ZENE_PARQUET_V1\n");
        try self.writer.writeAll("source_id:UINT64,golden_record_id:UINT64,cluster_size:UINT32,match_score:FLOAT64\n");

        for (records) |*record| {
            try self.writer.print("{d},{d},{d},{d:.6}\n", .{
                record.source_id,
                record.golden_record_id,
                record.cluster_size,
                record.match_score,
            });
        }
    }
};

test "ParquetWriter simplified format" {
    const test_path = "test_output.parquet";
    var writer = try ParquetWriter.init(test_path);
    defer {
        writer.deinit();
        std.fs.cwd().deleteFile(test_path) catch {};
    }

    const records = [_]LinkageRecord{
        .{ .source_id = 1, .golden_record_id = 100, .cluster_size = 3, .match_score = 8.5 },
        .{ .source_id = 2, .golden_record_id = 100, .cluster_size = 3, .match_score = 7.2 },
    };

    try writer.writeRecords(&records);
}
