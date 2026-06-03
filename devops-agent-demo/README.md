# DevOps Agent Demo

Serverless application demonstrating automated incident detection and remediation with AWS DevOps Agent, featuring OpenSearch MCP Server integration for private subnet connectivity.

## Architecture

```
                                    ┌─────────────────────────────────────────────┐
                                    │         OUTSIDE VPC (Internet)              │
┌──────────┐   ┌────────────┐      │                                             │
│   User   │──▶│ CloudFront │──▶ API Gateway ──▶ App Lambda ──▶ Aurora DSQL      │
└──────────┘   └────────────┘      │                 │                            │
                                    │                 │ async invoke               │
                                    │                 ▼                            │
                                    │          Injector Lambda                     │
                                    │          (fault injection)                   │
                                    └─────────────────────────────────────────────┘
                                                      │
                                                      │ Lambda:InvokeFunction (async)
                                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  VPC (Private Subnets, No NAT)                                                  │
│  VPC Endpoints: AOSS, DSQL, SSM, Logs, Secrets Manager, S3                     │
│                                                                                  │
│  ┌─────────────────────┐         ┌──────────────────────────┐                  │
│  │ OpenSearch Logger    │────────▶│  OpenSearch Serverless    │                  │
│  │ Lambda (Node.js)    │  SigV4  │  (TIMESERIES Collection)  │                  │
│  └─────────────────────┘         │  • app-transactions       │                  │
│                                   │  • app-errors             │                  │
│  ┌─────────────────────┐         │                           │                  │
│  │ MCP Server Lambda   │────────▶│                           │                  │
│  │ (Python, Streamable │  SigV4  └──────────────────────────┘                  │
│  │  HTTP via Func URL) │                                                        │
│  └─────────────────────┘                                                        │
└─────────────────────────────────────────────────────────────────────────────────┘
        ▲                                              ▲
        │ MCP Protocol                                 │
        │ (Streamable HTTP)                            │
        │                                              │
┌───────┴──────────┐     ┌─────────┐     ┌────────────┴───────┐
│  DevOps Agent    │◀────│   SNS   │◀────│  CloudWatch Alarms │
│  (Frontier AI)   │     └─────────┘     └────────────────────┘
│                  │           ▲
│  Investigates +  │     ┌─────┴──────┐
│  Remediates      │     │  Webhook   │
└──────────────────┘     │  Bridge    │
                         └────────────┘
```

## Key Design Decisions

- **Dual-function approach**: App Lambda stays outside VPC (DSQL has no data-plane VPC endpoint), OpenSearch access is fully private via VPC-based Logger Lambda
- **No NAT Gateway**: All VPC-based Lambdas access AWS services through VPC endpoints only
- **Async logging**: App Lambda invokes Logger asynchronously (fire-and-forget) — zero latency impact on user requests
- **MCP Server in VPC**: DevOps Agent queries OpenSearch through the MCP protocol over a Lambda Function URL, keeping data plane fully private

## Prerequisites

- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- Node.js 20+ (for local Lambda development)
- Python 3.12+ (for MCP server packaging)
- Access to Aurora DSQL cluster
- DevOps Agent space + webhook secret

## Setup

```bash
# Install Lambda dependencies
cd lambda && npm install && cd ..

# Initialize Terraform
terraform init

# Configure variables (edit terraform.tfvars)
# Required: devops_agent_webhook_url, webhook_secret, dsql_cluster_endpoint, dsql_cluster_arn

# Deploy
terraform apply -var="webhook_secret=YOUR_SECRET"
```

## Configuration (terraform.tfvars)

| Variable | Description | Example |
|----------|-------------|---------|
| `region` | AWS region | `us-east-1` |
| `account_id` | AWS account ID | `033216807884` |
| `project_name` | Resource name prefix | `devops-agent-demo` |
| `dsql_cluster_endpoint` | DSQL cluster hostname | `xxx.dsql.us-east-1.on.aws` |
| `dsql_cluster_arn` | DSQL cluster ARN | `arn:aws:dsql:...` |
| `devops_agent_webhook_url` | DevOps Agent webhook | `https://event-ai...` |
| `webhook_secret` | HMAC signing key (sensitive) | — |
| `devops_agent_space_id` | Agent space ID | `e8246657-...` |
| `enable_mcp_server` | Deploy MCP server | `true` |
| `mcp_server_auth_type` | Function URL auth | `AWS_IAM` or `NONE` |

## How to Demo

### Post-Install: DevOps Agent Setup

After `terraform apply` completes, configure the DevOps Agent to connect to your MCP server:

1. **Create a Private Connection** (console)
   - Go to the DevOps Agent console → your space → Settings → Connections
   - Create a new connection:
     - Type: Private (VPC)
     - VPC: Select the VPC created by Terraform (`devops-agent-demo-vpc`)
     - Subnets: Select the private subnets
     - Security Group: Select `devops-agent-demo-vpce-sg`
   - Note: If your MCP server Function URL auth is `NONE`, you can skip the private connection and use a public connection instead (the Lambda Function URL is internet-accessible, while OpenSearch remains private behind the VPC)

2. **Register the MCP Server** (console)
   - Go to the DevOps Agent console → your space → Tools → MCP Servers
   - Add a new MCP server:
     - Name: `opensearch-logs`
     - URL: `<mcp_server_function_url>/mcp` (from Terraform output)
     - Transport: Streamable HTTP
     - Connection: Select the private connection from step 1 (or public if using `NONE` auth)
     - Auth: AWS IAM SigV4 (if `mcp_server_auth_type = AWS_IAM`)

3. **Upload Investigation Skills** (console)
   - Go to the DevOps Agent console → your space → Skills
   - Upload `skills/investigate-app-failure.md` (infra errors)
   - Upload `skills/investigate-opensearch-app-errors.md` (applicative errors)

4. **Configure Webhook** (console)
   - Go to the DevOps Agent console → your space → Integrations → Webhooks
   - Create a generic webhook (should already exist if using an existing space)
   - Copy the webhook URL + secret into your `terraform.tfvars` / env vars

### Normal Operation
1. Open the CloudFront URL (output: `test_page_url`)
2. Click "Fetch Data" — app queries DSQL, logs transaction to OpenSearch (async)
3. Use "Auto-Fetch" for continuous traffic generation

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
5. Agent connects to OpenSearch MCP Server (private subnet)
6. Agent queries `app-errors` index, categorizes the issue, provides remediation
7. Click "Restore App Errors" to clear faults

## OpenSearch MCP Server

Deploys the [opensearch-mcp-server-py](https://github.com/opensearch-project/opensearch-mcp-server-py) as a Lambda behind a Function URL. DevOps Agent connects to it using the MCP protocol to query logs in the private OpenSearch collection.

### Connecting DevOps Agent

```json
{
  "mcpServers": {
    "opensearch": {
      "url": "<mcp_server_function_url>/mcp",
      "transport": "streamable-http"
    }
  }
}
```

If using `AWS_IAM` auth (default), sign requests with SigV4 for the `lambda` service.

### Available MCP Tools
- `ListIndexTool` — List all indexes
- `SearchIndexTool` — Query with DSL
- `IndexMappingTool` — Get index mappings
- `ClusterHealthTool` — Cluster status
- `CountTool` — Document counts

## OpenSearch Indexes

### app-transactions
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
├── main.tf                # Core infra (Lambdas, API GW, CloudWatch, SNS)
├── vpc.tf                 # VPC, subnets, VPC endpoints (no NAT)
├── opensearch.tf          # OpenSearch Serverless collection & access policies
├── mcp-server.tf          # MCP Server Lambda + Function URL
├── terraform.tfvars       # Variable values (account-specific)
├── lambda/
│   ├── index.js           # App Lambda — DSQL queries + async logger invoke
│   ├── opensearch-logger.js  # Logger Lambda (VPC) — writes to AOSS
│   ├── injector.js        # Fault injection (IAM/SSM manipulation)
│   ├── webhook-bridge.js  # SNS → DevOps Agent HMAC webhook
│   └── package.json
├── mcp-server/
│   ├── handler.py         # Mangum ASGI adapter for opensearch-mcp-server-py
│   └── requirements.txt
├── skills/
│   ├── investigate-app-failure.md          # Infra error investigation skill
│   └── investigate-opensearch-app-errors.md # Applicative error skill
└── docs/
    └── solution-architecture.drawio        # Full architecture diagram
```

## Outputs

| Output | Description |
|--------|-------------|
| `cloudfront_url` | App frontend URL |
| `test_page_url` | Direct link to test page |
| `api_url` | API Gateway endpoint |
| `opensearch_endpoint` | AOSS collection URL |
| `mcp_server_function_url` | MCP Server endpoint |
| `mcp_server_function_name` | MCP Server Lambda name |
| `lambda_function_name` | App Lambda name |
| `alarm_error_rate` | Error rate alarm name |
| `alarm_timeout` | Timeout alarm name |

## Deploying to Another Account

1. Create a DSQL cluster in the target account
2. Set up a DevOps Agent space + webhook
3. Update `terraform.tfvars` with new values
4. `terraform init && terraform apply -var="webhook_secret=..."`

The architecture is fully parameterized — no hardcoded account IDs or ARNs.
