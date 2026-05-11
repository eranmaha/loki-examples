# AWS Agent Hub — AgentCore Research & Resilience

AI-powered multi-agent web application backed by Amazon Bedrock AgentCore. Features two specialized agents with Cognito authentication, CloudFront delivery, and full observability.

## Live Demo

🌐 **URL:** `https://dtt5rtdxrg7b6.cloudfront.net`

## Agents

| Agent | Purpose | Model |
|-------|---------|-------|
| 🔍 **Research Agent** | General-purpose AI research assistant | Claude Sonnet 4.6 |
| 🛡️ **Infra Resilience Specialist** | AWS infrastructure resilience analysis, DR planning, PRD review | Claude Sonnet 4.6 |

## Features

- **Agent Selector** — switch between specialized agents
- **PRD File Upload** — attach architecture/PRD documents for resilience analysis
- **Cognito Auth** — JWT-based authentication (admin-only registration)
- **Observability** — OpenTelemetry tracing via AgentCore + CloudWatch
- **Inline Fallback** — fast responses via Bedrock InvokeInlineAgent

## Architecture

```
User → CloudFront (HTTPS)
         ├── / → S3 (static frontend)
         └── /api/* → HTTP API Gateway (JWT auth)
                          └── Lambda (VPC, arm64)
                                ├── Bedrock InvokeInlineAgent (primary, fast)
                                └── AgentCore Runtime (observability, tracing)

AgentCore Runtimes (Strands Agents framework):
  ├── myresearchagent (research, browser tool)
  └── awsInfraRecSpec (resilience, skills-loaded context)

Auth: Cognito User Pool → JWT Authorizer on API Gateway
Observability: OpenTelemetry → CloudWatch Gen AI Observability
```

## Project Structure

```
agentcore-research/
├── ARCHITECTURE.md          # Detailed architecture description
├── architecture.drawio      # Visual diagram (dark theme, AWS style)
├── frontend/
│   └── index.html           # Chat UI with agent selector + file upload
├── infrastructure/
│   ├── bin/app.ts           # CDK entry point
│   ├── lib/stack.ts         # CDK stack (CloudFront, Cognito, Lambda, API GW)
│   ├── lambda/index.py      # Lambda handler (multi-agent routing)
│   ├── package.json
│   └── tsconfig.json
├── agent/                   # Research Agent (Strands framework)
│   ├── agentcore.json       # AgentCore config
│   └── myresearchagent/
│       ├── main.py          # Agent entry point
│       ├── pyproject.toml
│       ├── model/           # Model loading
│       └── mcp_client/      # MCP client module
└── agent-resilience/        # Resilience Agent
    ├── agentcore.json       # AgentCore config (observability enabled)
    ├── main.py              # Agent entry point with skills context
    └── resilience-skills.md # Resilience knowledge base
```

## Deployment

### Prerequisites
- AWS CDK bootstrapped (`npx cdk bootstrap aws://033216807884/us-east-1`)
- Node.js 20+, Python 3.10+
- `credential_process` in `~/.aws/config` for EC2 instances

### Deploy Infrastructure
```bash
cd infrastructure
npm install
npx cdk deploy
```

### Deploy Agents
```bash
# Research Agent
cd ../agent && agentcore deploy -y

# Resilience Agent  
cd ../agent-resilience && agentcore deploy -y
```

### Create Users
```bash
aws cognito-idp admin-create-user \
  --user-pool-id <pool-id> \
  --username user@example.com \
  --user-attributes Name=email,Value=user@example.com Name=email_verified,Value=true \
  --temporary-password 'TempPass123!' \
  --message-action SUPPRESS
```

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| CloudFront | ~$1-5 |
| NAT Gateway | ~$35 |
| Lambda | ~$0-5 |
| API Gateway | ~$1-3 |
| Cognito | Free (< 50k MAU) |
| Bedrock (Sonnet 4.6) | Variable (per token) |
| AgentCore Runtime (x2) | Variable (per invoke) |

## Observability

- **Traces:** CloudWatch → Gen AI Observability → Agent Core
- **Logs:** `/aws/bedrock-agentcore/runtimes/<runtime-id>`
- **Metrics:** Invocation count, latency, errors
- **Console:** `agentcore traces list` / `agentcore logs`

## Security

- Cognito JWT authentication (no self-signup)
- Lambda in VPC private subnets
- HTTPS enforced via CloudFront
- IAM least-privilege policies
- No hardcoded secrets

## License

Internal use — AWS account 033216807884
