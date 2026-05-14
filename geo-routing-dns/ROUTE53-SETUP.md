# Route 53 Setup Guide — Geo Routing DNS v2

This document explains the complete Route 53 configuration for the latency-based geo-routing solution.

## Overview

Route 53 serves two purposes in this architecture:
1. **Latency-based routing** — directs traffic to the nearest healthy origin
2. **Health checks** — monitors each origin and removes unhealthy ones from rotation

## Hosted Zone Structure

### Zone: `geo.emhadip.people.aws.dev`
- **Zone ID:** `Z041924975F55CKBD4RI`
- **Type:** Public hosted zone (subdomain delegated from parent `emhadip.people.aws.dev`)
- **Purpose:** Contains all routing records, health check associations, and cert validation

### Records in the Zone

| Record Name | Type | Routing | Purpose |
|-------------|------|---------|---------|
| `api.geo.emhadip.people.aws.dev` | CNAME | Latency (americas) | Routes to us-east-1 API GW |
| `api.geo.emhadip.people.aws.dev` | CNAME | Latency (emea) | Routes to eu-west-1 API GW |
| `api.geo.emhadip.people.aws.dev` | CNAME | Latency (apac) | Routes to ap-southeast-1 API GW |
| `_d581acd5...geo.emhadip...` | CNAME | Simple | ACM cert validation (wildcard) |
| `_0b856371...api.geo.emhadip...` | CNAME | Simple | ACM cert validation (api subdomain) |
| `geo.emhadip.people.aws.dev` | NS | Simple | Zone nameservers (auto-created) |
| `geo.emhadip.people.aws.dev` | SOA | Simple | Start of Authority (auto-created) |

## Record Types Explained

### Latency-Based CNAME Records (3 records, same name)

These are the core routing records. All three share the same DNS name (`api.geo.emhadip.people.aws.dev`) but have different **Set Identifiers** and **Region** values:

```
Name:            api.geo.emhadip.people.aws.dev
Type:            CNAME
TTL:             60 seconds
Routing Policy:  Latency
```

| Set Identifier | Region | Target (CNAME value) | Health Check |
|---------------|--------|---------------------|--------------|
| `americas` | us-east-1 | `d-jy367dle65.execute-api.us-east-1.amazonaws.com` | ✅ Attached |
| `emea` | eu-west-1 | `d-nucf7rie5c.execute-api.eu-west-1.amazonaws.com` | ✅ Attached |
| `apac` | ap-southeast-1 | `d-vknsde25h4.execute-api.ap-southeast-1.amazonaws.com` | ✅ Attached |

**How latency routing works:**
1. Client makes DNS query for `api.geo.emhadip.people.aws.dev`
2. Route 53 determines which AWS region has the lowest latency from the client's DNS resolver
3. Returns the CNAME for that region (e.g., EMEA for clients in Israel/Europe)
4. If that origin's health check is failing, R53 returns the next-best-latency origin instead

**CNAME targets** are API Gateway **custom domain endpoints** (the `d-xxxxx.execute-api...` format). These endpoints present a valid TLS certificate for `api.geo.emhadip.people.aws.dev`, which is why custom domains + ACM certs are required.

### ACM Certificate Validation Records (DO NOT DELETE)

```
_d581acd5f1d628ceb7920bde105bf848.geo.emhadip.people.aws.dev
  → CNAME → _6ac9d5b600becb1c6f9b114d4614599b.jkddzztszm.acm-validations.aws.

_0b856371bab040b6827e7185e7bb4542.api.geo.emhadip.people.aws.dev
  → CNAME → _bafcefccb06c3ac09c4cdf19037a0c24.jkddzztszm.acm-validations.aws.
```

**What these are:** DNS proof-of-ownership for ACM (AWS Certificate Manager) certificates.

**Why they exist:** When we created SSL certificates for the API Gateway custom domains, ACM required proof that we own the domain. ACM generates a unique CNAME record that must exist in DNS — it checks periodically to ensure ongoing ownership.

**Which certs they validate:**
- `_d581...` → Wildcard cert `*.geo.emhadip.people.aws.dev` (for future subdomains)
- `_0b856...` → Specific cert `api.geo.emhadip.people.aws.dev` (used by API GW custom domains in all 3 regions)

**⚠️ Never delete these records.** If removed, ACM will fail to renew the certificates, and the API Gateway custom domains will stop serving HTTPS traffic.

### NS and SOA Records (auto-created)

Created automatically by Route 53 when the hosted zone was created. These tell the DNS system which nameservers are authoritative for this zone.

```
geo.emhadip.people.aws.dev  NS
  ns-223.awsdns-27.com
  ns-1965.awsdns-53.co.uk
  ns-1177.awsdns-19.org
  ns-610.awsdns-12.net
```

These same NS values are configured in the **parent zone** (`emhadip.people.aws.dev`) as a delegation record, telling the DNS hierarchy: "for anything under `geo.emhadip.people.aws.dev`, ask these nameservers."

## Health Checks

Three HTTPS health checks monitor each regional origin:

| Health Check | Target | Path | Interval | Threshold |
|-------------|--------|------|----------|-----------|
| `591d4d0d-...` (Americas) | `zp1q92gi4g.execute-api.us-east-1.amazonaws.com` | `/health` | 10s | 3 failures |
| `240f864c-...` (EMEA) | `qis8ziofkc.execute-api.eu-west-1.amazonaws.com` | `/health` | 10s | 3 failures |
| `ab055823-...` (APAC) | `q2kqzrn8zc.execute-api.ap-southeast-1.amazonaws.com` | `/health` | 10s | 3 failures |

