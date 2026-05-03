# CloudFront Geo-Based Origin Routing with Health Checks

## Overview

Dynamic origin selection using **CloudFront Functions + Key Value Store**, with automated health checking and failover.

## Architecture

```
Viewer → CloudFront → CF Function (reads KVS) → Route to origin
                                                    ↓
                                        Origin 0 (Americas)
                                        Origin 1 (EMEA)
                                        Origin 2 (APAC)
                                        __default__ (fallback)

Health Checker Lambda (every 60s) → invokes /health on each origin
                                  → updates KVS enabled/disabled
                                  → CF Function reads KVS next request
```

## Components

| Component | Purpose |
|-----------|---------|
| `src/viewer-request.js` | CF Function — geo-routes requests based on country → region → origin |
| `src/test-client.html` | Interactive demo page with toggles and request simulation |
| `lambdas/origin-handler.mjs` | Origin Lambda with `/health` endpoint (reads SSM for health state) |
| `lambdas/health-checker.py` | Background Lambda — checks each origin's health, updates KVS |
| `lambdas/maintenance-api.py` | API to toggle origin health state (SSM parameter) |

## AWS Resources

| Resource | Identifier |
|----------|-----------|
| CF Distribution | `E2ASS4LVS2WQ05` — `d2y11z8qnhnm6.cloudfront.net` |
| KVS | `arn:aws:cloudfront::033216807884:key-value-store/1bd98db4-05f4-4aa1-9d6b-324f6e513832` |
| CF Function | `us-east-1SimpleDynamicOriunctionViewerReq35F07A0A` |
| Health Checker | `geo-routing-health-checker` (EventBridge every 60s) |
| Maintenance API | `https://8llszk7jic.execute-api.us-east-1.amazonaws.com/maintenance` |
| Origin 0 Lambda | `SimpleDynamicOriginRoutin-Origin0NodejsFunction529-VgxgmqPIBfMo` |
| Origin 1 Lambda | `SimpleDynamicOriginRoutin-Origin1NodejsFunction975-Pq0yox0O7JkZ` |
| Origin 2 Lambda | `SimpleDynamicOriginRoutin-Origin2NodejsFunction052-HvPwKCnKHQsk` |
| ALB 0 | `Simple-Origi-qQX3a9ALUo1P-1885041626.us-east-1.elb.amazonaws.com` |
| ALB 1 | `Simple-Origi-9M4sckIkxijJ-1516111109.us-east-1.elb.amazonaws.com` |
| ALB 2 | `Simple-Origi-O914SMpD40HE-731436583.us-east-1.elb.amazonaws.com` |
| S3 Demo Bucket | `simpledynamicoriginroutings-demodemobucketb018ff5f-4qxqz6jtf4n7` |
| CDK Stack | `SimpleDynamicOriginRoutingStack` |

## Geo-Routing Rules

| Region | Countries | Origin |
|--------|-----------|--------|
| Americas | US, CA, MX, BR, AR, etc. | Origin 0 |
| EMEA | GB, DE, FR, IL, AE, ZA, etc. | Origin 1 |
| APAC | JP, AU, IN, SG, KR, etc. | Origin 2 |
| Unmapped/Unknown | AQ, XX, etc. | Default (Origin 0) |

## Routing Toggle Flow

1. Test page toggle → API writes directly to KVS `origin_X_enabled`
2. CF Function reads KVS → routes to fallback if disabled
3. Health Checker Lambda (background, every 60s) detects actual origin failures
4. If origin unhealthy → updates KVS → CF routes to fallback
5. **~5-10s edge propagation** (no SSM, no polling delay)


## Authentication

Maintenance API requires: `Authorization: Bearer <token>`
Token stored in: AWS Secrets Manager `geo-routing/maintenance-api-key`

## Quick Commands

```bash
# Disable origin 1
curl -X POST https://8llszk7jic.execute-api.us-east-1.amazonaws.com/maintenance \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(aws secretsmanager get-secret-value --secret-id geo-routing/maintenance-api-key --query SecretString --output text)" \
  -d '{"originId":1,"enabled":false}'

# Manually trigger health check
aws lambda invoke --function-name geo-routing-health-checker --payload '{}' /tmp/hc.json && cat /tmp/hc.json

# Check KVS state
aws cloudfront-keyvaluestore list-keys --kvs-arn "arn:aws:cloudfront::033216807884:key-value-store/1bd98db4-05f4-4aa1-9d6b-324f6e513832"
```

## Source

Based on: https://github.com/aws-samples/sample-simple-dynamic-origin-routing-using-amazon-cloudfront-functions
