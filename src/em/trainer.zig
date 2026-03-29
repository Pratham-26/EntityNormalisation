const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../config/types.zig");
const params = @import("params.zig");
const convergence = @import("convergence.zig");

pub const FieldParams = params.FieldParams;
pub const EMParams = params.EMParams;
pub const ConvergenceState = convergence.ConvergenceState;
pub const ConvergenceChecker = convergence.ConvergenceChecker;

pub const ComparisonPair = struct {
    left_id: u32,
    right_id: u32,
    gamma: []u8,
};

pub const EMTrainer = struct {
    params: EMParams,
    checker: ConvergenceChecker,
    phi: f64,

    pub fn init(allocator: Allocator, config: *const types.Priors, field_names: [][]const u8) !EMTrainer {
        var em_params = try EMParams.init(allocator, field_names.len);

        for (field_names, 0..) |name, i| {
            em_params.field_names[i] = try allocator.dupe(u8, name);
            em_params.fields[i] = FieldParams.init(config.initial_m, config.initial_u);
        }

        return .{
            .params = em_params,
            .checker = ConvergenceChecker.init(config.convergence_threshold, config.max_iterations),
            .phi = 0.05,
        };
    }

    pub fn deinit(self: *EMTrainer, allocator: Allocator) void {
        self.params.deinit(allocator);
        self.checker.deinit(allocator);
    }

    pub fn computeMatchProb(self: *const EMTrainer, gamma: []const u8) f64 {
        var prob_match: f64 = self.phi;
        var prob_nonmatch: f64 = 1.0 - self.phi;

        for (gamma, 0..) |g, i| {
            if (i >= self.params.fields.len) break;

            const m = self.params.fields[i].m;
            const u = self.params.fields[i].u;

            if (g == 1) {
                prob_match *= m;
                prob_nonmatch *= u;
            } else {
                prob_match *= (1.0 - m);
                prob_nonmatch *= (1.0 - u);
            }
        }

        const denominator = prob_match + prob_nonmatch;
        if (denominator < 1e-300) {
            return 0.5;
        }

        return prob_match / denominator;
    }

    pub fn eStep(self: *EMTrainer, pairs: []const ComparisonPair) ![]f64 {
        const expectations = try self.params.fields[0..0].ptr[0..0].ptr.*;
        _ = expectations;

        var result = std.ArrayList(f64).init(std.heap.page_allocator);
        defer result.deinit();

        for (pairs) |pair| {
            const prob = self.computeMatchProb(pair.gamma);
            try result.append(prob);
        }

        return result.toOwnedSlice();
    }

    pub fn eStepAlloc(self: *EMTrainer, pairs: []const ComparisonPair, allocator: Allocator) ![]f64 {
        const expectations = try allocator.alloc(f64, pairs.len);

        for (pairs, 0..) |pair, i| {
            expectations[i] = self.computeMatchProb(pair.gamma);
        }

        return expectations;
    }

    pub fn mStep(self: *EMTrainer, pairs: []const ComparisonPair, expectations: []const f64) !void {
        if (pairs.len == 0) return;
        if (self.params.fields.len == 0) return;

        var sum_match: f64 = 0.0;
        for (expectations) |e| {
            sum_match += e;
        }

        const n_pairs: f64 = @floatFromInt(pairs.len);
        self.phi = if (n_pairs > 0) sum_match / n_pairs else 0.05;

        const num_fields = self.params.fields.len;

        for (0..num_fields) |field_idx| {
            var sum_match_gamma1: f64 = 0.0;
            var sum_nonmatch_gamma1: f64 = 0.0;
            var sum_match_total: f64 = 0.0;
            var sum_nonmatch_total: f64 = 0.0;

            for (pairs, expectations) |pair, expectation| {
                const prob_match = expectation;
                const prob_nonmatch = 1.0 - expectation;

                if (field_idx < pair.gamma.len) {
                    if (pair.gamma[field_idx] == 1) {
                        sum_match_gamma1 += prob_match;
                        sum_nonmatch_gamma1 += prob_nonmatch;
                    }
                }

                sum_match_total += prob_match;
                sum_nonmatch_total += prob_nonmatch;
            }

            const new_m = if (sum_match_total > 1e-10)
                sum_match_gamma1 / sum_match_total
            else
                0.9;

            const new_u = if (sum_nonmatch_total > 1e-10)
                sum_nonmatch_gamma1 / sum_nonmatch_total
            else
                0.05;

            self.params.fields[field_idx] = FieldParams.init(new_m, new_u);
        }
    }

    pub fn computeLogLikelihood(self: *EMTrainer, pairs: []const ComparisonPair) f64 {
        var ll: f64 = 0.0;

        for (pairs) |pair| {
            var prob_match: f64 = self.phi;
            var prob_nonmatch: f64 = 1.0 - self.phi;

            for (pair.gamma, 0..) |g, i| {
                if (i >= self.params.fields.len) break;

                const m = self.params.fields[i].m;
                const u = self.params.fields[i].u;

                if (g == 1) {
                    prob_match *= m;
                    prob_nonmatch *= u;
                } else {
                    prob_match *= (1.0 - m);
                    prob_nonmatch *= (1.0 - u);
                }
            }

            const total_prob = prob_match + prob_nonmatch;
            if (total_prob > 0) {
                ll += std.math.log(total_prob);
            }
        }

        return ll;
    }

    pub fn train(self: *EMTrainer, pairs: []const ComparisonPair, allocator: Allocator) !ConvergenceState {
        self.checker.reset(allocator);

        var expectations = try self.eStepAlloc(pairs, allocator);
        defer allocator.free(expectations);

        var iteration: u32 = 0;

        while (iteration < self.checker.max_iterations) : (iteration += 1) {
            try self.mStep(pairs, expectations);

            for (pairs, 0..) |pair, i| {
                expectations[i] = self.computeMatchProb(pair.gamma);
            }

            const ll = self.computeLogLikelihood(pairs);
            const state = self.checker.checkWithIteration(&self.params, allocator, iteration + 1, ll);

            if (state.converged) {
                return state;
            }
        }

        const ll = self.computeLogLikelihood(pairs);
        return .{
            .iteration = iteration,
            .delta_m_max = 0.0,
            .delta_u_max = 0.0,
            .log_likelihood = ll,
            .converged = false,
        };
    }

    pub fn getParams(self: *const EMTrainer) *const EMParams {
        return &self.params;
    }

    pub fn getPhi(self: *const EMTrainer) f64 {
        return self.phi;
    }
};
