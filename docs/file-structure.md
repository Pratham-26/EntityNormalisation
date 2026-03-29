# ZENE File Structure

## Project Layout

```
zene/
├── build.zig                    # Build configuration
├── build.zig.zon               # Package manifest
├── src/
│   ├── main.zig                # CLI entry point
│   ├── root.zig                # Library root (exports)
│   │
│   ├── ingestion/
│   │   ├── mod.zig             # Ingestion module root
│   │   ├── parquet.zig         # Parquet file reader
│   │   ├── schema.zig          # Schema validation & mapping
│   │   └── mmap.zig            # Memory-mapped file utilities
│   │
│   ├── blocking/
│   │   ├── mod.zig             # Blocking module root
│   │   ├── hash_block.zig      # Hash-based blocking
│   │   ├── index.zig           # Inverted index builder
│   │   ├── skew_handler.zig    # Block size limit & fallback
│   │   └── transforms.zig      # Key transformations (prefix, soundex, etc.)
│   │
│   ├── em/
│   │   ├── mod.zig             # EM module root
│   │   ├── trainer.zig         # Expectation-Maximization loop
│   │   ├── params.zig          # m/u parameter storage
│   │   └── convergence.zig     # Convergence detection
│   │
│   ├── scoring/
│   │   ├── mod.zig             # Scoring module root
│   │   ├── fellegi_sunter.zig  # Log-likelihood weight calculation
│   │   ├── comparators.zig     # Comparison functions (exact, levenshtein, etc.)
│   │   ├── simd.zig            # SIMD-optimized batch scoring
│   │   └── frequency.zig       # Frequency-based weight adjustment
│   │
│   ├── clustering/
│   │   ├── mod.zig             # Clustering module root
│   │   ├── cohesion.zig        # Cohesion-aware clustering
│   │   ├── union_find.zig      # Union-Find data structure
│   │   └── thresholds.zig      # Threshold band management
│   │
│   ├── output/
│   │   ├── mod.zig             # Output module root
│   │   ├── writer.zig          # Output file writer
│   │   ├── csv.zig             # CSV format writer
│   │   ├── parquet.zig         # Parquet format writer
│   │   └── debug_trace.zig     # Debug trace generator
│   │
│   ├── config/
│   │   ├── mod.zig             # Config module root
│   │   ├── parser.zig          # JSON configuration parser
│   │   ├── validator.zig       # Schema validation
│   │   └── types.zig           # Configuration type definitions
│   │
│   ├── thread_pool/
│   │   ├── mod.zig             # Thread pool module root
│   │   ├── pool.zig            # Work-stealing thread pool
│   │   ├── queue.zig           # Lock-free work queue
│   │   └── barrier.zig         # Synchronization barrier
│   │
│   ├── memory/
│   │   ├── mod.zig             # Memory module root
│   │   ├── arena.zig           # Arena allocator wrapper
│   │   └── metrics.zig         # Memory usage tracking
│   │
│   └── utils/
│       ├── mod.zig             # Utilities module root
│       ├── hash.zig            # Hashing utilities (xxHash64)
│       ├── string.zig          # String utilities
│       └── log.zig             # Logging infrastructure
│
├── test/
│   ├── test_main.zig           # Test runner
│   ├── fixtures/               # Test data files
│   │   ├── sample_100.parquet  # Small test dataset
│   │   ├── sample_10k.parquet  # Medium test dataset
│   │   └── config_valid.json   # Valid config fixture
│   │
│   ├── ingestion/
│   │   └── parquet_test.zig
│   ├── blocking/
│   │   └── hash_block_test.zig
│   ├── em/
│   │   └── trainer_test.zig
│   ├── scoring/
│   │   └── fellegi_sunter_test.zig
│   └── clustering/
│       └── cohesion_test.zig
│
├── docs/
│   ├── architecture.md         # System architecture
│   ├── api-reference.md        # API documentation
│   ├── file-structure.md       # This file
│   └── plans/                  # Design documents
│       └── YYYY-MM-DD-topic-design.md
│
├── examples/
│   ├── basic_dedupe.json       # Basic deduplication config
│   ├── customer_link.json      # Customer linkage config
│   └── README.md               # Example usage guide
│
├── scripts/
│   ├── benchmark.zig           # Performance benchmarking
│   ├── generate_test_data.py   # Test data generator
│   └── validate_parquet.py     # Parquet validation utility
│
├── .gitignore
├── LICENSE
├── README.md
└── prd.md
```

