# DevOps Agent Demo

Serverless application demonstrating automated incident detection and remediation with AWS DevOps Agent.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────────┐     ┌──────────────────┐
│  CloudFront │────▶│ API Gateway  │────▶│  Lambda (App)  │────▶│  Aurora DSQL     │
└─────────────┘     └──────────────┘     └────────────────┘     └──────────────────┘
                           │                      │
                           │                      ▼
                           │              ┌────────────────────┐
                           │              │ OpenSearch          │
                           │              │ Serverless (AOSS)  │
                           │              │ • app-transactions  │
                           │              │ • app-errors        │
                           │              └────────────────────┘
                           │
                    ┌──────────────┐
                    │   Injector   │
                    │   Lambda     │
                    └──────────────┘

┌────────────────┐     ┌─────────┐     ┌────────────────┐     ┌──────────────────┐
│ CloudWatch     │────▶│   SNS   │────▶│ Webhook Bridge │────▶│  DevOps Agent    │
│ Alarms         │     └─────────┘     │    Lambda      │     │  (Frontier)      │
└────────────────┘                     └────────────────┘     └──────────────────┘

┌─────────────────────────────────────────────────────────┐
│  VPC (Private Subnets, No NAT)                         │
│  VPC Endpoints: DSQL, AOSS, SSM, Logs, S3, Secrets    │
│  Lambda functions run inside VPC                       │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- Node.js 20+ (for local Lambda development)
- Access to Aurora DSQL cluster
- DevOps Agent webhook secret

## Setup

```bash
# Install Lambda dependencies
cd lambda && npm install && cd ..

# Initialize Terraform
terraform init

# Set webhook secret (don't commit this!)
export TF_VAR_webhook_secret="your-secret-here"

# Plan and apply
terraform plan
terraform apply
```

## How to Demo

### Normal Operation
1. Open the CloudFront URL (output: `cloudfront_url`)
2. Click "Fetch Data" — app queries DSQL and logs to OpenSearch
3. Use "Auto-Fetch" for continuous traffic

### Fault Injection Scenarios

| Scenario | Button | Effect | Detection |
|----------|--------|--------|-----------|
| Permission failure | Remove DSQL Permission | Lambda can't connect to DB | CloudWatch alarm → DevOps Agent |
| Timeout | Inject Timeout | Lambda sleeps 20s (timeout=15s) | Duration alarm → DevOps Agent |
| Data corruption | Inject Data Corruption | Malformed data in OpenSearch | App-errors index logged |
| Business logic | Inject Business Logic Error | Invalid state transitions | App-errors index + CloudWatch alarm |

### Demo Flow
1. Start auto-fetch to generate baseline traffic
2. Inject a fault (e.g., "Inject Business Logic Error")
3. Watch errors appear in the event log
4. DevOps Agent receives alarm via webhook
5. Agent uses skills to investigate and remediate
6. Click "Restore App Errors" to clear faults

## Fault Injection Guide

### Infrastructure Faults
- **Remove DSQL Permission**: Deletes IAM inline policy → immediate DB failures
- **Inject Timeout**: Sets SSM param to 20s sleep → Lambda timeout (15s limit)

### Application Faults
- **Data Corruption**: Sets SSM flag → writes wrong field types to OpenSearch `app-transactions`
- **Business Logic Error**: Sets SSM flag → simulates invalid state transitions, logs to `app-errors`

### Restoration
- **Restore DSQL**: Re-attaches IAM policy
- **Restore Timeout**: Resets sleep param to 0
- **Restore App Errors**: Clears both corruption and business logic flags

## OpenSearch Indexes

### app-transactions
Logs every successful `/data` request:
```json
{
  "@timestamp": "2025-01-01T00:00:00Z",
  "request_path": "/data",
  "status": 200,
  "duration_ms": 45,
  "dsql_rows_returned": 10
}
```

### app-errors
Logs application-level errors:
```json
{
  "@timestamp": "2025-01-01T00:00:00Z",
  "error_type": "business_logic|data_corruption|infrastructure",
  "message": "Description of error",
  "severity": "ERROR|WARNING|CRITICAL",
  "context": {}
}
```

## Project Structure

```
├── main.tf           # Core infrastructure (Lambda, API GW, CloudWatch, SNS)
├── vpc.tf            # VPC, subnets, VPC endpoints
├── opensearch.tf     # OpenSearch Serverless collection & policies
├── terraform.tfvars  # Variable values
├── lambda/
│   ├── index.js      # App Lambda (DSQL + OpenSearch)
│   ├── injector.js   # Fault injection Lambda
│   └── webhook-bridge.js  # SNS → DevOps Agent webhook
└── skills/
    ├── investigate-app-failure.md
    └── investigate-opensearch-app-errors.md
```
