# Aurora DSQL Benchmark — TPC-C Performance Testing

A TPC-C-based benchmark tool for comparing **Aurora DSQL single-region vs multi-region** latency across SELECT, INSERT, UPDATE, and New Order workloads.

---

## Architecture

```
EC2 (us-east-1, Graviton arm64)
  ├── → Single-Region DSQL cluster (us-east-1)
  └── → Multi-Region DSQL cluster (us-east-1 + us-west-2)
```

Measurements are taken **from the same EC2 instance**, so single-region will be the fastest baseline and multi-region overhead shows the cost of cross-region consensus.

---

## Prerequisites

- Node.js 18+
- AWS CLI v2
- IAM permissions for DSQL (provided via EC2 instance role)
- `npm` available

---

## Quick Start

### 1. Create DSQL Clusters

```bash
bash scripts/setup-clusters.sh
```

This creates:
- A single-region DSQL cluster in `us-east-1`
- A multi-region linked cluster spanning `us-east-1` and `us-west-2`
- A `config.json` with endpoints

### 2. Install Dependencies

```bash
npm install
```

### 3. Load TPC-C Schema

```bash
npm run setup-schema
```

Creates all TPC-C tables (`warehouse`, `district`, `customer`, `history`, `new_order`, `orders`, `order_line`, `item`, `stock`) on both clusters.

### 4. Run the Benchmark

```bash
# Quick run (default: select,insert,update at 1,100,1000 ops)
bash scripts/run-benchmark.sh

# Custom workloads and counts
WORKLOADS=select,insert,update,neworder COUNTS=1,100,1000,10000 bash scripts/run-benchmark.sh

# Or use npm directly
npm run benchmark -- --workloads select,insert,update --counts 1,100,1000,10000 --visualize
```

### 5. View Results

Results are saved in `results/`:
- `benchmark-<timestamp>.json` — Raw latency data
- `benchmark-<timestamp>.html` — Interactive Chart.js visualization

Open the HTML file in a browser or share it with customers.

---

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `--workloads` | `select,insert,update` | Comma-separated: `select`, `insert`, `update`, `neworder` |
| `--counts` | `1,100,1000` | Operations per run: `1`, `100`, `1000`, `10000` |
| `--output` | `benchmark-<ts>.json` | Output filename (saved to `results/`) |
| `--visualize` | `false` | Generate HTML report after run |

### Environment Variables (for run-benchmark.sh)

```bash
WORKLOADS=select,insert,update,neworder
COUNTS=1,100,1000,10000
bash scripts/run-benchmark.sh
```

---

## Workload Descriptions

| Workload | TPC-C Equivalent | Description |
|----------|-----------------|-------------|
| `select` | Stock Level | Point-lookup queries on `warehouse` |
| `insert` | Loader | Insert into `item` with ON CONFLICT |
| `update` | Payment | Update `warehouse.w_ytd` |
| `neworder` | New Order | Multi-step transaction: INSERT into `orders` + `new_order` |

---

## Interpreting Results

### Metrics

| Metric | Meaning |
|--------|---------|
| `avg` | Mean latency across all operations |
| `p50` | Median — half of requests faster, half slower |
| `p95` | 95th percentile — tail latency indicator |
| `p99` | 99th percentile — worst-case tail |
| `min` | Fastest single operation |
| `max` | Slowest single operation (often cold start) |

### What to Expect

- **Single-region** will generally be faster (lower latency) since writes only need quorum within us-east-1
- **Multi-region** adds consensus latency between us-east-1 and us-west-2 (typically +20–50ms for writes)
- **SELECT** latency is similar between both (reads are local by default)
- **Higher counts** smooth out outliers — run at 1000+ for meaningful stats

### Example Output

```json
{
  "singleRegion": {
    "select": {
      "1":    { "avg": 3.2,  "p50": 3.1,  "p95": 4.1,  "p99": 5.0 },
      "100":  { "avg": 2.8,  "p50": 2.7,  "p95": 3.5,  "p99": 4.2 },
      "1000": { "avg": 2.6,  "p50": 2.5,  "p95": 3.2,  "p99": 4.0 }
    }
  },
  "multiRegion": {
    "select": {
      "1":    { "avg": 3.5,  "p50": 3.3,  "p95": 4.5,  "p99": 6.1 },
      ...
    }
  }
}
```

---

## Cleanup

```bash
bash scripts/cleanup.sh
```

Deletes both DSQL clusters and removes `config.json`. Results files are preserved.

---

## File Structure

```
dsql-benchmark/
├── src/
│   ├── benchmark.js      # Main benchmark runner
│   ├── setup-schema.js   # TPC-C DDL setup
│   ├── dsql-client.js    # DSQL IAM auth + pg pool helper
│   └── visualize.js      # HTML report generator
├── scripts/
│   ├── setup-clusters.sh # Create DSQL clusters
│   ├── run-benchmark.sh  # Convenience run wrapper
│   └── cleanup.sh        # Delete all resources
├── results/              # JSON + HTML outputs
├── config.json           # Cluster endpoints (generated)
├── package.json
└── README.md
```

---

## Notes

- Authentication uses **IAM token auth** (no passwords hardcoded) — tokens are generated per connection using the instance role
- Tokens expire after ~15 minutes; the app creates a fresh pool per workload run
- DSQL uses **PostgreSQL wire protocol** — standard `pg` driver works
- All clusters use `deletionProtectionEnabled: false` for easy cleanup
- The benchmark does **not** pre-load data beyond what each workload needs (schema only)
