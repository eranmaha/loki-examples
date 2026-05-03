# Aurora DSQL Performance Benchmark Report

## TPC-C Based Latency Analysis: Single-Region vs Multi-Region

**Date:** April 30, 2026  
**Duration:** ~10 minutes total execution  
**Prepared by:** Loki (Automated Benchmark)

---

## Test Characteristics

| Parameter | Value |
|-----------|-------|
| **Benchmark Type** | TPC-C derived workload patterns |
| **Database** | Amazon Aurora DSQL (PostgreSQL wire protocol) |
| **Single-Region Cluster** | us-east-1 |
| **Multi-Region Cluster** | us-east-1 (primary) ↔ us-west-2 (secondary), witness: us-east-2 |
| **Client Location** | EC2 Graviton (arm64) in us-east-1 |
| **Instance Type** | t4g.medium (arm64, Amazon Linux 2023) |
| **Connection** | IAM-authenticated, TLS, connection pooling (max 10) |
| **Operations Tested** | SELECT, INSERT, UPDATE |
| **Record Counts** | 1, 100, 1000 per operation type |
| **Schema** | 9 TPC-C tables (warehouse, district, customer, history, orders, new_order, order_line, item, stock) |
| **Data Seeded** | 10 warehouses, 100 items |
| **Auth Method** | IAM token via @aws-sdk/dsql-signer |
| **Encryption** | AWS-owned KMS key (default) |

### Workload Description

| Operation | SQL Pattern | Description |
|-----------|-------------|-------------|
| **SELECT** | `SELECT w_id, w_name, w_tax FROM warehouse WHERE w_id = $1` | Point read by primary key |
| **INSERT** | `INSERT INTO item (i_id, ...) VALUES ($1, ...) ON CONFLICT DO NOTHING` | Single-row insert with conflict handling |
| **UPDATE** | `UPDATE warehouse SET w_ytd = w_ytd + $1 WHERE w_id = $2` | Single-row update by primary key |

---

## Results Summary

### SELECT Performance (Point Read by Primary Key)

