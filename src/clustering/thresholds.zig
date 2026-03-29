const std = @import("std");

pub const ThresholdBand = enum {
    match,
    review,
    discard,
};

pub const Thresholds = struct {
    match: f64,
    review: f64,
    cohesion: f64,

    pub fn init(match: f64, review: f64, cohesion: f64) Thresholds {
        return Thresholds{
            .match = match,
            .review = review,
            .cohesion = cohesion,
        };
    }

    pub fn classify(self: *const Thresholds, score: f64) ThresholdBand {
        if (score >= self.match) {
            return .match;
        } else if (score >= self.review) {
            return .review;
        } else {
            return .discard;
        }
    }

    pub fn isMatch(self: *const Thresholds, score: f64) bool {
        return score >= self.match;
    }

    pub fn needsReview(self: *const Thresholds, score: f64) bool {
        return score >= self.review and score < self.match;
    }
};

const testing = std.testing;

test "Thresholds classify" {
    const thresholds = Thresholds.init(0.85, 0.70, 0.60);

    try testing.expectEqual(ThresholdBand.match, thresholds.classify(0.90));
    try testing.expectEqual(ThresholdBand.match, thresholds.classify(0.85));
    try testing.expectEqual(ThresholdBand.review, thresholds.classify(0.80));
    try testing.expectEqual(ThresholdBand.review, thresholds.classify(0.70));
    try testing.expectEqual(ThresholdBand.discard, thresholds.classify(0.60));
    try testing.expectEqual(ThresholdBand.discard, thresholds.classify(0.50));
}

test "Thresholds isMatch" {
    const thresholds = Thresholds.init(0.85, 0.70, 0.60);

    try testing.expect(thresholds.isMatch(0.85));
    try testing.expect(thresholds.isMatch(0.90));
    try testing.expect(!thresholds.isMatch(0.84));
    try testing.expect(!thresholds.isMatch(0.70));
}

test "Thresholds needsReview" {
    const thresholds = Thresholds.init(0.85, 0.70, 0.60);

    try testing.expect(thresholds.needsReview(0.70));
    try testing.expect(thresholds.needsReview(0.80));
    try testing.expect(thresholds.needsReview(0.84));
    try testing.expect(!thresholds.needsReview(0.85));
    try testing.expect(!thresholds.needsReview(0.69));
}
