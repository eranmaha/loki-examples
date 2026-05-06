# DevOps Agent Demo — Investigation Skill

## Context
You are monitoring a serverless application: `devops-agent-demo-app`
- **Architecture:** CloudFront → API Gateway → Lambda (Node.js 20, arm64) → Aurora DSQL
- **Region:** us-east-1
- **Lambda Function:** `devops-agent-demo-app`
- **Lambda Role:** `devops-agent-demo-lambda-role`
- **DSQL Cluster:** `zntxnmjv6gxlrwznxhbmxrboza.dsql.us-east-1.on.aws`
- **SSM Parameter:** `/devops-agent-demo/sleep-seconds` (controls artificial delay)

## When Alarm Fires

### Step 1: Identify the alarm
```bash
aws cloudwatch describe-alarms --alarm-names "devops-agent-demo-error-rate" "devops-agent-demo-timeout-rate" \
  --query 'MetricAlarms[?StateValue==`ALARM`].{Name:AlarmName,Reason:StateReason}' --output table
```

### Step 2: Check Lambda errors in CloudWatch Logs
```bash
aws logs filter-log-events \
  --log-group-name "/aws/lambda/devops-agent-demo-app" \
  --start-time $(date -d '5 min ago' +%s000) \
  --filter-pattern "ERROR" \
  --query 'events[].message' --output text
```

### Step 3: Diagnose based on error type

#### If error contains "permission" or "AccessDenied" or "dsql:DbConnectAdmin":
The Lambda lost its DSQL IAM permission. Fix:
```bash
aws iam put-role-policy \
  --role-name devops-agent-demo-lambda-role \
  --policy-name dsql-access \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dsql:DbConnectAdmin"],"Resource":"arn:aws:dsql:us-east-1:033216807884:cluster/zntxnmjv6gxlrwznxhbmxrboza"}]}'
```

#### If error contains "Task timed out" or duration is near timeout:
Check for injected sleep:
```bash
aws ssm get-parameter --name "/devops-agent-demo/sleep-seconds" --query 'Parameter.Value' --output text
```
If value > 0, restore it:
```bash
aws ssm put-parameter --name "/devops-agent-demo/sleep-seconds" --value "0" --type String --overwrite
```

### Step 4: Verify fix
```bash
# Invoke Lambda directly to test
aws lambda invoke --function-name devops-agent-demo-app \
  --cli-binary-format raw-in-base64-out \
  --payload '{"rawPath":"/data","requestContext":{"http":{"method":"GET"}},"headers":{}}' \
  /tmp/test-output.json && cat /tmp/test-output.json
```

### Step 5: Report
Notify the operator with:
- What alarm fired
- Root cause identified
- Fix applied
- Verification result
