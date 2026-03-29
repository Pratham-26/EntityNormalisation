# ZENE Architecture

## Overview

ZENE (Zig Entity Normalization Engine) is a high-performance entity resolution engine implementing the Fellegi-Sunter probabilistic model. It processes 100M+ records through a multi-stage pipeline optimized for cache locality, SIMD parallelism, and zero-allocation hot paths.

---

## Core Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Ingestion  │───▶│   Blocking  │───▶│ EM Training │───▶│   Scoring   │───▶│  Clustering │───▶ Export
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
      │                  │                  │                  │                  │
      ▼                  ▼                  ▼                  ▼                  ▼
 MultiArrayList     Block Index       m/u Estimates      SIMD Compare      Cohesion Pass
   (mmap)           (skew-safe)       (iterative)        (fixed-point)     (threshold)
```

### Stage 1: Data Ingestion

**Purpose:** Load Parquet files into columnar memory with zero-copy efficiency.

**Implementation:**
- Memory-mapped file I/O via `std.os.mmap`
- Parquet column readers stream directly into `MultiArrayList` structures
- Schema validation against user-provided JSON configuration
- Type coercion: String, Date, Categorical, Boolean

**Memory Layout:**
```zig
const RecordBlock = struct {
    ids: []u64,
    fields: MultiArrayList(FieldData),
    allocator: std.mem.Allocator,
};
```

**Constraints:**
- Single allocation per block during load
- No dynamic resizing after initial population

---

### Stage 2: Blocking & Indexing

**Purpose:** Reduce O(n²) comparison space to tractable candidate pairs.

**Strategies:**

1. **Hash-Based Blocking**
   - Concatenate blocking keys → xxHash64
   - Group records by hash into blocks
   - Enforce `max_block_size` limit

2. **Skew Handling**
   - Blocks exceeding threshold trigger fallback keys
   - Secondary blocking pass on oversized blocks
   - Final fallback: TF-IDF token blocking

3. **Inverted Index**
   - Per-field value → record ID list mapping
   - Built using `MultiArrayList` for cache locality
   - Arena-allocated per block for instant cleanup

**Block Structure:**
```zig
const Block = struct {
    hash: u64,
    record_ids: []u32,
    fallback_applied: bool,
};
```

---

### Stage 3: EM Training

**Purpose:** Estimate m (match) and u (unmatch) probabilities from unlabeled data.

**Algorithm:**
```
Initialize: m_i = 0.9, u_i = 0.05 for all fields i
Repeat until convergence:
  E-step: Compute γ expectations for each pair
  M-step: Update m_i, u_i from expectations
  Check: max|Δm| < threshold AND max|Δu| < threshold
```

**Implementation Details:**
- Sample 10,000 blocks for training (configurable)
- Fixed 20 iterations maximum (configurable)
- Log Δ values per iteration for observability
- Early termination on convergence

**Data Structures:**
```zig
const EMParams = struct {
    m_probs: []f64,  // P(γ=1 | match) per field
    u_probs: []f64,  // P(γ=1 | unmatch) per field
    convergence_threshold: f64,
    max_iterations: u32,
};
```

---

### Stage 4: Probabilistic Scoring

**Purpose:** Compute log-likelihood weights for all candidate pairs.

**Fellegi-Sunter Formula:**
```
W_total = Σ W_i where:
  W_i = log2(m_i / u_i)     if γ_i = 1 (agreement)
  W_i = log2((1-m_i) / (1-u_i))  if γ_i = 0 (disagreement)
  W_i = 0                   if γ_i = null