| Iterations | Region | Avg (ms) | P50 (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |
|-----------|--------|----------|----------|----------|----------|----------|----------|
| 100 | Single-Region | 3.40 | 3 | 4 | 19 | 3 | 19 |
| 100 | Multi-Region | 3.34 | 3 | 4 | 30 | 3 | 30 |
| 1000 | Single-Region | 2.94 | 3 | 3 | 4 | 2 | 18 |
| 1000 | Multi-Region | 2.89 | 3 | 3 | 4 | 2 | 26 |

**Finding:** SELECT latency is virtually identical between single-region and multi-region deployments. Reads are served locally from the nearest cluster with no cross-region overhead.

---

### INSERT Performance (Single Row with Conflict Handling)

| Iterations | Region | Avg (ms) | P50 (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |
|-----------|--------|----------|----------|----------|----------|----------|----------|
| 100 | Single-Region | 9.83 | 9 | 11 | 45 | 8 | 45 |
| 100 | Multi-Region | 89.96 | 90 | 92 | 125 | 4 | 125 |
| 1000 | Single-Region | 9.69 | 10 | 11 | 13 | 3 | 36 |
| 1000 | Multi-Region | 89.22 | 90 | 91 | 92 | 3 | 121 |

**Finding:** Multi-region INSERT latency is ~9x higher than single-region (90ms vs 10ms at P50). This reflects the cross-region consensus required for write operations across us-east-1 and us-west-2 (~70-80ms network RTT between regions).

---

### UPDATE Performance (Single Row by Primary Key)

| Iterations | Region | Avg (ms) | P50 (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) |
|-----------|--------|----------|----------|----------|----------|----------|----------|
| 100 | Single-Region | 11.31 | 12 | 12 | 13 | 10 | 13 |
| 100 | Multi-Region | 91.47 | 91 | 93 | 100 | 91 | 100 |
| 1000 | Single-Region | 11.23 | 11 | 12 | 13 | 9 | 30 |
| 1000 | Multi-Region | 91.92 | 91 | 93 | 96 | 91 | 181 |

**Finding:** Multi-region UPDATE latency follows the same pattern as INSERT — ~8x overhead due to cross-region consensus. P95 remains tight (93ms), indicating consistent cross-region RTT.

---

## Key Insights

### 1. Reads Are Free (No Cross-Region Penalty)
SELECT operations show **no measurable latency difference** between single and multi-region deployments. Aurora DSQL serves reads locally from the nearest cluster replica, making multi-region an excellent choice for read-heavy workloads.

### 2. Write Overhead Is Consistent (~80ms)
Both INSERT and UPDATE operations show a consistent **~80ms overhead** on multi-region vs single-region. This maps directly to the network round-trip time between us-east-1 and us-west-2 for achieving cross-region consensus.

### 3. Write Latency Is Predictable
Multi-region P95 stays within 2-3ms of P50 for writes, indicating stable performance without significant tail latency spikes. The consensus mechanism is deterministic.

### 4. Cold Start Effect
First operation on a fresh connection shows elevated latency (200-300ms) due to TLS handshake + IAM token validation. Subsequent operations settle to steady-state quickly.

### 5. Throughput Implications
- **Single-region writes:** ~100 TPS per connection (10ms/op)
- **Multi-region writes:** ~11 TPS per connection (90ms/op)
- For higher throughput, use connection pooling and concurrent connections

---

## Architecture Diagram

```
┌─────────────────┐         ┌─────────────────────────────────┐
│  EC2 Client     │         │  Aurora DSQL (Single-Region)     │
│  us-east-1      │◄──3ms──►│  us-east-1                      │
│  (Graviton)     │         │  Reads: ~3ms | Writes: ~10ms    │
└─────────────────┘         └─────────────────────────────────┘

┌─────────────────┐         ┌─────────────────────────────────┐
│  EC2 Client     │         │  Aurora DSQL (Multi-Region)      │
│  us-east-1      │◄──3ms──►│  Primary: us-east-1             │
│  (Graviton)     │         │  Secondary: us-west-2           │
└─────────────────┘         │  Witness: us-east-2             │
                            │  Reads: ~3ms | Writes: ~90ms    │
                            │  (cross-region consensus)        │
                            └─────────────────────────────────┘
```

---

## Recommendations

| Use Case | Recommendation |
|----------|---------------|
| Read-heavy workloads (>80% reads) | Multi-region — free disaster recovery with no read penalty |
| Write-heavy OLTP | Single-region — 9x better write latency |
| Global users, local reads | Multi-region — users read from nearest replica |
| Strong consistency writes + DR | Multi-region — accept ~80ms write latency for automatic failover |
| Latency-sensitive transactions | Single-region — sub-15ms for all operations |

---

## How to Reproduce

```bash
cd projects/dsql-benchmark/

# Install dependencies
npm install

# Setup clusters (creates single + multi-region)
bash scripts/setup-clusters.sh

# Setup schema
npm run setup-schema

# Run benchmark
npm run benchmark -- --workloads select,insert,update --counts 1,100,1000 --visualize

# Cleanup (deletes all clusters)
bash scripts/cleanup.sh
```

---

## Test Environment Details

- **AWS Account:** Production benchmark account
- **DSQL Version:** Aurora DSQL GA (April 2026)
- **Node.js:** v25.9.0
- **AWS SDK:** @aws-sdk/dsql-signer v3.x
- **PostgreSQL Client:** pg v8.11.x
- **OS:** Amazon Linux 2023 (aarch64/Graviton)
- **Network:** VPC default, no VPC endpoints (public DSQL endpoints via IGW)

---

*Report generated automatically. Raw data available in `results/full-benchmark.json`.*
*Interactive HTML visualization: `results/full-benchmark.html`*
