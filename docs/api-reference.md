# ZENE API Reference

## Configuration Format

ZENE accepts a JSON configuration file specifying the entity schema, comparison logic, and blocking strategy.

---

## Configuration Object

### Root Schema

```json
{
  "entity_name": "string",
  "priors": { ... },
  "comparisons": [ ... ],
  "blocking": [ ... ],
  "output": { ... }
}
```

| Field          | Type           | Required | Description                        |
|----------------|----------------|----------|------------------------------------|
| entity_name    | string         | Yes      | Identifier for this entity type    |
| priors         | object         | No       | EM training parameters             |
| comparisons    | array          | Yes      | Field comparison definitions       |
| blocking       | array          | Yes      | Blocking key definitions           |
| output         | object         | No       | Output format settings             |

---

## Priors Configuration

Controls Expectation-Maximization training behavior.

```json
{
  "priors": {
    "convergence_threshold": 0.001,
    "max_iterations": 20,
    "sample_size": 10000,
    "initial_m": 0.9,
    "initial_u": 0.05
  }
}
```

| Field                  | Type   | Default | Description                              |
|------------------------|--------|---------|------------------------------------------|
| convergence_threshold  | f64    | 0.001   | Δ threshold to stop EM iterations        |
| max_iterations         | u32    | 20      | Maximum EM iterations                    |
| sample_size            | u32    | 10000   | Number of blocks to sample for training  |
| initial_m              | f64    | 0.9     | Initial P(γ=1 \| match) for all fields   |
| initial_u              | f64    | 0.05    | Initial P(γ=1 \| unmatch) for all fields |

---

## Comparisons Configuration

Defines how each field contributes to the match score.

### Comparison Object

```json
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
}
```

| Field                   | Type    | Required | Description                              |
|-------------------------|---------|----------|------------------------------------------|
| column                  | string  | Yes      | Source column name                       |
| logic                   | string  | Yes      | Comparison function (see below)          |
| params                  | object  | No       | Logic-specific parameters                |
| use_frequency_weighting | bool    | No       | Boost rare-value matches                 |
| m_prior                 | f64     | No       | Override default m probability           |
| u_prior                 | f64     | No       | Override default u probability           |

### Logic Types

#### exact

Binary match. Returns 1 if values are identical, 0 otherwise.

```json
{
  "logic": "exact",
  "params": {
    "null_logic": "penalize",
    "case_sensitive": false
  }
}
```

| Param          | Type   | Default   | Description                              |
|----------------|--------|-----------|------------------------------------------|
| null_logic     | string | "ignore"  | How to handle nulls (see below)          |
| case_sensitive | bool   | false     | Case-sensitive comparison                |

#### levenshtein

Normalized Levenshtein similarity. Returns 1 if similarity ≥ threshold.

```json
{
  "logic": "levenshtein",
  "params": {
    "threshold": 0.85,
    "null_logic": "ignore"
  }
}
```

| Param          | Type   | Default | Description                              |
|----------------|--------|---------|------------------------------------------|
| threshold      | f64    | 0.8     | Minimum similarity to count as match     |
| null_logic     | string | "ignore"| How to handle nulls                      |

#### jaro_winkler

Jaro-Winkler string similarity with prefix bonus.

```json
{
  "logic": "jaro_winkler",
  "params": {
    "threshold": 0.9,
    "prefix_weight": 0.1,
    "null_logic": "ignore"
  }
}
```

| Param          | Type   | Default | Description                              |
|----------------|--------|---------|------------------------------------------|
| threshold      | f64    | 0.85    | Minimum similarity to count as match     |
| prefix_weight  | f64    | 0.1     | Weight for matching prefix               |
| null_logic     | string | "ignore"| How to handle nulls                      |

#### date

Date comparison with tolerance window.

```json
{
  "logic": "date",
  "params": {
    "tolerance_days": 7,
    "null_logic": "penalize",
    "format": "%Y-%m-%d"
  }
}
```