```

**Optimizations:**
- Pre-compute log2 weights as fixed-point i16 during EM finalization
- SIMD batch comparison (8 pairs at once via @Vector)
- Frequency weighting: boost rare-value agreements
- Null handling: distinct penalty curve

**Comparison Logic Types:**
| Logic      | Description                          |
|------------|--------------------------------------|
| exact      | Binary match (0 or 1)                |
| levenshtein| Normalized edit distance ≥ threshold |
| jaro_winkler| String similarity with prefix bonus |
| date       | Match within tolerance (days)        |

**Hot Path:**
```zig
fn scorePairSIMD(pairs: []const Pair, weights: *const WeightTable) @Vector(8, i32) {
    // All comparisons in SIMD lanes
    // Return 8 scores in single instruction
}
```

---

### Stage 5: Clustering

**Purpose:** Group matched records while preventing false-positive "hairball" clusters.

**Algorithm: Cohesion-Aware Correlation Clustering**

1. Initialize: Each record is its own cluster
2. Iterate edges sorted by weight (descending):
   - If edge weight ≥ match threshold:
     - Compute average edge weight of merged cluster
     - If cohesion ≥ threshold: merge clusters
     - Else: skip edge (weak link)
3. Output: Cluster ID per record (Golden Record ID)

**Cohesion Check:**
```
cohesion(C) = (Σ edge_weight within C) / (|C| choose 2)
```

**Threshold Bands:**
| Band          | Score Range  | Action              |
|---------------|--------------|---------------------|
| Match         | ≥ T_match    | Auto-merge          |
| Manual Review | T_review..T_match | Flag for audit  |
| Discard       | < T_review   | No link             |

---

### Stage 6: Export

**Output Formats:**
- **Linkage Table:** `source_id, golden_record_id, cluster_size, match_score`
- **Debug Trace:** Full weight breakdown per pair (optional)
- **EM Convergence Log:** Per-iteration Δm, Δu values

---

## Memory Model

### Arena Allocators

Each processing stage uses arena allocators for bulk deallocation:

```
Block Processing Cycle:
  1. Create arena allocator
  2. Load block data into arena
  3. Score all pairs in block
  4. Write results to output buffer
  5. Reset arena (instant free)
```

### Memory Footprint

| Component        | Memory Type    | Lifetime           |
|------------------|----------------|--------------------|
| Parquet mmap     | Virtual        | Duration of file   |
| Block index      | Heap (arena)   | Per-block          |
| m/u parameters   | Heap (general) | Full run           |
| Score buffer     | Heap (arena)   | Per-block          |
| Cluster map      | Heap (general) | Full run           |

**RSS Stability:** Flat memory profile. No allocation spikes during scoring.

---

## Concurrency Model

### Thread Pool Architecture

- Work-stealing thread pool (lock-free deque per thread)
- Block-level parallelism: each block is independent unit
- SIMD within threads: vectorize pair comparisons

**Synchronization Points:**
1. After EM training (barrier)
2. After scoring all blocks (reduce to cluster phase)
3. During clustering (atomic cluster ID updates)

---

## Data Structures

### MultiArrayList Layout

```zig
const FieldData = struct {
    strings: []const []const u8,
    dates: []const i64,
    cats: []const u32,
    bools: []const bool,
    nulls: []const u8,  // bitmask
};
```

Benefits:
- Contiguous memory per field type
- Cache-friendly sequential access
- Zero padding overhead

### Hash Map for Blocking

```zig
const BlockIndex = std.HashMap(
    u64,              // block hash
    std.ArrayList(u32), // record IDs
    std.hash_map.AutoContext(u64),
    std.hash_map.default_max_load_percentage,
);
```

---

## Error Handling

| Error Type           | Handling                              |
|----------------------|---------------------------------------|
| File not found       | Exit with error code + message        |
| Invalid Parquet      | Report row/col, continue or halt      |
| Schema mismatch      | Halt with detailed field comparison   |
| Block size exceeded  | Apply fallback, log warning           |
| EM non-convergence   | Warn + use best estimates             |
| Memory allocation    | Graceful shutdown with cleanup        |

---

## Performance Targets

| Metric                          | Target                    |
|---------------------------------|---------------------------|
| Pair comparisons per core       | >100,000/sec              |
| 100M records total time         | <2 hours (64-core)        |
| Memory RSS variance             | <5% during scoring        |
| EM convergence iterations       | <10 (typical)             |
| SIMD utilization                | >80% of pairs vectorized  |
