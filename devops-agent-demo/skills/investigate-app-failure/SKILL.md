---
name: investigate-app-failure
description: Investigation procedures for application failures in the devops-agent-demo
  serverless application. Use this skill when CloudWatch alarms fire for Lambda error
  rates, timeout rates, or when the application returns 5xx errors. Covers IAM permission
  issues, timeout injection via SSM parameters, DSQL connectivity, and Lambda invocation
  failures.
---

# Investigate Application Failure

Use this skill when CloudWatch alarms fire for the devops-agent-demo application,
indicating Lambda errors, timeouts, or connectivity issues.

## Context

- **Architecture:** CloudFront → API Gateway → Lambda (Node.js 20, arm64) → Aurora DSQL
- **Region:** us-east-1
- **Lambda Function:** `devops-agent-demo-app`
- **Lambda Role:** `devops-agent-demo-lambda-role`
- **DSQL Cluster:** Available via environment variable in the Lambda
- **SSM Parameter:** `/devops-agent-demo/sleep-seconds` (controls artificial delay for fault injection)

## Step 1: Identify the alarm

Check which alarms are in ALARM state to understand the failure mode:
- `devops-agent-demo-error-rate` — Lambda invocation errors exceeding threshold
- `devops-agent-demo-timeout-rate` — Lambda timeouts exceeding threshold

## Step 2: Check Lambda errors in CloudWatch Logs

Query the Lambda log group `/aws/lambda/devops-agent-demo-app` for recent ERROR entries
from the last 5 minutes. Look for patterns in the error messages.

## Step 3: Diagnose based on error type

### Permission / AccessDenied errors

If logs contain "permission", "AccessDenied", or "dsql:DbConnectAdmin":
- The Lambda's IAM role has lost its DSQL access policy
- Remediation: Restore the `dsql:DbConnectAdmin` permission on the Lambda role for the DSQL cluster ARN

### Timeout errors

If logs show "Task timed out" or duration approaches the configured timeout:
1. Check the SSM parameter `/devops-agent-demo/sleep-seconds` for injected delay
2. If value > 0, this is an injected fault — set it back to "0"
3. If value is already 0, check DSQL cluster health and network connectivity

### Connection errors

If logs show connection refused, DNS resolution failure, or network timeout to DSQL:
- Verify the DSQL cluster is active
- Check if the Lambda has internet access (for DSQL data plane which requires public endpoint)
- Verify IAM authentication token generation is working

## Step 4: Verify the fix

After applying remediation, invoke the Lambda directly with a test payload targeting
the `/data` endpoint. Confirm it returns a 200 status with valid transaction data.

## Step 5: Report findings

Summarize:
1. Which alarm fired and when
2. Root cause identified (permission loss / timeout injection / connectivity)
3. Remediation applied
4. Verification result (success/failure)
