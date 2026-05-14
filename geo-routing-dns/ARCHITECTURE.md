# Geo Routing v2 — Route 53 Latency-Based Routing + CloudFront WAF/DDoS

## Overview

Production-grade geo-routing using **Route 53 latency-based DNS**, **CloudFront WAF/DDoS protection**, and **API Gateway custom domains** with automatic health-check failover. Zero custom routing code.

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              CloudFront                       │
                    │   • WAF (Common Rules + Bad Inputs)           │
                    │   • AWS Shield Standard (DDoS)                │
                    │   • HTTPS termination                         │
                    │   • Global edge caching                       │
                    │                                               │
                    │   Distribution: dro2fulrmreh4.cloudfront.net  │
                    └──────────────────┬──────────────────────────┘
                                       │
                                       │ Origin: api.geo.emhadip.people.aws.dev
                                       │
                    ┌──────────────────▼──────────────────────────┐
                    │              Route 53                         │
                    │   Latency-Based Routing + Health Checks       │
                    │                                               │
                    │   Zone: geo.emhadip.people.aws.dev           │
                    │   Record: api.geo.emhadip.people.aws.dev     │
                    └──────────┬───────────┬───────────┬──────────┘
                               │           │           │
              ┌────────────────▼─┐  ┌──────▼────────┐  ┌▼────────────────┐
              │  us-east-1        │  │  eu-west-1     │  │  ap-southeast-1  │
              │  Americas         │  │  EMEA          │  │  APAC            │
              │                   │  │                │  │                  │
              │  Custom Domain    │  │  Custom Domain │  │  Custom Domain   │
              │  → API Gateway    │  │  → API Gateway │  │  → API Gateway   │
              │  → Lambda (arm64) │  │  → Lambda      │  │  → Lambda        │
              └───────────────────┘  └────────────────┘  └──────────────────┘
```

## How It Works

1. **Client request** → CloudFront edge (WAF inspects, Shield protects)
2. **CloudFront** → resolves origin `api.geo.emhadip.people.aws.dev` from edge POP
3. **Route 53** → returns lowest-latency healthy backend (CNAME to regional API GW custom domain)
4. **API Gateway** → custom domain with ACM cert → routes to Lambda
5. **Lambda** → responds with region info

### Failover
- Route 53 health checks ping `/health` on each regional API GW every **10 seconds**
- After **3 consecutive failures** (~30s), origin is marked unhealthy
- DNS automatically stops returning the unhealthy origin
- Traffic shifts to next-lowest-latency healthy origin
- Recovery is automatic when health returns

## Live URLs

| Resource | URL |
|----------|-----|
| **CloudFront (WAF protected)** | `https://dro2fulrmreh4.cloudfront.net/` |
| **Direct DNS (R53 latency)** | `https://api.geo.emhadip.people.aws.dev/` |
| **Test Client** | `https://dro2fulrmreh4.cloudfront.net/geo-routing.html` |
| Americas (direct) | `https://zp1q92gi4g.execute-api.us-east-1.amazonaws.com/` |
| EMEA (direct) | `https://qis8ziofkc.execute-api.eu-west-1.amazonaws.com/` |
| APAC (direct) | `https://q2kqzrn8zc.execute-api.ap-southeast-1.amazonaws.com/` |

## AWS Resources

| Resource | Identifier | Region |
|----------|-----------|--------|
| CloudFront Distribution | `EU5BY9YOEOVHR` | Global |
| WAF Web ACL | `geo-routing-waf` | Global |
| R53 Hosted Zone | `Z041924975F55CKBD4RI` | Global |
| Health Check (Americas) | `591d4d0d-044d-45d9-acd1-9ea6f73b0bad` | Global |
| Health Check (EMEA) | `240f864c-4c0e-4386-b245-f47dbb4ff5e4` | Global |
| Health Check (APAC) | `ab055823-7ae9-4c5b-950f-1264914cbc4e` | Global |
| API GW (Americas) | `zp1q92gi4g` | us-east-1 |
| API GW (EMEA) | `qis8ziofkc` | eu-west-1 |
| API GW (APAC) | `q2kqzrn8zc` | ap-southeast-1 |
| Custom Domain (all regions) | `api.geo.emhadip.people.aws.dev` | Multi |
| Lambda (Americas) | `geo-routing-dns-origin-americas` | us-east-1 |
| Lambda (EMEA) | `geo-routing-dns-origin-emea` | eu-west-1 |
| Lambda (APAC) | `geo-routing-dns-origin-apac` | ap-southeast-1 |
| Status API | `h1spol3qpl` | us-east-1 |
| ACM Cert (us-east-1) | `e02537a6-cba1-4cad-aabf-76e19f26f21a` | us-east-1 |
| ACM Cert (eu-west-1) | `89d6f308-1018-4773-a23c-622f0a9cfcd4` | eu-west-1 |
| ACM Cert (ap-southeast-1) | `c79c5404-d7c3-4e7f-bccd-1d672fee29c6` | ap-southeast-1 |

## Demo Script

```bash
# Show current health status
./failover.sh status

# Inject failure (simulate regional outage)
./failover.sh inject emea

# Wait ~30s for R53 to detect failure
# Watch test client: EMEA goes red, traffic routes elsewhere

# Restore
./failover.sh revert emea

# Wait ~30s for R53 to detect recovery
```

## Test Client — Page Sections Explained

