# Product Requirements Document: Zig Entity Normalization Engine (ZENE)

## 1. Executive Summary
ZENE (formerly PENE) is a high-performance, system-level entity resolution engine written in Zig. It is designed to ingest, deduplicate, and cluster massive datasets (100M+ records) using the Fellegi-Sunter probabilistic model. ZENE utilizes unsupervised machine learning (Expectation-Maximization) to learn match weights from unlabeled data, providing a high-accuracy, transparent resolution profile at extreme speeds, effectively bypassing the limitations of traditional edit-distance tools and opaque ML black-boxes.

---

## 2. Problem Statement
Enterprise datasets frequently contain duplicate records obfuscated by varied schemas, typographical errors, and missing information. Existing deduplication solutions fail across three vectors:
* **Scale and Speed:** Python/Java-based tools struggle with $O(n^2)$ scaling per block and suffer from garbage collection latency.
* **Rigidity:** Rule-based systems fail to account for the statistical rarity of specific values (e.g., matching on "Zyzzyva" vs. "Smith").
* **Opacity:** Deep learning or proprietary black-box ML solutions lack the explainability required for stringent data auditing and regulatory compliance.

---

## 3. Goals & Objectives
* **Extreme Scale:** Process datasets exceeding 100 million records on a single high-memory, multi-core instance.
* **Maximized Efficiency:** Achieve sub-millisecond scoring per pair using Zig’s SIMD capabilities, `MultiArrayList` cache locality, and comptime optimizations.
* **Unsupervised Learning:** Automatically estimate $m$ (match probability) and $u$ (unmatch probability) distributions using an Expectation-Maximization (EM) algorithm.
* **Developer-First Usability:** Provide a declarative JSON API for schema definition, blocking strategies, and weight priors.

---

## 4. User Personas
* **Data Engineer:** Requires a highly performant, memory-stable binary to integrate into a Lakehouse ETL pipeline.
* **Data Scientist:** Needs to tune probabilistic weights, analyze EM convergence, and audit "gray-area" matches with transparent scoring.
* **System Architect:** Seeks a low-latency, low-footprint, statically linked binary easily deployed in containerized environments.

---

## 5. Functional Requirements

### 5.1 Data Ingestion
* **Columnar Native:** Native reading of Parquet or Apache Arrow formats via memory mapping (mmap).
* **Schema Mapping:** API support for mapping source columns to internal generic attributes (String, Date, Categorical, Boolean).

### 5.2 Blocking & Indexing
* **Multi-Pass Blocking:** Support for hash-based blocking and sorted-neighborhood algorithms to constrain the search space.
* **Dynamic Skew Handling:** Implement block size limits (e.g., maximum 10,000 records per block). If a block exceeds this threshold due to data skew (e.g., a massive null-value block), the engine must automatically apply a secondary fallback key or utilize TF-IDF token blocking to split the cluster and prevent $O(n^2)$ memory explosions.
* **Inverted Indexing:** High-speed, RAM-resident indexing built using Zig's `MultiArrayList`.

### 5.3 Probabilistic Scoring Engine
* **Fellegi-Sunter Implementation:** Calculate log-likelihood weights for field agreements ($\gamma_i$). The base weight $W_i$ for an exact agreement on field $i$ is calculated as:
    $$W_i = \log_2 \left( \frac{m_i}{u_i} \right)$$
    where $m_i = P(\gamma_i = 1 | M)$ and $u_i = P(\gamma_i = 1 | U)$.
* **Frequency-Based Weighting:** Dynamically assign higher agreement weights to rare values (calculated via a pre-pass histogram).
* **Nuanced Null Handling:** Implement distinct marginal probabilities for missing data. A missing field must not penalize the total score as heavily as a deterministic disagreement between two populated fields.
* **EM Algorithm:** Iterative training mode to refine $m$ and $u$ parameters from unlabeled blocks before final scoring.

### 5.4 Clustering & Output
* **Correlation Clustering / Cohesion Pass:** Replace strict, transitive Union-Find with a cohesion-aware clustering algorithm. The engine must verify that the average edge weight within a formed cluster remains above the user-defined threshold, proactively pruning weak links to prevent massive, false-positive "hairball" clusters.
* **Threshold Management:** User-defined bands for match, manual review, and discard.
* **Linkage Export:** Export an optimized mapping table of `Source_ID` to `Golden_Record_ID`.

---

## 6. Non-Functional Requirements

### 6.1 Performance
* Total execution time for 100M records (including blocking, EM training, and scoring) must be < 2 hours on a standard 64-core machine.

### 6.2 Memory Safety & Architecture
* Strict reliance on Zig’s manual memory management.
* Utilize Arena allocators for block-level processing to guarantee zero fragmentation and instant memory reclamation after a block is scored.

### 6.3 Deployment
* The core engine must be a single, statically linked binary with zero external runtime dependencies.

### 6.4 Observability & Telemetry
* **EM Convergence Logging:** The engine must output iteration logs detailing the $\Delta$ of $m$ and $u$ probabilities. If the algorithm risks converging on a local minimum, it must emit warnings.
* **Scoring Transparency:** Ability to output a debug trace for any two records, showing the exact mathematical derivation of their final weight.

---

## 7. API Specification (Input Format)

### 7.1 Configuration Object
```json
{
  "entity_name": "customer_global",
  "priors": {
    "convergence_threshold": 0.001,
    "max_iterations": 20
  },
  "comparisons": [
    {
      "column": "last_name",
      "logic": "levenshtein",
      "params": { 
        "threshold": 0.85,
        "null_logic": "ignore" 
      },
      "use_frequency_weighting": true,
      "m_prior": 0.9,
      "u_prior": 0.05
    },
    {
      "column": "is_active",
      "logic": "exact",
      "params": { 
        "null_logic": "penalize" 
      },
      "use_frequency_weighting": false,
      "m_prior": 0.8,
      "u_prior": 0.5
    }
  ],
  "blocking": [
    { 
      "keys": ["zip_code", "last_name_prefix_3"],
      "max_block_size": 10000,
      "fallback_keys": ["dob_year"]
    }
  ]
}
```

---

## 8. Technical Constraints
* **Language:** Must be written in Zig 0.13.0+ (or current stable release).
* **Concurrency:** Must utilize a lock-free or work-stealing thread pool optimized for the pair-scoring phase.
* **Precision:** Mathematical operations must be performed using `f64` for probability estimations during EM, but aggressively optimized to fixed-point `i32` or `i16` for the hot-path combinatorial scoring loop.

---

## 9. Success Metrics
* **Accuracy:** Achieve >95% F1-score on standard academic datasets (e.g., FEBRL).
* **Throughput:** Process >100,000 pair comparisons per second, per CPU core.
* **Resource Footprint:** Maintain a stable, flat Resident Set Size (RSS) during the Expectation-Maximization and final scoring phases, entirely avoiding memory spikes.

---

## 10. Testing & Evaluation Data
* **Parquet Format:** All testing and evaluation datasets must be provided in Parquet format to ensure consistency with the production ingestion pipeline and to validate the columnar-native reading capabilities.