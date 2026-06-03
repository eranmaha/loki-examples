# Testing Guide — DevOps Agent Demo

This guide explains how to simulate errors, verify they appear in OpenSearch, and
trigger the DevOps Agent to investigate.

## Prerequisites

- Demo fully deployed (`terraform apply` completed)
- MCP server connected to DevOps Agent (verified with "Test" in console)
- Skills imported: `investigate-app-failure.zip` and `investigate-opensearch-app-errors.zip`
- Webhook configured and active in Agent Space

## Quick Reference

| Variable | Value |
|----------|-------|
| CloudFront URL | `terraform output -raw cloudfront_url` |
| API Gateway URL | `terraform output -raw api_url` |
| MCP Server IP | `terraform output -raw mcp_server_private_ip` |

## Test Scenarios

---

### Scenario 1: Data Corruption Errors

**What it does:** App writes malformed data (wrong field types, missing required fields)
to the `app-errors` index in OpenSearch with `error_type: data_corruption`.

#### Step 1: Inject the fault

```bash
# Via curl
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "inject_data_corruption"}'

# Expected response:
# {"success":true,"message":"🔴 Data corruption ENABLED - malformed data will be written to OpenSearch"}
```

Or use the demo UI: Open `$(terraform output -raw cloudfront_url)` in a browser and
click **"Inject Data Corruption"**.

#### Step 2: Generate traffic (to produce errors)

```bash
# Hit the app endpoint several times to generate corrupted writes
for i in {1..10}; do
  curl -s "$(terraform output -raw cloudfront_url)/data" > /dev/null
  sleep 1
done
```

Each request will write a corrupted document to OpenSearch AND log an error.

#### Step 3: Verify errors appear in OpenSearch

From the MCP server EC2 (via SSM):
```bash
PYTHONPATH=/opt/mcp-server python3.12 -c "
from mcp_server_opensearch.tool_executor import execute_tool
# Or use curl to the MCP server:
"
```

Or test via the MCP server directly:
```bash
curl -k -X POST https://127.0.0.1:8080/mcp/ \
  -H "x-api-key: $(terraform output -raw mcp_server_api_key)" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "id": 1,
    "params": {
      "name": "search_index",
      "arguments": {
        "index": "app-errors",
        "body": "{\"query\":{\"bool\":{\"must\":[{\"term\":{\"error_type\":\"data_corruption\"}},{\"range\":{\"@timestamp\":{\"gte\":\"now-5m\"}}}]}},\"size\":5}"
      }
    }
  }'
```

#### Step 4: Wait for CloudWatch alarm

The `devops-agent-demo-error-rate` alarm fires when **≥ 3 errors occur within 1 minute**.

Check alarm status:
```bash
aws cloudwatch describe-alarms \
  --alarm-names "devops-agent-demo-error-rate" \
  --query 'MetricAlarms[0].StateValue' --output text
```

#### Step 5: DevOps Agent receives webhook

Once the alarm fires:
1. SNS sends notification to the Webhook Bridge Lambda
2. Bridge Lambda formats and signs the payload
3. DevOps Agent receives the webhook and starts investigating
4. Agent uses the `investigate-opensearch-app-errors` skill
5. Agent queries OpenSearch via MCP tools to analyze the errors

#### Step 6: Watch the investigation

Go to the DevOps Agent console → Agent Space → Investigations tab.
You should see a new investigation triggered by the alarm.

The agent will:
- Query `app-errors` index for recent errors
- Categorize errors by type
- Identify data corruption pattern
- Check SSM parameters for fault injection flags
- Report findings and suggest remediation

#### Step 7: Restore (clean up)

```bash
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "restore_app_errors"}'
```

---

### Scenario 2: Business Logic Errors

**What it does:** App generates invalid state transitions logged as
`error_type: business_logic` in OpenSearch.

#### Inject

```bash
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "inject_business_logic_error"}'
```

#### Generate traffic

```bash
for i in {1..10}; do
  curl -s "$(terraform output -raw cloudfront_url)/data" > /dev/null
  sleep 1
done
```

#### Restore

```bash
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "restore_app_errors"}'
```

---

### Scenario 3: Lambda Timeout (Permission Fault)

**What it does:** Removes DSQL IAM permission from the Lambda role, causing
AccessDenied errors on every request.

#### Inject

```bash
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "remove_dsql_permission"}'
```

#### Generate traffic

```bash
for i in {1..5}; do
  curl -s "$(terraform output -raw cloudfront_url)/data"
  sleep 2
done
# Expect 500 errors with AccessDenied
```

#### Restore

```bash
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "restore_dsql_permission"}'
```

---

### Scenario 4: Timeout Injection

**What it does:** Adds a 20-second sleep to every Lambda invocation, causing
timeout errors (Lambda timeout is typically 30s).

#### Inject

```bash
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "inject_timeout"}'
```

#### Generate traffic

```bash
# These will be slow (20s+) and may timeout
for i in {1..3}; do
  curl -s --max-time 35 "$(terraform output -raw cloudfront_url)/data"
  sleep 1
done
```

#### Restore

```bash
curl -X POST "$(terraform output -raw cloudfront_url)/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "restore_timeout"}'
```

---

## Where to Track Errors

| Location | What to check |
|----------|--------------|
| CloudFront URL `/` | Demo UI with inject buttons and live status |
| CloudWatch Alarms | `devops-agent-demo-error-rate`, `devops-agent-demo-timeout-rate` |
| CloudWatch Logs | `/aws/lambda/devops-agent-demo-app` — Lambda execution logs |
| OpenSearch `app-errors` | Error documents (query via MCP tools) |
| OpenSearch `app-transactions` | Successful transactions (baseline) |
| DevOps Agent Console | Investigations tab — shows triggered investigations |
| SSM Parameters | `/devops-agent-demo/sleep-seconds`, `/devops-agent-demo/data-corruption`, `/devops-agent-demo/business-logic-error` |

## Timing

- **Fault injection** → immediate (next request generates errors)
- **Errors in OpenSearch** → ~1-2 seconds after request (async Lambda)
- **CloudWatch alarm** → 1-2 minutes (evaluation period)
- **Webhook to DevOps Agent** → seconds after alarm state change
- **Investigation start** → seconds after webhook received
- **Investigation complete** → 30-120 seconds (depends on tool calls)

## Troubleshooting Tests

| Issue | Check |
|-------|-------|
| No errors in OpenSearch | Logger Lambda in VPC — check AOSS VPC endpoint exists |
| Alarm not firing | Check metric namespace/name in CloudWatch console |
| Webhook not triggering | Check Lambda logs for webhook-bridge function |
| Agent not investigating | Verify webhook is active in Agent Space settings |
| Agent can't query OpenSearch | Test MCP connection from DevOps Agent console |
