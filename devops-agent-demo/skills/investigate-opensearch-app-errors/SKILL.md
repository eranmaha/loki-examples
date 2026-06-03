---
name: investigate-opensearch-app-errors
description: Investigation procedures for application errors logged in OpenSearch
  Serverless. Use this skill when you need to investigate applicative issues such as
  data corruption, business logic errors, or anomalous error patterns in the app-errors
  index. Use the OpenSearch MCP tools (search_index, list_index, get_index_mapping,
  count) to query error data.
---

# Investigate OpenSearch Application Errors

Use this skill when CloudWatch alarms fire for application errors and you need to
investigate applicative (non-infrastructure) issues by querying error logs stored
in OpenSearch Serverless.

## Context

The application logs to two OpenSearch Serverless indexes:
- **app-transactions** — successful transaction records
- **app-errors** — error events with categorization

Error types:
- **data_corruption** — malformed data (wrong field types, missing fields)
- **business_logic** — invalid state transitions, constraint violations
- **infrastructure** — connection failures, timeouts (handled by other skills)

## Step 1: Query recent errors

Use the `search_index` tool to retrieve errors from the last hour in the `app-errors`
index, sorted by timestamp descending. Limit to 50 results to understand the scope.

Query filter: range on `@timestamp` field, `gte: now-1h`.

## Step 2: Categorize by error type

Use the `search_index` tool with an aggregation on the `error_type` field to get
a breakdown of error categories in the last hour. This reveals whether the issue is
data corruption, business logic, or infrastructure.

## Step 3: Investigate data corruption errors

If data_corruption errors are present:
1. Query for documents where `error_type` equals `data_corruption`
2. Examine the error details for which fields are malformed
3. Check if the SSM parameter `/{project}/data-corruption` is set to `true` (injected fault)
4. Cross-reference with `app-transactions` to find corrupted records

## Step 4: Investigate business logic errors

If business_logic errors are present:
1. Query for documents where `error_type` equals `business_logic`
2. Look for patterns (specific transaction types, time correlation)
3. Check if the SSM parameter `/{project}/business-logic-error` is set to `true` (injected fault)
4. If not injected, look for race conditions or upstream event ordering issues

## Step 5: Check error rate trend

Use the `count` tool on `app-errors` with a time range to compare current error rate
against the previous hour. A spike indicates an acute issue; steady errors suggest
a persistent bug.

## Remediation

### Injected faults (demo scenarios)

Clear fault injection flags via SSM parameters:
- Data corruption: set `/{project}/data-corruption` to `false`
- Business logic: set `/{project}/business-logic-error` to `false`

Alternatively, call the application's restore endpoint: `POST /inject` with body
`{"action": "restore_app_errors"}`.

### Real errors

If errors persist after clearing fault flags:
1. Review recent code deployments for regressions
2. Check upstream service health
3. Escalate to the application team with the error samples from OpenSearch

## Step 6: Report findings

Summarize:
1. Error breakdown by type and count
2. Time of onset and correlation with deployments or changes
3. Whether this was an injected fault or real issue
4. Remediation applied and current status