| Param          | Type   | Default     | Description                              |
|----------------|--------|-------------|------------------------------------------|
| tolerance_days | u32    | 0           | Max days difference for match            |
| null_logic     | string | "penalize"  | How to handle nulls                      |
| format         | string | auto-detect | Strptime format string                   |

#### categorical

Exact match for categorical encoded values.

```json
{
  "logic": "categorical",
  "params": {
    "null_logic": "ignore"
  }
}
```

### Null Logic Options

| Value       | Behavior                                    |
|-------------|---------------------------------------------|
| ignore      | Skip field in score calculation (weight=0)  |
| penalize    | Treat as disagreement (use unmatch weight)  |
| neutral     | Use average of match/unmatch weight         |
| conditional | Only penalize if both are null              |

---

## Blocking Configuration

Defines how to partition records for comparison.

### Blocking Object

```json
{
  "blocking": [
    {
      "keys": ["zip_code", "last_name_prefix_3"],
      "max_block_size": 10000,
      "fallback_keys": ["dob_year"],
      "fallback_logic": "secondary"
    }
  ]
}
```

| Field           | Type     | Required | Description                              |
|-----------------|----------|----------|------------------------------------------|
| keys            | []string | Yes      | Column names to concatenate for blocking |
| max_block_size  | u32      | No       | Trigger fallback if exceeded (default: 10000) |
| fallback_keys   | []string | No       | Secondary blocking keys for large blocks |
| fallback_logic  | string   | No       | "secondary" or "tfidf" (default: secondary) |

### Blocking Key Transformations

Pre-defined transformations available in key names:

| Transformation      | Example Input | Example Output |
|---------------------|---------------|----------------|
| {column}_prefix_3   | "Smith"       | "SMI"          |
| {column}_prefix_4   | "Smith"       | "SMIT"         |
| {column}_soundex    | "Smith"       | "S530"         |
| {column}_metaphone  | "Smith"       | "SM0T"         |
| {column}_ngrams_2   | "AB"          | ["AB"]         |
| {column}_year       | "1990-05-15"  | "1990"         |
| {column}_month      | "1990-05-15"  | "05"           |

### Multi-Pass Blocking

Multiple blocking definitions create independent passes:

```json
{
  "blocking": [
    { "keys": ["ssn_exact"] },
    { "keys": ["zip_code", "last_name_prefix_3"] },
    { "keys": ["dob", "first_name_prefix_4"] }
  ]
}
```

Pairs matching any pass are scored. Deduplication ensures each pair scored once.

---

## Output Configuration

```json
{
  "output": {
    "format": "parquet",
    "path": "./output/",
    "include_debug_trace": false,
    "threshold_match": 7.0,
    "threshold_review": 3.0,
    "cohesion_threshold": 0.7
  }
}
```

| Field               | Type   | Default    | Description                              |
|---------------------|--------|------------|------------------------------------------|
| format              | string | "csv"      | Output format: "csv" or "parquet"        |
| path                | string | "./output" | Output directory                         |
| include_debug_trace | bool   | false      | Write per-pair weight breakdown          |
| threshold_match     | f64    | 7.0        | Auto-merge threshold (log2 score)        |
| threshold_review    | f64    | 3.0        | Manual review lower bound                |
| cohesion_threshold  | f64    | 0.6        | Minimum cluster cohesion for merge       |

---

## CLI Interface

### Commands

#### train

Run EM training only, output learned parameters.

```bash
zene train --config config.json --data input.parquet --output params.json
```

| Flag      | Description                    |
|-----------|--------------------------------|
| --config  | Path to configuration file     |
| --data    | Path to input Parquet file     |
| --output  | Path to output parameters file |
| --verbose | Log EM iterations              |

#### dedupe

Full deduplication pipeline.

```bash
zene dedupe --config config.json --data input.parquet --output ./results/
```

| Flag          | Description                         |
|---------------|-------------------------------------|
| --config      | Path to configuration file          |
| --data        | Path to input Parquet file          |
| --output      | Output directory                    |
| --params      | Pre-trained parameters (optional)   |
| --threads     | Number of threads (default: all)    |
| --max-memory  | Memory limit in GB (default: 80%)   |
| --verbose     | Detailed progress logging           |

