pub const comparators = @import("comparators.zig");
pub const fellegi_sunter = @import("fellegi_sunter.zig");
pub const frequency = @import("frequency.zig");
pub const simd = @import("simd.zig");

pub const CompareResult = comparators.CompareResult;
pub const Value = comparators.Value;
pub const exact = comparators.exact;
pub const levenshtein = comparators.levenshtein;
pub const jaroWinkler = comparators.jaroWinkler;
pub const dateCompare = comparators.dateCompare;
pub const categorical = comparators.categorical;
pub const compare = comparators.compare;

pub const EMParams = fellegi_sunter.EMParams;
pub const WeightTable = fellegi_sunter.WeightTable;
pub const PairScore = fellegi_sunter.PairScore;
pub const scorePair = fellegi_sunter.scorePair;
pub const scorePairDetailed = fellegi_sunter.scorePairDetailed;

pub const FrequencyTable = frequency.FrequencyTable;
pub const adjustWeightForFrequency = frequency.adjustWeightForFrequency;
pub const adjustWeightForFrequencyAlpha = frequency.adjustWeightForFrequencyAlpha;
pub const adjustWeightForFrequencyHash = frequency.adjustWeightForFrequencyHash;
pub const adjustWeightForFrequencyHashAlpha = frequency.adjustWeightForFrequencyHashAlpha;

pub const PairBatch = simd.PairBatch;
pub const scoreBatchSIMD = simd.scoreBatchSIMD;
pub const score8Pairs = simd.score8Pairs;
pub const score4Pairs = simd.score4Pairs;
pub const scoreBatchScalar = simd.scoreBatchScalar;

test {
    _ = comparators;
    _ = fellegi_sunter;
    _ = frequency;
    _ = simd;
}
