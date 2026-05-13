# Geo Routing v2 — Route 53 Latency-Based Routing with Health Checks

## Problem Statement

The CloudFront KVS geo-routing solution (v1) requires:
- CloudFront Function code for routing logic
- Key Value Store management
- Health checker Lambda (polling every 60s)
- Maintenance API for toggling origins
- SSM parameters for health state

**Customer feedback:** Too many moving parts. Want something simpler that "just works."

## Proposed Solution

Replace the entire custom routing stack with **Route 53 Latency-Based Routing + Native Health Checks**.

Route 53 handles both routing AND health — zero custom code needed.

## Architecture

```
                         ┌─────────────────────────────────┐
                         │         Route 53                 │
                         │   Latency-Based Routing Policy   │
                         │   + Health Checks (built-in)     │
                         └──────────┬──────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
              ▼                     ▼                     ▼
    ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
    │  Origin: us-east-1│  │  Origin: eu-west-1│  │  Origin: ap-south-1│
    │  (Americas)       │  │  (EMEA)           │  │  (APAC)            │
    │                   │  │                   │  │                    │
    │  ALB / API GW /   │  │  ALB / API GW /   │  │  ALB / API GW /    │
    │  Lambda URL       │  │  Lambda URL       │  │  Lambda URL        │
    └──────────────────┘  └──────────────────┘  └──────────────────┘
```

## How It Works

### 1. Latency-Based Routing
- Route 53 maintains a latency database between AWS regions and client networks
- DNS resolves to the origin with **lowest latency** from the client's resolver location
- No geo-mapping tables, no CloudFront Functions — AWS handles it natively

### 2. Health Checks (Built-in)
- Route 53 health checks ping each origin every 10s or 30s (configurable)
- If an origin fails (3 consecutive checks), Route 53 **automatically stops routing** to it
- Traffic shifts to the next-best-latency origin — no Lambda, no KVS updates, no SSM
- When the origin recovers, traffic resumes automatically

### 3. Failover Behavior
```
Normal:    Client (Tel Aviv) → DNS → eu-west-1 (lowest latency)
Failure:   eu-west-1 goes down → Route 53 detects in ~30s → routes to us-east-1
Recovery:  eu-west-1 comes back → Route 53 resumes routing in ~30s
```

## Components

| Component | Purpose | Managed By |
|-----------|---------|------------|
| Route 53 Hosted Zone | DNS resolution | AWS |
| Latency-based records (x3) | One per origin region | Terraform/CFN |
| Health Checks (x3) | Monitor each origin | Route 53 (native) |
| Origin (x3) | Sample app in 3 regions | Lambda Function URL or ALB |
| CloudWatch Alarms | Alert on health check failure | Optional |

## Demo Origins (for this project)

| Origin | Region | Endpoint |
|--------|--------|----------|
| Americas | us-east-1 | Lambda Function URL |
| EMEA | eu-west-1 | Lambda Function URL |
| APAC | ap-southeast-1 | Lambda Function URL |

Each origin serves a simple JSON response with region info + a `/health` endpoint.

## Comparison: v1 (CloudFront KVS) vs v2 (Route 53)

| Aspect | v1 (CloudFront KVS) | v2 (Route 53) |
|--------|---------------------|---------------|
| Routing logic | Custom CF Function + KVS | AWS-managed latency DB |
| Health checking | Custom Lambda (every 60s) | Native R53 checks (10-30s) |
| Failover speed | ~60s (Lambda poll interval) | ~30s (3 × 10s checks) |
| Maintenance API | Custom Lambda + API GW + SSM | None needed (R53 console or API) |
| Components to manage | 7+ (Function, KVS, Lambda, API, SSM, EventBridge, origins) | 3 (R53 records, health checks, origins) |
| Code to maintain | ~300 lines | ~0 lines (IaC only) |
| Cost | CF Function invocations + Lambda + API GW | R53 queries ($0.60/M) + health checks ($0.50/check/mo) |
| Routing granularity | Country-level (custom mapping) | Network-latency-level (more accurate) |
| CDN caching | Yes (CloudFront) | Add CloudFront in front if needed |

## Optional Enhancements

1. **CloudFront in front** — Add a CF distribution with the R53 domain as origin for caching + HTTPS termination
2. **Weighted routing** — Combine latency with weighted records for canary deploys (90/10 split)
3. **Failover + Latency combo** — Primary/secondary per region for multi-AZ resilience
4. **CloudWatch integration** — Alarm on health check status → SNS notification

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| Route 53 Hosted Zone | $0.50 |
| Health Checks (3 × HTTPS) | $2.25 ($0.75 each) |
| DNS Queries | ~$0.60 per 1M queries |
| Lambda origins (3 regions) | ~$0-3 (demo traffic) |
| **Total** | **~$3-6/mo** |

vs v1: ~$40/mo (Lambda health checker + API GW + EventBridge + CF Function invocations)

## Implementation Plan

1. Create Lambda origins in 3 regions (simple "hello from {region}" + `/health`)
2. Create Route 53 hosted zone (or use existing)
3. Create 3 health checks (one per origin)
4. Create 3 latency-based alias/CNAME records pointing to origins
5. Test client page — shows which origin responds based on location
6. Simulate failure — disable one origin, verify automatic failover
7. IaC: Terraform or CDK for repeatable deployment

## Prerequisites

- A domain name (or use Route 53 subdomain for testing)
- Lambda deployed in 3 regions (cross-region CDK or Terraform)

---

*Review this architecture and let me know if you'd like to proceed with implementation.*
