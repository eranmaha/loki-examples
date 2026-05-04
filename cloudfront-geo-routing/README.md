# CloudFront Geo-Based Origin Routing with Automated Health Checks

## Overview

Dynamic origin selection using **CloudFront Functions + Key Value Store**, with CloudWatch Synthetics canaries for automated health monitoring and failover.

## Architecture

```
                    ┌─────────────────────────┐
                    │   CloudFront Function    │
                    │  (reads KVS for routing) │
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                   ▼
         Origin 0           Origin 1            Origin 2
        (Americas)           (EMEA)              (APAC)
              │                  │                   │
              └──────────────────┼──────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  Synthetics Canaries     │
                    │  (health check /health)  │
                    └────────────┬────────────┘
                                 │ fails
                    ┌────────────▼────────────┐
                    │  CloudWatch Alarm        │
                    │  (SuccessPercent = 0)    │
                    └────────────┬────────────┘
                                 │ SNS
                    ┌────────────▼────────────┐
                    │  Failover Lambda         │
                    │  (updates KVS)          │
                    └─────────────────────────┘
```

## Components

| Component | Description |
|-----------|-------------|
| **CF Function** | Geo-routes requests by country → region → origin, checks KVS for enabled/disabled |
| **Origin Lambdas (×3)** | Simulated origins with `/health` endpoint (SSM-controlled) |
| **Synthetics Canaries (×3)** | Health checks every 60s per origin |
| **CloudWatch Alarms (×3)** | Fires when canary SuccessPercent drops to 0% |
| **Failover Lambda** | Triggered by alarm → disables origin in KVS; re-enables on recovery |
| **Maintenance API** | Manual toggle endpoint for demos |
| **KVS** | Source of truth for origin enabled/disabled state |

## Installation

### Prerequisites

- AWS CLI v2
- An AWS account with permissions for Lambda, CloudFront, CloudWatch, IAM, SSM, SNS, S3
- A Lambda layer with `botocore[crt]` (required for CloudFront KVS API)

### Step 1: Build the CRT Layer

The Failover Lambda needs `botocore[crt]` to write to CloudFront Key Value Store. Build it:

```bash
mkdir -p /tmp/crt-layer/python
cd /tmp/crt-layer/python
pip install boto3 botocore awscrt -t . --upgrade
cd /tmp/crt-layer
zip -r botocore-crt-layer.zip python/
```

Publish as a Lambda layer:

```bash
aws lambda publish-layer-version \
  --layer-name botocore-crt-arm64 \
  --zip-file fileb:///tmp/crt-layer/botocore-crt-layer.zip \
  --compatible-runtimes python3.9 \
  --compatible-architectures arm64
```

Note the `LayerVersionArn` from the output.

### Step 2: Deploy the CloudFormation Stack

```bash
aws cloudformation create-stack \
  --stack-name geo-routing-demo \
  --template-body file://cloudformation/geo-routing-stack.yaml \
  --parameters \
    ParameterKey=ProjectName,ParameterValue=geo-routing-demo \
    ParameterKey=AlertEmail,ParameterValue=your@email.com \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

Wait for completion:

```bash
aws cloudformation wait stack-create-complete --stack-name geo-routing-demo
```

### Step 3: Attach the CRT Layer to Failover Lambda

```bash
aws lambda update-function-configuration \
  --function-name geo-routing-demo-failover \
  --layers <LayerVersionArn-from-step-1> \
  --runtime python3.9
```

### Step 4: Initialize KVS with Origin URLs

Get the origin Function URLs from stack outputs:

```bash
aws cloudformation describe-stacks --stack-name geo-routing-demo \
  --query 'Stacks[0].Outputs' --output table
```

Then populate the KVS (use the KVS ARN from outputs):

```bash
KVS_ARN="<KvsArn from outputs>"
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)

# Set origin URLs
aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --key "0" --value "<Origin0Url>" --if-match $ETAG
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --key "1" --value "<Origin1Url>" --if-match $ETAG
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --key "2" --value "<Origin2Url>" --if-match $ETAG
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --key "__default__" --value "<Origin0Url>" --if-match $ETAG

# Set all origins as enabled
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --key "origin_0_enabled" --value "true" --if-match $ETAG
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --key "origin_1_enabled" --value "true" --if-match $ETAG
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --key "origin_2_enabled" --value "true" --if-match $ETAG
```

### Step 5: Create CloudFront Distribution

Create a CloudFront distribution with:
- The KVS associated to a CloudFront Function (use `src/viewer-request.js`)
- Origins pointing to your actual backend services
- The Function triggered on viewer-request

## Testing the Failover

### Simulate an Origin Failure

```bash
# Make origin 1 unhealthy
aws ssm put-parameter --name "/geo-routing/origin-1-healthy" --value "false" --type String --overwrite

# Within 60s, the canary will detect the failure:
# - Canary runs → gets HTTP 503 from /health
# - CloudWatch alarm fires (SuccessPercent = 0%)
# - SNS triggers Failover Lambda
# - Failover Lambda sets KVS origin_1_enabled = false
# - CloudFront Function routes EMEA traffic to default origin
```

### Verify Failover

```bash
# Check alarm state
aws cloudwatch describe-alarms --alarm-names geo-routing-demo-canary-alarm-origin-1 \
  --query 'MetricAlarms[0].StateValue'

# Check KVS
aws cloudfront-keyvaluestore list-keys --kvs-arn <KVS_ARN> \
  --query 'Items[?Key==`origin_1_enabled`]'
```

### Recovery

```bash
# Re-enable origin 1
aws ssm put-parameter --name "/geo-routing/origin-1-healthy" --value "true" --type String --overwrite

# Within 60s:
# - Canary passes → alarm goes to OK
# - Failover Lambda re-enables origin in KVS
# - Traffic routes normally again
```

## Manual Toggle (Maintenance API)

```bash
# Disable origin 2
curl -X POST https://<MaintenanceApiUrl>/maintenance \
  -H "Content-Type: application/json" \
  -d '{"originId": 2, "enabled": false}'
```

## Cleanup

```bash
aws cloudformation delete-stack --stack-name geo-routing-demo
```

## Geo-Routing Rules

| Region | Countries | Origin |
|--------|-----------|--------|
| Americas | US, CA, MX, BR, AR, CL, CO, etc. | Origin 0 |
| EMEA | GB, DE, FR, IL, AE, ZA, NG, etc. | Origin 1 |
| APAC | JP, AU, IN, SG, KR, CN, etc. | Origin 2 |
| Unmapped | AQ, XX, etc. | Default (Origin 0) |
