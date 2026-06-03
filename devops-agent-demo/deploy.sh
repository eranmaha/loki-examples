#!/bin/bash
set -euo pipefail

# ─── DevOps Agent Demo — Deploy Script ──────────────────────────────────────
# Reads configuration from environment variables and deploys via Terraform.
#
# Required env vars:
#   ACCOUNT_ID               - AWS account ID (e.g., 954976329732)
#   DSQL_CLUSTER_ENDPOINT    - DSQL cluster hostname
#   DSQL_CLUSTER_ARN         - DSQL cluster ARN
#   DEVOPS_AGENT_WEBHOOK_URL - DevOps Agent webhook endpoint
#   WEBHOOK_SECRET           - HMAC signing key for webhook
#
# Optional env vars:
#   AWS_REGION               - AWS region (default: us-east-1)
#   PROJECT_NAME             - Resource prefix (default: devops-agent-demo)
#   DEVOPS_AGENT_SPACE_ID    - Agent space ID (default: e8246657-9b81-4f09-8dd9-7d9d97142afa)
#   ENABLE_MCP_SERVER        - Deploy MCP server (default: true)
#   MCP_SERVER_AUTH_TYPE     - Function URL auth type (default: AWS_IAM)
#   LAMBDA_TIMEOUT           - App Lambda timeout seconds (default: 15)
#   TF_ACTION                - plan|apply|destroy (default: apply)
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[deploy]${NC} $*"; }
warn() { echo -e "${YELLOW}[deploy]${NC} $*"; }
err()  { echo -e "${RED}[deploy]${NC} $*" >&2; exit 1; }

# ─── Validate required vars ─────────────────────────────────────────────────

check_var() {
  if [[ -z "${!1:-}" ]]; then
    err "Missing required env var: $1\n  export $1=\"...\""
  fi
}

check_var ACCOUNT_ID
check_var DSQL_CLUSTER_ENDPOINT
check_var DSQL_CLUSTER_ARN
check_var DEVOPS_AGENT_WEBHOOK_URL
check_var WEBHOOK_SECRET

# ─── Defaults ────────────────────────────────────────────────────────────────

REGION="${AWS_REGION:-us-east-1}"
PROJECT="${PROJECT_NAME:-devops-agent-demo}"
SPACE_ID="${DEVOPS_AGENT_SPACE_ID:-e8246657-9b81-4f09-8dd9-7d9d97142afa}"
MCP_ENABLED="${ENABLE_MCP_SERVER:-true}"
TIMEOUT="${LAMBDA_TIMEOUT:-15}"
ACTION="${TF_ACTION:-apply}"

# ─── Display config ─────────────────────────────────────────────────────────

log "Configuration:"
echo "  Account ID:       $ACCOUNT_ID"
echo "  Region:           $REGION"
echo "  Project:          $PROJECT"
echo "  DSQL Endpoint:    $DSQL_CLUSTER_ENDPOINT"
echo "  Webhook URL:      $DEVOPS_AGENT_WEBHOOK_URL"
echo "  Agent Space:      $SPACE_ID"
echo "  MCP Server:       $MCP_ENABLED"
echo "  Lambda Timeout:   ${TIMEOUT}s"
echo "  Action:           $ACTION"
echo ""

# ─── Change to script directory ──────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─── Install Lambda dependencies ────────────────────────────────────────────

if [[ ! -d "lambda/node_modules" ]]; then
  log "Installing Lambda dependencies..."
  (cd lambda && npm install --omit=dev)
fi

# ─── Terraform init ─────────────────────────────────────────────────────────

if [[ ! -d ".terraform" ]]; then
  log "Initializing Terraform..."
  terraform init
else
  log "Terraform already initialized"
fi

# ─── Build tfvars ────────────────────────────────────────────────────────────

TF_VARS=(
  -var="region=$REGION"
  -var="project_name=$PROJECT"
  -var="account_id=$ACCOUNT_ID"
  -var="dsql_cluster_endpoint=$DSQL_CLUSTER_ENDPOINT"
  -var="dsql_cluster_arn=$DSQL_CLUSTER_ARN"
  -var="devops_agent_webhook_url=$DEVOPS_AGENT_WEBHOOK_URL"
  -var="webhook_secret=$WEBHOOK_SECRET"
  -var="devops_agent_space_id=$SPACE_ID"
  -var="enable_mcp_server=$MCP_ENABLED"
  -var="lambda_timeout=$TIMEOUT"
)

# ─── Execute ─────────────────────────────────────────────────────────────────

case "$ACTION" in
  plan)
    log "Running terraform plan..."
    terraform plan "${TF_VARS[@]}"
    ;;
  apply)
    log "Running terraform apply..."
    terraform apply -auto-approve "${TF_VARS[@]}"
    echo ""
    log "Deploy complete! Outputs:"
    terraform output
    ;;
  destroy)
    warn "Destroying all resources..."
    terraform destroy -auto-approve "${TF_VARS[@]}"
    ;;
  *)
    err "Invalid TF_ACTION: $ACTION (must be plan|apply|destroy)"
    ;;
esac
