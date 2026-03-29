const std = @import("std");
const Allocator = std.mem.Allocator;
const params = @import("params.zig");
const EMParams = params.EMParams;

pub const ConvergenceState = struct {
    iteration: u32,
    delta_m_max: f64,
    delta_u_max: f64,
    log_likelihood: f64,
    converged: bool,
};

pub const ConvergenceChecker = struct {
    threshold: f64,
    max_iterations: u32,
    prev_params: ?EMParams,

    pub fn init(threshold: f64, max_iterations: u32) ConvergenceChecker {
        return .{
            .threshold = threshold,
            .max_iterations = max_iterations,
            .prev_params = null,
        };
    }

    pub fn deinit(self: *ConvergenceChecker, allocator: Allocator) void {
        if (self.prev_params) |*p| {
            p.deinit(allocator);
        }
    }

    pub fn check(self: *ConvergenceChecker, current: *const EMParams, allocator: Allocator) ConvergenceState {
        const iteration: u32 = if (self.prev_params == null) 0 else 1;

        if (self.prev_params) |*prev| {
            const delta = current.maxDelta(prev);
            const converged = delta.delta_m < self.threshold and delta.delta_u < self.threshold;

            prev.deinit(allocator);
            self.prev_params = current.clone(allocator) catch prev.*;
            return .{
                .iteration = iteration,
                .delta_m_max = delta.delta_m,
                .delta_u_max = delta.delta_u,
                .log_likelihood = 0.0,
                .converged = converged,
            };
        }

        self.prev_params = current.clone(allocator) catch null;
        return .{
            .iteration = 0,
            .delta_m_max = std.math.inf(f64),
            .delta_u_max = std.math.inf(f64),
            .log_likelihood = 0.0,
            .converged = false,
        };
    }

    pub fn checkWithIteration(self: *ConvergenceChecker, current: *const EMParams, allocator: Allocator, iteration: u32, log_likelihood: f64) ConvergenceState {
        if (self.prev_params) |*prev| {
            const delta = current.maxDelta(prev);
            const converged = delta.delta_m < self.threshold and delta.delta_u < self.threshold;

            prev.deinit(allocator);
            self.prev_params = current.clone(allocator) catch prev.*;

            return .{
                .iteration = iteration,
                .delta_m_max = delta.delta_m,
                .delta_u_max = delta.delta_u,
                .log_likelihood = log_likelihood,
                .converged = converged,
            };
        }

        self.prev_params = current.clone(allocator) catch null;
        return .{
            .iteration = iteration,
            .delta_m_max = std.math.inf(f64),
            .delta_u_max = std.math.inf(f64),
            .log_likelihood = log_likelihood,
            .converged = false,
        };
    }

    pub fn reset(self: *ConvergenceChecker, allocator: Allocator) void {
        if (self.prev_params) |*p| {
            p.deinit(allocator);
            self.prev_params = null;
        }
    }
};