---

## Module Responsibilities

### src/ingestion/

**Purpose:** Load and validate input data.

| File            | Responsibility                              |
|-----------------|---------------------------------------------|
| parquet.zig     | Parse Parquet format, extract columns       |
| schema.zig      | Validate columns against config             |
| mmap.zig        | Memory-map files for zero-copy reading      |

### src/blocking/

**Purpose:** Partition records into tractable blocks.

| File            | Responsibility                              |
|-----------------|---------------------------------------------|
| hash_block.zig  | Generate block hashes from keys             |
| index.zig       | Build inverted index for blocks             |
| skew_handler.zig| Detect oversized blocks, apply fallbacks    |
| transforms.zig  | Key transformations (prefix, soundex, etc.) |

### src/em/

**Purpose:** Learn match/unmatch probabilities.

| File            | Responsibility                              |
|-----------------|---------------------------------------------|
| trainer.zig     | EM algorithm main loop                      |
| params.zig      | Store and update m/u parameters             |
| convergence.zig | Detect convergence, log progress            |

### src/scoring/

**Purpose:** Compute pair similarity scores.

| File               | Responsibility                              |
|--------------------|---------------------------------------------|
| fellegi_sunter.zig | Weight calculation formula                  |
| comparators.zig    | Comparison functions per logic type         |
| simd.zig           | SIMD batch processing                       |
| frequency.zig      | Frequency-based weight adjustment           |

### src/clustering/

**Purpose:** Group matched records into clusters.

| File            | Responsibility                              |
|-----------------|---------------------------------------------|
| cohesion.zig    | Cohesion-aware correlation clustering       |
| union_find.zig  | Efficient cluster merging                   |
| thresholds.zig  | Match/review/discard band logic             |

### src/output/

**Purpose:** Write results to disk.

| File            | Responsibility                              |
|-----------------|---------------------------------------------|
| writer.zig      | Generic output dispatcher                   |
| csv.zig         | CSV format implementation                   |
| parquet.zig     | Parquet format implementation               |
| debug_trace.zig | Detailed pair weight breakdown              |

### src/config/

**Purpose:** Parse and validate user configuration.

| File         | Responsibility                              |
|--------------|---------------------------------------------|
| parser.zig   | JSON parsing into typed structs             |
| validator.zig| Validate required fields, ranges            |
| types.zig    | Configuration struct definitions            |

### src/thread_pool/

**Purpose:** Parallel execution infrastructure.

| File      | Responsibility                              |
|-----------|---------------------------------------------|
| pool.zig  | Work-stealing thread pool                   |
| queue.zig | Lock-free deque per worker                  |
| barrier.zig| Synchronization between phases              |

### src/memory/

**Purpose:** Memory management utilities.

| File       | Responsibility                              |
|------------|---------------------------------------------|
| arena.zig  | Arena allocator wrapper with reset          |
| metrics.zig| Track RSS, allocation counts                |

### src/utils/

**Purpose:** Shared utilities.

| File      | Responsibility                              |
|-----------|---------------------------------------------|
| hash.zig  | xxHash64 implementation                     |
| string.zig| String normalization, comparison            |
| log.zig   | Structured logging with levels              |

---

## Build Targets

Defined in `build.zig`:

| Target         | Command               | Description                    |
|----------------|-----------------------|--------------------------------|
| zene           | `zig build`           | Build main binary              |
| test           | `zig build test`      | Run all tests                  |
| benchmark      | `zig build benchmark` | Run performance benchmarks     |
| docs           | `zig build docs`      | Generate documentation         |

---

## Test Organization

Tests mirror source structure:

```
test/
├── test_main.zig          # Runs all tests
├── ingestion/
│   └── parquet_test.zig   # Tests src/ingestion/parquet.zig
├── blocking/
│   └── hash_block_test.zig
...
```

Each test file imports the module it tests and uses Zig's built-in `test` blocks.

---

## Configuration Files

| File                  | Purpose                              |
|-----------------------|--------------------------------------|
| build.zig             | Zig build system configuration       |
| build.zig.zon         | Package dependencies                 |
| examples/*.json       | Sample configuration files           |
| test/fixtures/*.json  | Test configuration fixtures          |
