# Email Draft: CloudFront Geo-Routing with Automated Health Checks

**Subject:** CloudFront Latency-Aware Geo-Routing with Automated Failover — Implementation Guide

---

Hi,

Following our discussion, here's the full technical breakdown of the CloudFront geo-routing solution with automated health checks and failover.

## Architecture Overview

The solution routes viewer requests to the nearest regional origin based on the viewer's country, with automated failover when an origin becomes unhealthy.

**Components:**
- **CloudFront Distribution** — 3 origins (Americas, EMEA, APAC)
- **CloudFront Function (viewer-request)** — geo-routing logic using CloudFront KeyValueStore
- **CloudFront KeyValueStore** — stores origin domain mappings and enabled/disabled state
- **CloudWatch Synthetics Canaries** — health checks per origin (1-minute intervals)
- **CloudWatch Alarms** — triggers failover after 3 consecutive health check failures
- **Failover Lambda** — updates KVS to disable/re-enable origins automatically

## How It Works

### 1. Geo-Routing (viewer-request CloudFront Function)

Every request passes through a CloudFront Function at the edge. The function:

1. Reads the viewer's country from the `CloudFront-Viewer-Country` header
2. Maps the country to a region (Americas → Origin 0, EMEA → Origin 1, APAC → Origin 2)
3. Checks KVS if that origin is enabled
4. If enabled → uses `cf.updateRequestOrigin()` to route to the correct origin
5. If disabled → falls back to Origin 0 (Americas) as the default

```javascript
import cf from 'cloudfront';
const kvsHandle = cf.kvs();

// Country-to-region mapping
const AMERICAS = ['US','CA','MX','BR','AR','CL','CO','PE',...];
const EMEA = ['GB','DE','FR','IT','ES','IL','AE','SA','ZA',...];
const APAC = ['CN','JP','KR','IN','AU','NZ','SG','MY',...];

async function handler(event) {
  const request = event.request;
  const cc = request.headers['cloudfront-viewer-country']?.value || '';
  
  let originId = getOriginForCountry(cc); // returns '0', '1', or '2'
  
  // Check if origin is enabled in KVS
  const enabled = await kvsHandle.get('origin_' + originId + '_enabled');
  if (enabled === 'false') {
    originId = '0'; // fallback to default
  }
  
  // Route to correct origin
  const domain = await kvsHandle.get('origin_' + originId + '_domain');
  cf.updateRequestOrigin({ domainName: domain, originId: 'origin-' + originId });
  
  return request;
}
```

**Key point:** `cf.updateRequestOrigin()` switches between pre-configured origins in the distribution. All origins must be declared in the CloudFront distribution config.

### 2. CloudFront Distribution Configuration

The distribution has 3 origins, each pointing to a separate API Gateway (or ALB/origin server):

```yaml
Origins:
  - Id: origin-0
    DomainName: americas-api.execute-api.us-east-1.amazonaws.com
    OriginPath: /prod
    CustomOriginConfig:
      OriginProtocolPolicy: https-only
  - Id: origin-1
    DomainName: emea-api.execute-api.eu-west-1.amazonaws.com
    OriginPath: /prod
    CustomOriginConfig:
      OriginProtocolPolicy: https-only
  - Id: origin-2
    DomainName: apac-api.execute-api.ap-northeast-1.amazonaws.com
    OriginPath: /prod
    CustomOriginConfig:
      OriginProtocolPolicy: https-only
```

The default cache behavior targets `origin-0` and attaches the CloudFront Function:

```yaml
DefaultCacheBehavior:
  TargetOriginId: origin-0
  FunctionAssociations:
    - EventType: viewer-request
      FunctionARN: !GetAtt GeoRoutingFunction.FunctionARN
```

### 3. CloudFront KeyValueStore (KVS)

KVS stores the routing configuration (accessible from CF Functions with sub-ms latency):

