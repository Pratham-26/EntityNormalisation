const std = @import("std");
const Allocator = std.mem.Allocator;

pub const NullLogic = enum {
    ignore,
    penalize,
    neutral,
    conditional,
};

pub const ComparisonLogic = enum {
    exact,
    levenshtein,
    jaro_winkler,
    date,
    categorical,
};

pub const ComparisonParams = struct {
    threshold: ?f64 = null,
    null_logic: NullLogic = .ignore,
    case_sensitive: bool = false,
    tolerance_days: ?u32 = null,
    format: ?[]const u8 = null,
    prefix_weight: ?f64 = null,

    pub fn deinit(self: *ComparisonParams, allocator: Allocator) void {
        if (self.format) |fmt| {
            allocator.free(fmt);
        }
    }
};

pub const Comparison = struct {
    column: []const u8,
    logic: ComparisonLogic,
    params: ComparisonParams = .{},
    use_frequency_weighting: bool = false,
    m_prior: ?f64 = null,
    u_prior: ?f64 = null,

    pub fn deinit(self: *Comparison, allocator: Allocator) void {
        allocator.free(self.column);
        self.params.deinit(allocator);
    }
};

pub const BlockingPass = struct {
    keys: [][]const u8,
    max_block_size: u32 = 10000,
    fallback_keys: ?[][]const u8 = null,
    fallback_logic: []const u8 = "secondary",

    pub fn deinit(self: *BlockingPass, allocator: Allocator) void {
        for (self.keys) |key| {
            allocator.free(key);
        }
        allocator.free(self.keys);

        if (self.fallback_keys) |fb_keys| {
            for (fb_keys) |key| {
                allocator.free(key);
            }
            allocator.free(fb_keys);
        }

        allocator.free(self.fallback_logic);
    }
};

pub const Priors = struct {
    convergence_threshold: f64 = 0.001,
    max_iterations: u32 = 20,
    sample_size: u32 = 10000,
    initial_m: f64 = 0.9,
    initial_u: f64 = 0.05,
};

pub const OutputConfig = struct {
    format: []const u8 = "csv",
    path: []const u8 = "./output",
    include_debug_trace: bool = false,
    threshold_match: f64 = 7.0,
    threshold_review: f64 = 3.0,
    cohesion_threshold: f64 = 0.6,

    pub fn deinit(self: *OutputConfig, allocator: Allocator) void {
        allocator.free(self.format);
        allocator.free(self.path);
    }
};

pub const Config = struct {
    entity_name: []const u8,
    priors: Priors = .{},
    comparisons: []Comparison,
    blocking: []BlockingPass,
    output: OutputConfig = .{},

    pub fn deinit(self: *Config, allocator: Allocator) void {
        allocator.free(self.entity_name);

        for (self.comparisons) |*comp| {
            comp.deinit(allocator);
        }
        allocator.free(self.comparisons);

        for (self.blocking) |*block| {
            block.deinit(allocator);
        }
        allocator.free(self.blocking);

        self.output.deinit(allocator);
    }
};
