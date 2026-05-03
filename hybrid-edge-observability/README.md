# Hybrid Edge-to-Cloud Network Observability Demo

## Overview

This project demonstrates **end-to-end network observability** across a hybrid architecture spanning edge devices, AWS Global Accelerator, ALB, EKS, and Aurora DSQL (multi-region). It simulates payment terminal transactions and provides full-stack tracing at every network hop.

## Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│  Edge Simulator │────▶│  Global Accelerator  │────▶│     ALB     │────▶│   EKS Pod   │────▶│  Aurora DSQL │
│  (Lambda × 3)   │     │  (Anycast endpoint)  │     │  (Regional) │     │ (Payment API)│     │(Multi-Region)│
└─────────────────┘     └──────────────────────┘     └─────────────┘     └─────────────┘     └──────────────┘
     us-west-2                                            us-east-1          us-east-1         us-east-1 primary
     eu-west-1                                                                                 us-west-2 secondary
     ap-southeast-1
```

## Network Observability Layers

| Layer | Tool | What It Captures |
|-------|------|-----------------|
| L3/L4 | VPC Flow Logs (v5) | Source/dest IP, ports, packets, TCP flags, direction |
| L4 | Global Accelerator Flow Logs | Client→GA→endpoint routing, processing time |
| L7 | ALB Access Logs | Full HTTP details, target processing time, TLS |
| L7 | X-Ray Distributed Traces | Service map, latency per hop, DB query spans |
| DNS | Route 53 Resolver Query Logs | DNS resolution across all components |
| App | CloudWatch Container Insights | Pod CPU, memory, network I/O |
| DB | DSQL CloudWatch Metrics | Query latency, connections, replication lag |

## Correlation Strategy

All observability data is correlated by:
1. **`X-Transaction-ID`** — injected at edge, propagated through every component
2. **X-Ray Trace ID** — auto-propagated across services via ADOT sidecar
3. **Source IP + Timestamp** — correlates flow logs across ENIs
4. **CloudWatch Log Insights** — cross-log-group queries by transaction ID

## Project Structure

```
hybrid-edge-observability/
├── README.md                          # This file
├── terraform/
│   ├── main.tf                        # Root module — orchestrates all components
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Stack outputs
│   ├── providers.tf                   # AWS provider config (multi-region)
│   ├── backend.tf                     # S3 state backend
│   ├── modules/
│   │   ├── global-accelerator/        # GA + flow logs
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── alb/                       # ALB + access logs + VPC flow logs
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── eks/                       # EKS Fargate + ADOT + payment app
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── app/
│   │   │       ├── Dockerfile
│   │   │       ├── package.json
│   │   │       └── index.js           # Payment API with X-Ray instrumentation
│   │   ├── edge-simulator/            # Lambda edge simulators (multi-region)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── src/
│   │   │       └── handler.py         # Payment transaction simulator
│   │   └── observability/             # Dashboard + alarms + log groups
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
├── scripts/
│   ├── deploy.sh                      # Full deployment script
│   ├── simulate-traffic.sh            # Trigger edge simulators
│   └── teardown.sh                    # Clean destroy
└── docs/
    ├── OBSERVABILITY-GUIDE.md         # How to use each observability tool
    ├── DEMO-RUNBOOK.md                # Step-by-step demo script for customer
    └── ARCHITECTURE.md                # Detailed architecture decisions
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate IAM permissions
- Existing DSQL multi-region cluster:
  - Primary: `eftxnubwguc5c4dqr4gdvjct3e` (us-east-1)
  - Secondary: `5ftxnuflif62znbn33jayhvdoq` (us-west-2)
- Docker (for building EKS container image)

## Quick Start

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Estimated Cost

| Resource | Monthly Cost |
|----------|-------------|
| Global Accelerator | ~$18 + $0.015/GB |
| ALB | ~$16 |
| EKS Spot node (1× t4g.small ARM64) | ~$4 |
| Lambda simulators | ~$1 |
| S3 (logs) | ~$1 |
| CloudWatch dashboard | ~$3 |
| X-Ray | Free tier |
| **Total** | **~$43/month** |

*DSQL cluster is pre-existing and not counted here.*

## Demo Walkthrough

See [docs/DEMO-RUNBOOK.md](docs/DEMO-RUNBOOK.md) for the full customer presentation script.

1. Trigger payment from edge simulator (eu-west-1)
2. Trace through GA flow logs → ALB access logs → X-Ray trace → DSQL
3. Correlate by `X-Transaction-ID` across all layers
4. Simulate failure (kill pod) — show GA failover + alerting
5. Show unified CloudWatch dashboard

## Cleanup

```bash
cd terraform
terraform destroy
```