**URL:** `https://dtt5rtdxrg7b6.cloudfront.net/geo-routing.html`

The test page is divided into the following sections:

### 1. Architecture Diagram
Visual representation of the traffic flow: Client → CloudFront → Route 53 → Regional origins.

### 2. Origin Cards (Americas / EMEA / APAC)
Shows the status and latency for each regional origin when tested directly.
- **Status badge:** HEALTHY (green) or UNREACHABLE (red) — based on direct HTTP response
- **Latency:** Round-trip time in ms from your browser to that origin's API GW endpoint
- **Green glow border:** Indicates the "winner" (lowest latency among healthy origins)

### 3. Route 53 Health Check Status (live from AWS)
Real-time status from Route 53's global health checkers — **this is NOT your browser testing the origins**.

**Flow:**
```
Test Page → Status API Lambda (us-east-1) → Route 53 GetHealthCheckStatus API
                                                      ↓
                                          Returns checker results from
                                          16 global R53 health check locations
                                          that ping each origin every 10s
```

- Shows how many of R53's 16 global checkers report each origin as healthy
- This is what Route 53 **actually uses to make routing decisions**
- When you inject a failure, this section shows the origin flipping to ❌ UNHEALTHY
- Once unhealthy, R53 stops including that origin in DNS responses

### 4. Control Buttons

| Button | What it tests | Flow |
|--------|---------------|------|
| 🚀 Test All Origins (Direct) | Browser → each API GW directly | Measures raw latency, bypasses CloudFront and R53 |
| ☁️ Test via CloudFront | Browser → CloudFront → R53 → origin | Full production path (WAF + DDoS + latency routing) |
| 🌐 Test via R53 DNS | Browser → `api.geo.emhadip.people.aws.dev` → origin | R53 latency routing without CloudFront layer |
| 🔄 Continuous (5s) | Repeats CloudFront test every 5s | **Use this during failure injection demo** — shows failover in real-time |
| ⏹ Stop | Stops continuous testing | — |

### 5. Event Log
Chronological log of all test results with timestamps, showing which origin responded and how fast.

### Demo Walkthrough (for customers)

1. Open test page, point out the R53 Health Check section — all 3 origins green ✅
2. Click **🔄 Continuous** — log shows `☁️ CF → eu-west-1 (EMEA)` repeating (closest to Israel)
3. In terminal: `./failover.sh inject emea` — explain you're making EMEA return 503 on /health
4. Watch the R53 Health Check section — within ~30s EMEA flips to ❌ (0/16 checkers)
5. Watch the log — traffic automatically shifts to `☁️ CF → us-east-1 (Americas)` 
6. **Key point:** Zero code change, zero manual intervention — DNS handled it
7. In terminal: `./failover.sh revert emea` — EMEA recovers in ~30s
8. Log shows traffic returning to EMEA (lowest latency from Israel)

## Comparison: v1 (CloudFront KVS) vs v2 (Route 53 + CloudFront)

| Aspect | v1 (CF Function + KVS) | v2 (R53 + CF) |
|--------|------------------------|---------------|
| Routing logic | Custom CF Function | AWS-managed R53 latency |
| Health checking | Custom Lambda (60s) | Native R53 (10s) |
| Failover speed | ~60s | ~30s |
| WAF/DDoS | ✅ (CloudFront) | ✅ (CloudFront) |
| Components to manage | 7+ | 4 (CF, R53, API GW, Lambda) |
| Custom code | ~300 lines | 0 lines (IaC only) |
| TLS | Managed by CF | ACM certs + custom domains |
| Routing accuracy | Country-level mapping | Network-latency-level |

## Security

- ✅ **WAF** — AWS Managed Rules (Common + Known Bad Inputs)
- ✅ **Shield Standard** — DDoS protection (automatic with CloudFront)
- ✅ **HTTPS everywhere** — ACM certs on API GW custom domains + CloudFront
- ✅ **No public Lambda access** — API GW only (IAM invoke permission)
- ✅ **No hardcoded secrets**

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| CloudFront | ~$1-5 (data transfer) |
| WAF | ~$6 (1 Web ACL + 2 rules) |
| Route 53 Zone | $0.50 |
| Health Checks (3x) | $2.25 |
| DNS Queries | ~$0.60/1M |
| API Gateway (3 regions) | ~$1-3 |
| Lambda (3 regions) | ~$0-3 |
| ACM Certs | Free |
| **Total** | **~$12-20/mo** |

## Project Structure

```
geo-routing-dns/
├── ARCHITECTURE.md          # This file
├── failover.sh              # Demo script (inject/revert failures)
├── test-client.html         # Interactive browser demo
├── lambda/
│   ├── origin.py            # Origin Lambda (simple response + /health)
│   └── status.py            # R53 health status API
└── terraform/
    ├── main.tf              # Providers, variables
    ├── lambdas.tf           # Lambda functions (3 regions)
    ├── api_gateways.tf      # HTTP API Gateways (3 regions)
    ├── route53.tf           # Zone, health checks, latency records
    └── outputs.tf           # Terraform outputs
```

## Prerequisites

- Domain with Route 53 hosted zone (or delegated subdomain)
- ACM certificates in each region for the custom domain
- NS delegation from parent zone to the subdomain's R53 nameservers

---

*Zero custom routing code. DNS does the work. CloudFront adds WAF + DDoS.*
