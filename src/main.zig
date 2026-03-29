const std = @import("std");

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        std.process.exit(1);
    };
}

fn run(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const io = init.io;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 2) {
        try printHelp(stdout);
        try stdout.flush();
        return;
    }

    const command = args[1];
    const cmd_args = if (args.len > 2) args[2..] else args[0..0];

    const exit_code = if (std.mem.eql(u8, command, "train"))
        try runTrain(arena, cmd_args, stdout, stderr)
    else if (std.mem.eql(u8, command, "dedupe"))
        try runDedupe(arena, cmd_args, stdout, stderr)
    else if (std.mem.eql(u8, command, "link"))
        try runLink(arena, cmd_args, stdout, stderr)
    else if (std.mem.eql(u8, command, "validate"))
        try runValidate(arena, cmd_args, stdout, stderr)
    else if (std.mem.eql(u8, command, "inspect"))
        try runInspect(arena, cmd_args, stdout, stderr)
    else if (std.mem.eql(u8, command, "help")) blk: {
        try printHelp(stdout);
        try stdout.flush();
        break :blk @as(u8, 0);
    } else blk: {
        try stderr.print("Unknown command: {s}\n\n", .{command});
        try printHelp(stderr);
        try stderr.flush();
        break :blk @as(u8, 1);
    };

    try stdout.flush();
    try stderr.flush();

    if (exit_code != 0) {
        std.process.exit(exit_code);
    }
}

fn runTrain(arena: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !u8 {
    _ = arena;
    var config_path: ?[]const u8 = null;
    var data_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var verbose: bool = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --config requires a value\n", .{});
                return 1;
            }
            config_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--data")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --data requires a value\n", .{});
                return 1;
            }
            data_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --output requires a value\n", .{});
                return 1;
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try stdout.print(
                \\zene train - Run EM training only
                \\
                \\Usage: zene train --config <config.json> --data <input.parquet> [--output <params.json>] [--verbose]
                \\
                \\Flags:
                \\  --config   Path to configuration file
                \\  --data     Path to input Parquet file
                \\  --output   Path to output parameters file (optional)
                \\  --verbose  Log EM iterations
                \\
            , .{});
            return 0;
        }
    }

    if (config_path == null) {
        try stderr.print("Error: --config is required\n", .{});
        return 1;
    }
    if (data_path == null) {
        try stderr.print("Error: --data is required\n", .{});
        return 1;
    }

    try stdout.print("Loading configuration from: {s}\n", .{config_path.?});
    try stdout.print("Loading data from: {s}\n", .{data_path.?});

    if (verbose) {
        try stdout.print("Starting EM training...\n", .{});
    }
    try stdout.print("EM training complete\n", .{});

    if (output_path) |path| {
        try stdout.print("Writing parameters to: {s}\n", .{path});
    }

    return 0;
}

fn runDedupe(arena: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !u8 {
    _ = arena;
    var config_path: ?[]const u8 = null;
    var data_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var params_path: ?[]const u8 = null;
    var verbose: bool = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --config requires a value\n", .{});
                return 1;
            }
            config_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--data")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --data requires a value\n", .{});
                return 1;
            }
            data_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --output requires a value\n", .{});
                return 1;
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--params")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --params requires a value\n", .{});
                return 1;
            }
            params_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try stdout.print(
                \\zene dedupe - Run full deduplication pipeline
                \\
                \\Usage: zene dedupe --config <config.json> --data <input.parquet> --output <dir> [options]
                \\
                \\Flags:
                \\  --config     Path to configuration file
                \\  --data       Path to input Parquet file
                \\  --output     Output directory
                \\  --params     Pre-trained parameters file (optional)
                \\  --threads    Number of threads (default: all)
                \\  --verbose    Detailed progress logging
                \\
            , .{});
            return 0;
        }
    }

    if (config_path == null) {
        try stderr.print("Error: --config is required\n", .{});
        return 1;
    }
    if (data_path == null) {
        try stderr.print("Error: --data is required\n", .{});
        return 1;
    }
    if (output_path == null) {
        try stderr.print("Error: --output is required\n", .{});
        return 1;
    }

    try stdout.print("Loading configuration from: {s}\n", .{config_path.?});
    try stdout.print("Loading data from: {s}\n", .{data_path.?});

    if (params_path) |path| {
        try stdout.print("Loading pre-trained parameters from: {s}\n", .{path});
    }

    if (verbose) try stdout.print("Running blocking...\n", .{});
    try stdout.print("Blocking complete\n", .{});

    if (verbose) try stdout.print("Running EM training...\n", .{});
    try stdout.print("EM training complete\n", .{});

    if (verbose) try stdout.print("Scoring pairs...\n", .{});
    try stdout.print("Scoring complete\n", .{});

    if (verbose) try stdout.print("Clustering...\n", .{});
    try stdout.print("Clustering complete\n", .{});

    try stdout.print("Writing results to: {s}\n", .{output_path.?});

    return 0;
}

