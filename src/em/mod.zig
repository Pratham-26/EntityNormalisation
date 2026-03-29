pub const params = @import("params.zig");
pub const convergence = @import("convergence.zig");
pub const trainer = @import("trainer.zig");

pub const FieldParams = params.FieldParams;
pub const EMParams = params.EMParams;

pub const ConvergenceState = convergence.ConvergenceState;
pub const ConvergenceChecker = convergence.ConvergenceChecker;

pub const EMTrainer = trainer.EMTrainer;
pub const ComparisonPair = trainer.ComparisonPair;

test {
    @import("std").testing.refAllDecls(@This());
}
