# CloudFront Dynamic Geo-Based Origin Routing

> Deploy CloudFront distributions with multiple origins and route traffic based on viewer geography using CloudFront Functions + Key Value Store.

## When to Use
- Multi-origin CloudFront setups with geo-based routing
- Origin failover / maintenance mode without DNS changes
- Dynamic origin selection at the edge (sub-millisecond)
- Customer demos showing programmable edge routing

## Architecture

```
Browser → CloudFront → CF Function (viewer-request)
                            ↓
                        KVS Lookup (country → region → origin domain)
                            ↓
                    cf.updateRequestOrigin({ domainName })
                            ↓
                    Origin ALB/Server (Americas | EMEA | APAC)
```

## Key Concepts

### CloudFront Functions (Runtime 2.0)
- Execute at edge in V8 isolates — **no cold starts**, sub-ms startup
- `cf.updateRequestOrigin()` can route to any domain registered as an origin on the distribution
- `console.log()` outputs to CloudWatch at `/aws/cloudfront/function/<name>`
- Max compute: 100% utilization = throttled. Keep KVS lookups minimal (3-4 per request approaches limits)

### Key Value Store (KVS)
- Globally replicated, sub-millisecond reads from CF Functions
- Updated via `cloudfront-keyvaluestore` API (not CF Function itself)
- Propagation: ~5-10 seconds globally
- No cache invalidation needed — changes take effect automatically
- Max: 5MB total, keys ≤512 bytes, values ≤1KB
- **ETag required** for writes (optimistic concurrency)

### Critical Constraints
- `cf.updateRequestOrigin()` only works with domains **already registered as origins** on the distribution
- KVS values populated via CDK `ImportSource.fromInline()` do NOT resolve CDK tokens (ALB DNS names are tokens) — use post-deploy API to set actual values
- CloudFront-Viewer-Country header must be allowlisted in cache policy or origin request policy to reach the function

## Geo Mapping Pattern

```javascript
// CF Function: map country → region → origin
const AMERICAS = ['US','CA','MX','BR','AR',...];
const EMEA = ['GB','DE','FR','IL','AE','ZA',...];
const APAC = ['JP','AU','IN','SG','KR',...];

// KVS keys:
// "0" → ALB0 DNS (Americas origin)
// "1" → ALB1 DNS (EMEA origin)
// "2" → ALB2 DNS (APAC origin)
// "__default__" → fallback origin DNS
// "origin_0_enabled" → "true"/"false" (maintenance toggle)
```

## Maintenance Mode
Toggle an origin off via CLI — traffic falls back to default:
```bash
KVS_ARN="arn:aws:cloudfront::<account>:key-value-store/<id>"
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn "$KVS_ARN" --query ETag --output text)
aws cloudfront-keyvaluestore put-key --kvs-arn "$KVS_ARN" --if-match "$ETAG" --key origin_1_enabled --value false
```

## Fallback Logging
Unmapped countries log structured JSON to CloudWatch:
```json
{"event":"geo_routing_fallback","reason":"unmapped_country_XX","country":"XX","timestamp":"..."}
```
View: CloudWatch → Log Groups → `/aws/cloudfront/function/<name>`

## Deployment Notes (without Route 53)
If no domain available:
1. Deploy origins (ALBs) normally
2. Create CloudFront distribution with ALL origin ALBs registered as origins
3. Use KVS populated via API (not CDK inline) with actual ALB DNS names
4. CF Function reads KVS and routes via `cf.updateRequestOrigin()`

## Latency Breakdown (typical)
| Component | Time |
|-----------|------|
| CF Function + KVS reads | ~1-2ms |
| CF edge → origin (same region) | ~30-50ms |
| TLS handshake (first request) | ~15ms |
| Network: viewer → nearest POP | varies by location |

## Console Locations
- **KVS:** CloudFront → Key Value Stores (left nav)
- **Function metrics:** CloudFront → Functions → [function] → Metrics
- **Function logs:** CloudWatch → `/aws/cloudfront/function/<name>`
- **Compute utilization:** CloudWatch metric `FunctionComputeUtilization` (namespace AWS/CloudFront, dimension Region=Global)

## Testing with Simulated Countries
Use `x-viewer-country` custom header (must be forwarded to function via origin request policy):
```bash
curl -H "x-viewer-country: IL" https://<dist>.cloudfront.net/api
curl -H "x-viewer-country: JP" https://<dist>.cloudfront.net/api
curl -H "x-viewer-country: XX" https://<dist>.cloudfront.net/api  # fallback
```

## Reference Implementation
- GitHub: `aws-samples/sample-simple-dynamic-origin-routing-using-amazon-cloudfront-functions`
- Our deployed demo: https://d2y11z8qnhnm6.cloudfront.net
- Stack: `SimpleDynamicOriginRoutingStack` (CDK, us-east-1)
