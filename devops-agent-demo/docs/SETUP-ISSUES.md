# DevOps Agent Demo — Setup Issues & Resolutions

Summary of all issues encountered during the OpenSearch MCP Server setup (June 3–4, 2026).

---

## 1. DSQL Has No Data-Plane VPC Endpoint

**Problem:** Lambda in VPC couldn't reach Aurora DSQL. The `com.amazonaws.us-east-1.dsql` endpoint is control-plane only — data connections use a different hostname pattern (`dsql-fnh4`).

**Resolution:** Split into two Lambdas — App Lambda stays *outside* VPC (can reach DSQL directly), OpenSearch Logger Lambda goes *inside* VPC.

---

## 2. AOSS VPC Endpoint Doesn't Support us-east-1a

**Problem:** Creating an AOSS VPC endpoint failed because OpenSearch Serverless only supports `us-east-1b`, `us-east-1c`, `us-east-1d`.

**Resolution:** Filter subnets in Terraform to exclude `us-east-1a` for AOSS endpoint placement:
```hcl
aoss_supported_subnet_ids = [
  for s in aws_subnet.private : s.id
  if contains(["us-east-1b", "us-east-1c", "us-east-1d"], s.availability_zone)
]
```

---

## 3. DevOps Agent MCP Registration Requires HTTPS URL

**Problem:** DevOps Agent private connections require a URL matching `^https://[a-zA-Z0-9.-]+(?::[0-9]+)?(?:/.*)?$`. Lambda Function URLs didn't work.

**Resolution:** Deploy MCP server on EC2 with nginx fronting it with a self-signed TLS cert on port 8080.

---

## 4. DevOps Agent Private Connections Don't Support SigV4

**Problem:** Can't use IAM-based auth for the DevOps Agent → MCP server connection.

**Resolution:** Use API key auth — nginx checks `X-Api-Key` header, key stored in Secrets Manager.

---

## 5. EC2 in Private Subnet Can't pip install

**Problem:** The MCP server EC2 instance has no internet access, so can't install Python packages at boot.

**Resolution:** Pre-build the package (with all dependencies), upload to S3, download via S3 Gateway endpoint in user_data.

---

## 6. Missing SSM VPC Endpoints

**Problem:** Couldn't SSM into the EC2 instance — Session Manager requires `ssmmessages` and `ec2messages` endpoints.

**Resolution:** Added both interface endpoints to the VPC.

---

## 7. Terraform Heredoc Indentation

**Problem:** `<<-EOF` only strips leading *tabs*, not spaces. The shebang (`#!/bin/bash`) in user_data was indented with spaces, making it invalid.

**Resolution:** Ensure shebang is at column 1, or use tabs for indentation inside heredocs.

---

## 8. EC2 user_data Changes Don't Auto-Replace Instance

**Problem:** After fixing user_data in Terraform, `terraform apply` updated the launch config but didn't replace the running instance — it kept running the old broken script.

**Resolution:** Terminate the instance manually and re-apply, or use `terraform apply -replace=aws_instance.mcp_server[0]`.

---

## 9. Missing STS VPC Endpoint

**Problem:** `aws sts get-caller-identity` hung on the MCP server EC2 — it couldn't resolve IAM credentials because there was no STS VPC endpoint.

**Resolution:** Added `com.amazonaws.us-east-1.sts` interface endpoint.

---

## 10. Wrong Environment Variable for Serverless Mode

**Problem:** The systemd service set `OPENSEARCH_IS_SERVERLESS=true`, but the MCP server code reads `AWS_OPENSEARCH_SERVERLESS`. Result: SigV4 signed requests as service `es` instead of `aoss`, causing 403 from OpenSearch Serverless.

**Resolution:** Changed env var to `AWS_OPENSEARCH_SERVERLESS=true` in the systemd unit file.

---

## 11. Missing Index-Level Permissions in AOSS Data Access Policy

**Problem:** The AOSS data access policy for the MCP server role only had collection-level rules. AOSS requires *both* collection-level AND index-level rules to read/write documents.

**Resolution:** Added index-level rule:
```json
{
  "ResourceType": "index",
  "Resource": ["index/devops-agent-demo-logs/*"],
  "Permission": ["aoss:*"]
}
```

---

## 12. No Internet Access for API Spec Downloads

**Problem:** The MCP server (`opensearch-mcp-server-py`) fetches OpenSearch API specification YAML files from GitHub (`raw.githubusercontent.com`) at startup to generate tool definitions. In the private subnet with no NAT, this timed out — resulting in "no tools" in the DevOps Agent.

**Resolution:** Added NAT Gateway (IGW + public subnet + EIP + NAT + private route).

---

## Key Takeaways

| Category | Lesson |
|----------|--------|
| VPC Design | Always check which AZs a service's VPC endpoint supports |
| VPC Design | Private subnets need STS endpoint for IAM credential resolution |
| VPC Design | If your app fetches external resources at startup, you need NAT or pre-cached files |
| AOSS | Data access policies need both `collection` AND `index` resource type rules |
| AOSS | `opensearch-py` defaults to SigV4 service `es` — must explicitly pass `aoss` for serverless |
| Terraform | `user_data` changes don't replace instances — must force replacement |
| Terraform | Heredocs strip tabs only, not spaces |
| MCP Server | The env var is `AWS_OPENSEARCH_SERVERLESS`, not `OPENSEARCH_IS_SERVERLESS` |
| DevOps Agent | Tool discovery is cached per session — start new conversation after fixing MCP server |
