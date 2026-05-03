# Network Observability Guide

## How to Trace a Transaction End-to-End

### 1. Get the Transaction ID

Every payment request carries an `X-Transaction-ID` header (UUID). This is your correlation key across all layers.

### 2. Global Accelerator Flow Logs (L4 — Edge Routing)

**Location:** `s3://hybrid-edge-obs-logs-033216807884/ga-flow-logs/`

**Query with Athena:**
```sql
SELECT client_ip, accelerator_ip, endpoint_ip, 
       total_time_ms, client_port, listener_port
FROM ga_flow_logs
WHERE timestamp BETWEEN '2026-05-03T00:00:00Z' AND '2026-05-03T23:59:59Z'
  AND client_ip = '<edge-simulator-ip>'
ORDER BY timestamp DESC
LIMIT 50;
```

**What you see:** Which GA endpoint the client connected to, how long GA took to route, and which regional endpoint received the traffic.

### 3. ALB Access Logs (L7 — HTTP Request)

**Location:** `s3://hybrid-edge-obs-logs-033216807884/alb-access-logs/`

**Key fields:**
- `request_processing_time` — time ALB spent routing
- `target_processing_time` — time the EKS pod took to respond
- `response_processing_time` — time sending response back
- `trace_id` — X-Ray trace ID (auto-populated)
- Target IP reveals which pod handled it

**Query with Log Insights:**
```
fields @timestamp, target_processing_time, elb_status_code, target_status_code
| filter request like /X-Transaction-ID/
| sort @timestamp desc
```

### 4. VPC Flow Logs (L3/L4 — Packet Level)

**Location:** CloudWatch Log Group `/aws/vpc/flow-logs/hybrid-edge-obs`

**Query — trace a connection from ALB to pod:**
```
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, packets, bytes, action, tcpFlags
| filter srcAddr = '<alb-eni-ip>' and dstPort = 8080
| sort @timestamp desc
| limit 50
```

**Query — trace pod to DSQL:**
```
fields @timestamp, srcAddr, dstAddr, dstPort, bytes, action
| filter dstPort = 5432 and action = 'ACCEPT'
| sort @timestamp desc
```

### 5. X-Ray Distributed Trace (L7 — Application)

**Console:** CloudWatch → X-Ray → Traces

**Filter by transaction:**
```
annotation.transactionId = "<uuid>"
```

**What you see:**
- Full waterfall: ALB → PaymentAPI → DSQL Query
- Latency breakdown per segment
- Annotations: transaction ID, edge region, pod name
- Errors highlighted with stack traces

### 6. DSQL Metrics (Database)

**CloudWatch Metrics:**
- `ServerlessDatabaseCapacity` — compute utilization
- `DatabaseConnections` — active connections from pods
- `CommitLatency` / `SelectLatency` — query performance

### 7. Container Insights (Pod Level)

**CloudWatch → Container Insights → EKS Cluster**

- Pod CPU/memory utilization
- Network rx/tx bytes per pod
- Pod restart count
- Service map (auto-discovered topology)

---

## Troubleshooting Scenarios

### "Edge latency is high but ALB target_processing_time is low"
→ Problem is between edge and ALB. Check GA flow logs for routing time, and whether GA is routing to a distant region.

### "ALB target_processing_time is high"
→ Problem is in the EKS pod. Check X-Ray trace — is it the DB query or app logic?

### "VPC Flow Logs show REJECT"
→ Security group or NACL blocking traffic. Check the interface-id to identify which ENI, then check its security group rules.

### "X-Ray shows DSQL sub-segment is slow"
→ Check DSQL CloudWatch metrics. If it's multi-region writes, ~88ms is expected (consensus latency). For reads, should be ~3ms.

### "GA healthy endpoint count drops"
→ ALB health check failing. Check ALB target health, pod readiness probe, and `/health` endpoint response.