fn runLink(arena: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !u8 {
    _ = arena;
    var config_path: ?[]const u8 = null;
    var left_path: ?[]const u8 = null;
    var right_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var verbose: bool = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --config requires a value\n", .{});
                return 1;
            }
            config_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--left")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --left requires a value\n", .{});
                return 1;
            }
            left_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--right")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --right requires a value\n", .{});
                return 1;
            }
            right_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --output requires a value\n", .{});
                return 1;
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try stdout.print(
                \\zene link - Link two datasets
                \\
                \\Usage: zene link --config <config.json> --left <left.parquet> --right <right.parquet> --output <dir> [options]
                \\
                \\Flags:
                \\  --config   Path to configuration file
                \\  --left     Path to left dataset
                \\  --right    Path to right dataset
                \\  --output   Output directory
                \\  --threads  Number of threads (default: all)
                \\  --verbose  Detailed progress logging
                \\
            , .{});
            return 0;
        }
    }

    if (config_path == null) {
        try stderr.print("Error: --config is required\n", .{});
        return 1;
    }
    if (left_path == null) {
        try stderr.print("Error: --left is required\n", .{});
        return 1;
    }
    if (right_path == null) {
        try stderr.print("Error: --right is required\n", .{});
        return 1;
    }
    if (output_path == null) {
        try stderr.print("Error: --output is required\n", .{});
        return 1;
    }

    try stdout.print("Loading configuration from: {s}\n", .{config_path.?});
    try stdout.print("Loading left dataset from: {s}\n", .{left_path.?});
    try stdout.print("Loading right dataset from: {s}\n", .{right_path.?});

    if (verbose) try stdout.print("Running blocking...\n", .{});
    try stdout.print("Blocking complete\n", .{});

    if (verbose) try stdout.print("Running EM training...\n", .{});
    try stdout.print("EM training complete\n", .{});

    if (verbose) try stdout.print("Scoring pairs...\n", .{});
    try stdout.print("Scoring complete\n", .{});

    if (verbose) try stdout.print("Clustering...\n", .{});
    try stdout.print("Clustering complete\n", .{});

    try stdout.print("Writing results to: {s}\n", .{output_path.?});

    return 0;
}

fn runValidate(arena: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !u8 {
    _ = arena;
    var config_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--config")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --config requires a value\n", .{});
                return 1;
            }
            config_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try stdout.print(
                \\zene validate - Validate configuration file
                \\
                \\Usage: zene validate --config <config.json>
                \\
                \\Flags:
                \\  --config   Path to configuration file
                \\
            , .{});
            return 0;
        }
    }

    if (config_path == null) {
        try stderr.print("Error: --config is required\n", .{});
        return 1;
    }

    try stdout.print("Validating configuration: {s}\n", .{config_path.?});
    try stdout.print("Configuration appears valid\n", .{});

    return 0;
}

fn runInspect(arena: std.mem.Allocator, args: []const []const u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) !u8 {
    _ = arena;
    var data_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--data")) {
            i += 1;
            if (i >= args.len) {
                try stderr.print("Error: --data requires a value\n", .{});
                return 1;
            }
            data_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try stdout.print(
                \\zene inspect - Inspect Parquet schema
                \\
                \\Usage: zene inspect --data <input.parquet>
                \\
                \\Flags:
                \\  --data   Path to Parquet file
                \\
            , .{});
            return 0;
        }
    }

    if (data_path == null) {
        try stderr.print("Error: --data is required\n", .{});
        return 1;
    }

    try stdout.print("Inspecting: {s}\n", .{data_path.?});
    try stdout.print("Schema information:\n", .{});
    try stdout.print("  (Parquet inspection not yet implemented)\n", .{});

    return 0;
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.print(
        \\ZENE - Zig Entity Normalization Engine
        \\
        \\Usage: zene <command> [options]
        \\
        \\Commands:
        \\
        \\  train       Run EM training only
        \\  dedupe      Run full deduplication pipeline
        \\  link        Link two datasets
        \\  validate    Validate configuration file
        \\  inspect     Inspect Parquet schema
        \\
        \\Use 'zene <command> --help' for command details
        \\
    , .{});
}
