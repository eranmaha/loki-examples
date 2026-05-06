# DevOps Agent Demo — Serverless App with Error Injection

Serverless application (CloudFront → API Gateway → Lambda → Aurora DSQL) with built-in error injection for demonstrating AI DevOps agents.

## Architecture

```
Browser → CloudFront → API Gateway → Lambda → Aurora DSQL
                                        ↑
                                   SSM Parameter (sleep injection)
                                   IAM Policy (permission injection)
                                        ↓
                              CloudWatch Alarm (3 errors)
                                        ↓
                                   SNS → Webhook
                                        ↓
                                   DevOps Agent
```

## Error Injection Scenarios

### Scenario 1: Permission Failure
- **Inject:** Removes `dsql:DbConnectAdmin` IAM policy from Lambda role
- **Effect:** Lambda returns 500 on every DB call
- **Alarm:** Triggers after 3 errors in 1 minute
- **Agent task:** Investigate CloudWatch logs, identify IAM permission issue, restore policy

### Scenario 2: Timeout Injection
- **Inject:** Sets SSM parameter to make Lambda sleep 20s (timeout = 15s)
- **Effect:** Lambda times out on every request
- **Alarm:** Triggers when duration >= 14s
- **Agent task:** Investigate timeout, find SSM parameter injection, restore to 0

## Deployment

```bash
cd devops-agent-demo/lambda
npm install

cd ..
terraform init
terraform apply
```

Update `terraform.tfvars` with your DevOps agent webhook URL before deploying.

## Usage

1. Open the test page URL (from terraform output)
2. Click "Fetch Data" to verify app works
3. Click "Auto-Fetch (every 3s)" to generate continuous traffic
4. Click an error injection button
5. Wait ~1 minute for the alarm to trigger
6. Watch the DevOps agent investigate and fix

## Restore

Use the "Restore" buttons in the test page, or:

```bash
# Restore DSQL permission
aws iam put-role-policy --role-name devops-agent-demo-lambda-role \
  --policy-name dsql-access \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dsql:DbConnectAdmin"],"Resource":"*"}]}'

# Restore timeout
aws ssm put-parameter --name /devops-agent-demo/sleep-seconds --value "0" --type String --overwrite
```

## DevOps Agent Skills

The agent should have skills to:
1. Read CloudWatch Logs for the Lambda function
2. Describe CloudWatch Alarms
3. Check IAM policies on Lambda roles
4. Read/write SSM Parameters
5. Update Lambda function configuration