**How health checks work:**
1. Route 53 runs health checkers from **16 global locations**
2. Each checker pings the target's `/health` endpoint every **10 seconds**
3. If an origin returns non-2xx status **3 consecutive times** (~30s), it's marked unhealthy
4. Route 53 immediately stops returning that origin in DNS responses
5. When the origin returns 2xx again for 3 checks, it's marked healthy and re-added

**Note:** Health checks hit the **raw API GW endpoints** (not the custom domain endpoints) because R53 health checkers need a stable, region-specific target to accurately detect regional failures.

## DNS Resolution Flow

```
1. Client (Israel) queries: api.geo.emhadip.people.aws.dev
                                    │
2. Client's DNS resolver → Root DNS → .dev NS → aws.dev NS → people.aws.dev NS
                                    │
3. → emhadip.people.aws.dev NS (parent zone)
                                    │
4. → Finds NS delegation for "geo" subdomain:
     ns-223.awsdns-27.com, ns-1965.awsdns-53.co.uk, etc.
                                    │
5. → Queries R53 zone Z041924975F55CKBD4RI
                                    │
6. R53 checks:
   - Which region has lowest latency from client's resolver? → eu-west-1
   - Is eu-west-1 health check passing? → Yes
   - Return: d-nucf7rie5c.execute-api.eu-west-1.amazonaws.com (TTL 60s)
                                    │
7. Client connects to eu-west-1 API GW → Lambda responds
```

## Subdomain Delegation Setup

For this to work, the **parent zone** (`emhadip.people.aws.dev`) must have an NS record delegating the `geo` subdomain:

```
Record in parent zone (emhadip.people.aws.dev):
  Name:  geo
  Type:  NS
  Value: ns-223.awsdns-27.com
         ns-1965.awsdns-53.co.uk
         ns-1177.awsdns-19.org
         ns-610.awsdns-12.net
```

This was configured manually in the separate AWS account that owns `emhadip.people.aws.dev`.

## API Gateway Custom Domains

Each region has an API Gateway with a **custom domain name** configured:

| Region | API GW ID | Custom Domain Endpoint | ACM Cert |
|--------|-----------|----------------------|----------|
| us-east-1 | `zp1q92gi4g` | `d-jy367dle65.execute-api.us-east-1.amazonaws.com` | `e02537a6-...` |
| eu-west-1 | `qis8ziofkc` | `d-nucf7rie5c.execute-api.eu-west-1.amazonaws.com` | `89d6f308-...` |
| ap-southeast-1 | `q2kqzrn8zc` | `d-vknsde25h4.execute-api.ap-southeast-1.amazonaws.com` | `c79c5404-...` |

**Why custom domains are needed:**
- CloudFront connects to the origin using the domain name `api.geo.emhadip.people.aws.dev`
- R53 returns a CNAME to the custom domain endpoint (e.g., `d-jy367dle65...`)
- The API GW custom domain presents a TLS cert valid for `api.geo.emhadip.people.aws.dev`
- Without this, TLS handshake fails (cert mismatch)

## Reproducing This Setup (Step by Step)

### Prerequisites
- A domain with a hosted zone in Route 53 (or a delegated subdomain)
- AWS CLI access

### Steps

```bash
# 1. Create hosted zone for your subdomain
aws route53 create-hosted-zone --name geo.yourdomain.com \
  --caller-reference "geo-routing-$(date +%s)"

# 2. Note the NS records from the output and add them to your parent zone

# 3. Request ACM certificates in each region
aws acm request-certificate --region us-east-1 \
  --domain-name api.geo.yourdomain.com --validation-method DNS
aws acm request-certificate --region eu-west-1 \
  --domain-name api.geo.yourdomain.com --validation-method DNS
aws acm request-certificate --region ap-southeast-1 \
  --domain-name api.geo.yourdomain.com --validation-method DNS

# 4. Add the DNS validation CNAME to your zone (check acm describe-certificate for values)

# 5. Create API GW custom domains in each region
aws apigatewayv2 create-domain-name --region us-east-1 \
  --domain-name api.geo.yourdomain.com \
  --domain-name-configurations CertificateArn=<cert-arn>,EndpointType=REGIONAL,SecurityPolicy=TLS_1_2

# 6. Map your API to the custom domain
aws apigatewayv2 create-api-mapping --region us-east-1 \
  --domain-name api.geo.yourdomain.com \
  --api-id <api-id> --stage '$default'

# 7. Create health checks
aws route53 create-health-check --caller-reference "hc-americas" \
  --health-check-config Type=HTTPS,FullyQualifiedDomainName=<api-gw-endpoint>,ResourcePath=/health,Port=443,RequestInterval=10,FailureThreshold=3

# 8. Create latency-based records
aws route53 change-resource-record-sets --hosted-zone-id <zone-id> --change-batch '{
  "Changes": [{
    "Action": "CREATE",
    "ResourceRecordSet": {
      "Name": "api.geo.yourdomain.com",
      "Type": "CNAME",
      "TTL": 60,
      "SetIdentifier": "americas",
      "Region": "us-east-1",
      "HealthCheckId": "<health-check-id>",
      "ResourceRecords": [{"Value": "<custom-domain-endpoint>"}]
    }
  }]
}'

# 9. Repeat steps 5-8 for each region
```

---

*This setup ensures TLS validity end-to-end, latency-optimal routing, and automatic failover — all managed by AWS services with zero custom code.*
