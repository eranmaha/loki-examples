# Investigate OpenSearch Application Errors

## When to Use
Use this skill when CloudWatch alarms fire for application errors and you need to investigate **applicative** (non-infrastructure) issues logged in OpenSearch Serverless.

## Context
The application logs transactions to `app-transactions` index and errors to `app-errors` index in an OpenSearch Serverless (AOSS) collection. Errors are categorized as:
- **data_corruption**: Malformed data written (wrong field types, missing fields)
- **business_logic**: Invalid state transitions, constraint violations
- **infrastructure**: Connection failures, timeouts (handled by other skills)

## Investigation Steps

### 1. Query Recent Errors
```bash
# Get recent errors from the last hour (replace COLLECTION_ENDPOINT)
ENDPOINT="${OPENSEARCH_ENDPOINT}"

# Using curl with SigV4 (via awscurl or similar)
awscurl --service aoss --region us-east-1 \
  -X POST "$ENDPOINT/app-errors/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "range": {
        "@timestamp": {
          "gte": "now-1h"
        }
      }
    },
    "sort": [{"@timestamp": {"order": "desc"}}],
    "size": 50
  }'
```

### 2. Categorize by Error Type
```bash
awscurl --service aoss --region us-east-1 \
  -X POST "$ENDPOINT/app-errors/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "size": 0,
    "query": {"range": {"@timestamp": {"gte": "now-1h"}}},
    "aggs": {
      "by_type": {
        "terms": {"field": "error_type"}
      }
    }
  }'
```

### 3. Check for Data Corruption
```bash
awscurl --service aoss --region us-east-1 \
  -X POST "$ENDPOINT/app-errors/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"term": {"error_type": "data_corruption"}},
          {"range": {"@timestamp": {"gte": "now-1h"}}}
        ]
      }
    }
  }'
```

### 4. Check for Business Logic Errors
```bash
awscurl --service aoss --region us-east-1 \
  -X POST "$ENDPOINT/app-errors/_search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "bool": {
        "must": [
          {"term": {"error_type": "business_logic"}},
          {"range": {"@timestamp": {"gte": "now-1h"}}}
        ]
      }
    }
  }'
```

## Remediation

### Data Corruption
1. Check SSM parameter `/{project}/data-corruption` — if set to `true`, this is an injected fault
2. Clear the flag: `aws ssm put-parameter --name "/{project}/data-corruption" --value "false" --overwrite`
3. Identify corrupted documents in `app-transactions` by querying for type mismatches
4. Consider reindexing if corruption is widespread

### Business Logic Errors
1. Check SSM parameter `/{project}/business-logic-error` — if set to `true`, this is an injected fault
2. Clear the flag: `aws ssm put-parameter --name "/{project}/business-logic-error" --value "false" --overwrite`
3. If not injected, review application logic for race conditions or invalid state machines
4. Check upstream services for out-of-order event delivery

### Clearing All Fault Injections
```bash
# Via the API
curl -X POST "https://{cloudfront-domain}/inject" \
  -H "Content-Type: application/json" \
  -d '{"action": "restore_app_errors"}'
```

## Escalation
If errors persist after clearing fault flags, escalate to the application team — this indicates a real bug rather than injected faults.
