const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../config/types.zig");
const em = @import("../em/mod.zig");
const csv = @import("csv.zig");
const parquet = @import("parquet_out.zig");
const debug_trace = @import("debug_trace.zig");

pub const LinkageRecord = csv.LinkageRecord;
pub const CsvWriter = csv.CsvWriter;
pub const ParquetWriter = parquet.ParquetWriter;
pub const DebugTraceRecord = debug_trace.DebugTraceRecord;
pub const DebugTraceWriter = debug_trace.DebugTraceWriter;

pub const OutputWriter = struct {
    config: *const types.OutputConfig,
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: *const types.OutputConfig) OutputWriter {
        return .{
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OutputWriter) void {
        _ = self;
    }

    pub fn writeLinkage(self: *OutputWriter, records: []const LinkageRecord) !void {
        var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

        if (std.mem.eql(u8, self.config.format, "parquet")) {
            const path = try std.fmt.bufPrint(&path_buf, "{s}/linkage.parquet", .{self.config.path});
            try self.ensureDirectory();

            var writer = try ParquetWriter.init(path);
            defer writer.deinit();

            try writer.writeRecords(records);
        } else {
            const path = try std.fmt.bufPrint(&path_buf, "{s}/linkage.csv", .{self.config.path});
            try self.ensureDirectory();

            var writer = try CsvWriter.init(path);
            defer writer.deinit();

            try writer.writeHeader();
            try writer.writeRecords(records);
        }
    }

    pub fn writeConvergenceLog(self: *OutputWriter, iterations: []const em.ConvergenceState) !void {
        try self.ensureDirectory();

        var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/convergence_log.csv", .{self.config.path});

        const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();

        const writer = file.writer();
        try writer.writeAll("iteration,delta_m_max,delta_u_max,log_likelihood,converged\n");

        for (iterations) |state| {
            const converged_str: []const u8 = if (state.converged) "true" else "false";
            try writer.print("{d},{d:.6},{d:.6},{d:.6},{s}\n", .{
                state.iteration,
                state.delta_m_max,
                state.delta_u_max,
                state.log_likelihood,
                converged_str,
            });
        }
    }

    pub fn writeDebugTrace(self: *OutputWriter, records: []const DebugTraceRecord, field_names: []const []const u8) !void {
        if (!self.config.include_debug_trace) return;

        try self.ensureDirectory();

        var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/debug_trace.csv", .{self.config.path});

        var trace_writer = try DebugTraceWriter.init(self.allocator, path, field_names);
        defer trace_writer.deinit();

        try trace_writer.writeHeader();
        for (records) |*record| {
            try trace_writer.writeRecord(record);
        }
    }

    fn ensureDirectory(self: *OutputWriter) !void {
        std.fs.cwd().makePath(self.config.path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
};

test "OutputWriter write linkage CSV" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const format = try allocator.dupe(u8, "csv");
    const path = try allocator.dupe(u8, "test_output_dir");
    defer {
        allocator.free(format);
        allocator.free(path);
    }

    var config = types.OutputConfig{
        .format = format,
        .path = path,
    };

    var writer = OutputWriter.init(allocator, &config);
    defer writer.deinit();

    const records = [_]LinkageRecord{
        .{ .source_id = 1, .golden_record_id = 100, .cluster_size = 2, .match_score = 10.5 },
    };

    try writer.writeLinkage(&records);

    std.fs.cwd().deleteTree("test_output_dir") catch {};
}
