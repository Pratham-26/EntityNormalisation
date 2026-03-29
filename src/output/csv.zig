const std = @import("std");

pub const LinkageRecord = struct {
    source_id: u64,
    golden_record_id: u64,
    cluster_size: u32,
    match_score: f64,
};

pub const CsvWriter = struct {
    file: std.fs.File,
    writer: std.fs.File.Writer,

    pub fn init(path: []const u8) !CsvWriter {
        const file = try std.fs.cwd().createFile(path, .{
            .truncate = true,
        });
        return .{
            .file = file,
            .writer = file.writer(),
        };
    }

    pub fn deinit(self: *CsvWriter) void {
        self.file.close();
    }

    pub fn writeHeader(self: *CsvWriter) !void {
        try self.writer.print("source_id,golden_record_id,cluster_size,match_score\n", .{});
    }

    pub fn writeRecord(self: *CsvWriter, record: *const LinkageRecord) !void {
        try self.writer.print("{d},{d},{d},{d:.6}\n", .{
            record.source_id,
            record.golden_record_id,
            record.cluster_size,
            record.match_score,
        });
    }

    pub fn writeRecords(self: *CsvWriter, records: []const LinkageRecord) !void {
        for (records) |*record| {
            try self.writeRecord(record);
        }
    }
};

test "CsvWriter write and read" {
    const test_path = "test_output_linkage.csv";
    var writer = try CsvWriter.init(test_path);
    defer {
        writer.deinit();
        std.fs.cwd().deleteFile(test_path) catch {};
    }

    try writer.writeHeader();

    const records = [_]LinkageRecord{
        .{ .source_id = 1, .golden_record_id = 100, .cluster_size = 3, .match_score = 8.5 },
        .{ .source_id = 2, .golden_record_id = 100, .cluster_size = 3, .match_score = 7.2 },
        .{ .source_id = 3, .golden_record_id = 101, .cluster_size = 1, .match_score = 15.0 },
    };

    try writer.writeRecords(&records);
}
