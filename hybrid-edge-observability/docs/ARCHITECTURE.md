# Architecture Decisions

## Why Global Accelerator (not CloudFront or Route 53)?

- **GA preserves client source IP** — critical for payment compliance and fraud detection
- **GA flow logs** show routing decisions that are invisible with DNS-based routing
- **Static anycast IPs** — edge devices can hardcode the endpoint (no DNS dependency)
- **Health-check driven failover** — automatic, not TTL-dependent like DNS
- **TCP passthrough** — works with any protocol, not just HTTP

## Why EKS Fargate (not EC2 nodes)?

- **Per-pod ENIs** — each pod gets its own network interface, so VPC Flow Logs show individual pod traffic (not aggregated to a node)
- **No node management** — reduces operational overhead for a demo
- **ADOT sidecar** — automatically deployed for X-Ray trace collection
- **Container Insights** — native integration for pod-level metrics

## Why Aurora DSQL (not RDS)?

- **Multi-region active-active** — demonstrates observability across regions
- **Consensus writes** — the ~88ms write latency is a great observability talking point (expected behavior, not a bug)
- **IAM auth** — no password management, token-based authentication
- **Serverless** — no provisioning, auto-scales

## Why VPC Flow Logs v5 Format?

Enhanced fields we use:
- `tcp-flags` — identify SYN/FIN/RST for connection lifecycle analysis
- `flow-direction` — ingress vs egress without manual calculation
- `pkt-srcaddr` / `pkt-dstaddr` — original packet addresses (before NAT)
- `subnet-id` — quickly identify which tier (public/private) traffic flows through

## Why Separate Logs Bucket (not reusing loki-reports)?

- **Lifecycle policy:** Observability logs expire after 30 days (cost control)
- **IAM scoping:** GA, ALB, and Config all need bucket write access — isolating prevents overly broad permissions on other buckets
- **S3 Intelligent-Tiering:** Logs have predictable access patterns — frequent for 7 days, then Athena-only

## Observability Tool Selection Matrix

| Requirement | Tool | Why Not Alternative |
|-------------|------|---------------------|
| L3/L4 per-ENI | VPC Flow Logs | Traffic Mirroring is expensive at scale |
| L7 HTTP details | ALB Access Logs | Custom app logging misses ALB-level timing |
| Distributed trace | X-Ray + ADOT | Jaeger requires self-hosting; X-Ray is native |
| Pod metrics | Container Insights | Prometheus requires cluster management |
| Edge routing | GA Flow Logs | No alternative — GA-specific data |
| DNS resolution | Route 53 Resolver Logs | Only option for VPC DNS visibility |
| Unified view | CloudWatch Dashboard | Grafana requires hosting + data source config |
