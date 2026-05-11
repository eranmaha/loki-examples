# Research Agent — Architecture

## Overview

A serverless web application that provides an AI-powered research assistant backed by Amazon Bedrock. Users authenticate via Amazon Cognito, interact through a chat-style web UI served from CloudFront, and receive AI-generated research responses via a Lambda backend.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud (us-east-1)                        │
│                                                                       │
│  ┌──────────────┐     ┌─────────────┐                               │
│  │  CloudFront  │────▶│  S3 Bucket  │  (Static frontend)            │
│  │  Distribution│     └─────────────┘                               │
│  │              │                                                     │
│  │   /api/*     │────▶┌──────────────────┐                          │
│  └──────────────┘     │ HTTP API Gateway │                          │
│                       │ (JWT Authorizer) │                          │
│                       └────────┬─────────┘                          │
│                                │                                     │
│         ┌──────────────────────┼──────────────────────┐             │
│         │          VPC (10.0.0.0/16)                   │             │
│         │                      │                       │             │
│         │  ┌───────────────────▼────────────────┐     │             │
│         │  │   Private Subnets (10.0.10-11.0/24) │     │             │
│         │  │                                     │     │             │
│         │  │  ┌─────────────────────────┐       │     │             │
│         │  │  │  Lambda Function        │       │     │             │
│         │  │  │  (research-agent-invoke) │       │     │             │
│         │  │  │  Python 3.13 / arm64    │       │     │             │
│         │  │  └───────────┬─────────────┘       │     │             │
│         │  │              │                      │     │             │
│         │  └──────────────┼──────────────────────┘     │             │
│         │                 │                             │             │
│         │  ┌──────────────▼───────────┐                │             │
│         │  │  NAT Gateway             │                │             │
│         │  │  (Public Subnet)         │                │             │
│         │  └──────────────┬───────────┘                │             │
│         └─────────────────┼────────────────────────────┘             │
│                           │                                           │
│                           ▼                                           │
│              ┌─────────────────────────┐                             │
│              │  Amazon Bedrock         │                             │
│              │  (InvokeInlineAgent)    │                             │
│              │  Claude Sonnet 4        │                             │
│              └─────────────────────────┘                             │
│                                                                       │
│  ┌───────────────────┐                                               │
│  │  Amazon Cognito   │  (User authentication)                       │
│  │  User Pool        │                                               │
│  └───────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Service | Purpose |
|-----------|---------|---------|
| Frontend | S3 + CloudFront | Static HTML/JS chat UI with Cognito auth |
| Auth | Cognito User Pool | JWT-based authentication, admin-only registration |
| API | HTTP API Gateway | Routes `/api/invoke` with JWT authorizer |
| Backend | Lambda (Python, arm64) | Invokes Bedrock inline agent API |
| AI | Amazon Bedrock | Claude Sonnet 4 foundation model |
| Networking | VPC + NAT Gateway | Lambda runs in private subnets, outbound via NAT |
| CDN | CloudFront | HTTPS termination, S3 origin + API origin routing |

## Security

- **Authentication:** Cognito JWT tokens required for all API calls
- **Network:** Lambda in private subnets, no direct internet exposure
- **IAM:** Least-privilege Lambda role with only Bedrock invoke permissions
- **Transport:** HTTPS everywhere (CloudFront enforced)
- **Registration:** Admin-only (no self-signup)
- **CORS:** Controlled via Lambda response headers

## Data Flow

1. User opens `https://<cloudfront-domain>` → loads static HTML/JS from S3
2. User authenticates via Cognito (email/password) → receives JWT ID token
3. User sends a question → `POST /api/invoke` with JWT in Authorization header
4. API Gateway validates JWT → forwards to Lambda in VPC
5. Lambda calls `bedrock:InvokeInlineAgent` via NAT Gateway
6. Bedrock returns AI response → Lambda returns JSON → UI displays result

## Deployment

Infrastructure is managed via **AWS CDK (TypeScript)**:

```bash
cd webapp/infrastructure
npm install
npx cdk deploy
```

Stack name: `ResearchAgentWeb`

## Cost Considerations

| Resource | Est. Monthly Cost |
|----------|-------------------|
| CloudFront | ~$1-5 (low traffic) |
| NAT Gateway | ~$35 (hourly + data) |
| Lambda | ~$0-5 (pay per invoke) |
| API Gateway | ~$1-3 |
| Cognito | Free tier (< 50k MAU) |
| Bedrock | Variable (per token) |

**Note:** NAT Gateway is the fixed-cost baseline (~$35/mo). For production, consider VPC endpoints for Bedrock to eliminate NAT costs.

## Future Enhancements

- Switch to AgentCore runtime endpoint (VPC mode) for persistent agent sessions
- Add browser tool for live web research
- Implement conversation history (DynamoDB)
- Add streaming responses (WebSocket API)
- Custom domain with Route 53
- WAF on CloudFront