| Key | Value | Purpose |
|-----|-------|---------|
| `origin_0_domain` | `americas-api.execute-api...` | Origin 0 domain for routing |
| `origin_1_domain` | `emea-api.execute-api...` | Origin 1 domain for routing |
| `origin_2_domain` | `apac-api.execute-api...` | Origin 2 domain for routing |
| `origin_0_enabled` | `true` / `false` | Origin 0 health status |
| `origin_1_enabled` | `true` / `false` | Origin 1 health status |
| `origin_2_enabled` | `true` / `false` | Origin 2 health status |

**Failover is instant** — updating a KVS value immediately affects all edge locations without needing a distribution deployment.

### 4. Health Checks (CloudWatch Synthetics)

Three Synthetics canaries run every 60 seconds, each hitting its origin's `/health` endpoint:

```javascript
// Canary script (Node.js Synthetics)
const synthetics = require('Synthetics');
const http = require('http');

exports.handler = async () => {
  const response = await http.get('https://origin-api/health');
  if (response.statusCode !== 200) {
    throw new Error(`Health check failed: ${response.statusCode}`);
  }
};
```

The `/health` endpoint on each origin checks its own readiness (database connectivity, dependencies, etc.) and returns:
- **200** — healthy
- **503** — unhealthy

### 5. Alarm Configuration

Each canary has a CloudWatch Alarm:

```yaml
MetricName: SuccessPercent
Namespace: CloudWatchSynthetics
Period: 60 seconds
EvaluationPeriods: 3
DatapointsToAlarm: 3
Threshold: 0 (SuccessPercent ≤ 0%)
TreatMissingData: notBreaching
```

**This means: 3 consecutive failures (3 minutes) before triggering failover.** This prevents transient blips from causing unnecessary switches.

### 6. Failover Lambda

When an alarm transitions to ALARM state, it publishes to SNS, which invokes the failover Lambda:

```python
import boto3

kvs = boto3.client("cloudfront-keyvaluestore")

def handler(event, context):
    message = json.loads(event["Records"][0]["Sns"]["Message"])
    alarm_name = message["AlarmName"]
    new_state = message["NewStateValue"]
    
    origin_id = extract_origin_id(alarm_name)  # '0', '1', or '2'
    enabled = (new_state == "OK")  # True = re-enable, False = disable
    
    # Update KVS
    desc = kvs.describe_key_value_store(KvsARN=KVS_ARN)
    kvs.put_key(
        KvsARN=KVS_ARN,
        Key=f"origin_{origin_id}_enabled",
        Value=str(enabled).lower(),
        IfMatch=desc["ETag"]
    )
```

**Auto-recovery:** When the alarm returns to OK (3 consecutive successes), the same Lambda re-enables the origin automatically.

## Failover Timeline

```
T+0:00  Origin 1 becomes unhealthy
T+1:00  Canary check #1 fails
T+2:00  Canary check #2 fails
T+3:00  Canary check #3 fails → Alarm triggers → Lambda disables Origin 1 in KVS
T+3:01  All EMEA traffic routes to Origin 0 (fallback) ← failover complete

T+5:00  Origin 1 recovers
T+6:00  Canary check #1 passes
T+7:00  Canary check #2 passes
T+8:00  Canary check #3 passes → Alarm clears → Lambda re-enables Origin 1
T+8:01  EMEA traffic routes back to Origin 1 ← recovery complete
```

## Cost Estimate

| Component | Monthly Cost |
|-----------|-------------|
| CloudFront Function | Included (first 10M invocations free) |
| KeyValueStore | ~$0.50/month (reads included in CF Function pricing) |
| Synthetics Canaries (×3, 1/min) | ~$3.60/month ($0.0012/run × 3 × 43,200 runs) |
| CloudWatch Alarms (×3) | ~$0.30/month |
| Failover Lambda | ~$0.00 (invoked only on state changes) |
| **Total monitoring overhead** | **~$4.40/month** |

## Deployment

The entire solution is deployed via a single CloudFormation stack:

```bash
./deploy.sh geo-routing-prod alerts@yourcompany.com
```

## Live Demo

Test page (interactive): https://d2zpel5l84ohew.cloudfront.net/test

You can simulate a failure by setting an origin to unhealthy and watching the failover in real time.

---

Let me know if you'd like to walk through the deployment together or if you have questions about adapting this to your specific origin architecture (ALB, ECS, multi-region).

Best regards