#### link

Record linkage between two datasets.

```bash
zene link --config config.json --left left.parquet --right right.parquet --output ./results/
```

| Flag      | Description                    |
|-----------|--------------------------------|
| --config  | Path to configuration file     |
| --left    | Path to left dataset           |
| --right   | Path to right dataset          |
| --output  | Output directory               |
| --threads | Number of threads              |

#### validate

Validate configuration file without processing.

```bash
zene validate --config config.json
```

#### inspect

Inspect Parquet schema and statistics.

```bash
zene inspect --data input.parquet
```

---

## Output Formats

### Linkage Table

Primary output mapping source records to clusters.

**CSV Format:**
```csv
source_id,golden_record_id,cluster_size,match_score
1001,1,3,12.5
1002,1,3,11.2
1003,1,3,8.7
1004,2,1,0.0
```

**Parquet Schema:**
```
source_id: uint64
golden_record_id: uint64
cluster_size: uint32
match_score: float64
```

### Debug Trace

Optional per-pair weight breakdown (when `include_debug_trace: true`).

```csv
left_id,right_id,total_score,last_name_w,first_name_w,dob_w,zip_w
1001,1002,12.5,4.2,3.1,2.8,2.4
1001,1003,8.7,4.2,2.1,1.8,0.6
```

### EM Convergence Log

Written to `{output_path}/em_convergence.csv`:

```csv
iteration,delta_m_max,delta_u_max,log_likelihood
1,0.15,0.08,-45231.2
2,0.08,0.04,-38421.5
3,0.003,0.002,-36892.1
4,0.0008,0.0005,-36841.3
```

---

## Error Codes

| Code | Meaning                        |
|------|--------------------------------|
| 0    | Success                        |
| 1    | Configuration file not found   |
| 2    | Invalid JSON in configuration  |
| 3    | Schema validation failed       |
| 4    | Input file not found           |
| 5    | Invalid Parquet format         |
| 6    | Memory allocation failed       |
| 7    | Thread pool initialization failed |
| 8    | EM failed to converge          |
| 9    | Output write failed            |

---

## Example Configuration

Complete example for customer deduplication:

```json
{
  "entity_name": "customer_global",
  "priors": {
    "convergence_threshold": 0.001,
    "max_iterations": 20
  },
  "comparisons": [
    {
      "column": "ssn",
      "logic": "exact",
      "params": { "null_logic": "ignore" },
      "use_frequency_weighting": false,
      "m_prior": 0.95,
      "u_prior": 0.001
    },
    {
      "column": "last_name",
      "logic": "jaro_winkler",
      "params": { 
        "threshold": 0.9,
        "null_logic": "penalize"
      },
      "use_frequency_weighting": true,
      "m_prior": 0.9,
      "u_prior": 0.05
    },
    {
      "column": "first_name",
      "logic": "jaro_winkler",
      "params": { 
        "threshold": 0.85,
        "null_logic": "penalize"
      },
      "use_frequency_weighting": true,
      "m_prior": 0.85,
      "u_prior": 0.1
    },
    {
      "column": "dob",
      "logic": "date",
      "params": { 
        "tolerance_days": 0,
        "null_logic": "ignore"
      },
      "use_frequency_weighting": false,
      "m_prior": 0.95,
      "u_prior": 0.01
    },
    {
      "column": "zip_code",
      "logic": "exact",
      "params": { "null_logic": "neutral" },
      "use_frequency_weighting": false,
      "m_prior": 0.7,
      "u_prior": 0.3
    }
  ],
  "blocking": [
    { 
      "keys": ["ssn"],
      "max_block_size": 1000
    },
    { 
      "keys": ["zip_code", "last_name_prefix_3"],
      "max_block_size": 10000,
      "fallback_keys": ["dob_year"]
    },
    {
      "keys": ["dob", "first_name_prefix_4"]
    }
  ],
  "output": {
    "format": "parquet",
    "path": "./output/",
    "threshold_match": 10.0,
    "threshold_review": 5.0,
    "cohesion_threshold": 0.65
  }
}
```
