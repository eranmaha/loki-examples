#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Geo Routing DNS — Failure Injection / Recovery Script
# Usage:
#   ./failover.sh inject <region>    — make origin return 503 on /health
#   ./failover.sh revert <region>    — restore origin to healthy
#   ./failover.sh status             — show all health check statuses
#
# Regions: americas | emea | apac
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

ACTION="${1:-help}"
REGION="${2:-}"

# Map region names to AWS regions and function names
declare -A AWS_REGIONS=(
  [americas]="us-east-1"
  [emea]="eu-west-1"
  [apac]="ap-southeast-1"
)

declare -A FUNCTION_NAMES=(
  [americas]="geo-routing-dns-origin-americas"
  [emea]="geo-routing-dns-origin-emea"
  [apac]="geo-routing-dns-origin-apac"
)

declare -A HEALTH_CHECKS=(
  [americas]="591d4d0d-044d-45d9-acd1-9ea6f73b0bad"
  [emea]="240f864c-4c0e-4386-b245-f47dbb4ff5e4"
  [apac]="ab055823-7ae9-4c5b-950f-1264914cbc4e"
)

declare -A LABELS=(
  [americas]="Americas (us-east-1)"
  [emea]="EMEA (eu-west-1)"
  [apac]="APAC (ap-southeast-1)"
)

HEALTHY_CODE='import json, os
REGION = os.environ.get("AWS_REGION", "unknown")
LABEL = os.environ.get("ORIGIN_LABEL", f"Origin ({REGION})")

def handler(event, context):
    path = event.get("rawPath", "/")
    if path == "/health":
        return {"statusCode": 200, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"status": "healthy", "region": REGION})}
    return {"statusCode": 200, "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,OPTIONS"}, "body": json.dumps({"message": f"Hello from {LABEL}", "region": REGION, "label": LABEL, "healthy": True})}
'

UNHEALTHY_CODE='import json, os
REGION = os.environ.get("AWS_REGION", "unknown")
LABEL = os.environ.get("ORIGIN_LABEL", f"Origin ({REGION})")

def handler(event, context):
    path = event.get("rawPath", "/")
    if path == "/health":
        return {"statusCode": 503, "headers": {"Content-Type": "application/json"}, "body": json.dumps({"status": "unhealthy", "region": REGION})}
    return {"statusCode": 503, "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,OPTIONS"}, "body": json.dumps({"message": f"UNAVAILABLE - {LABEL}", "region": REGION, "label": LABEL, "healthy": False})}
'

inject_error() {
  local region_name="$1"
  local aws_region="${AWS_REGIONS[$region_name]}"
  local fn_name="${FUNCTION_NAMES[$region_name]}"
  local label="${LABELS[$region_name]}"

  echo "🔴 Injecting failure into ${label}..."
  
  local tmpdir=$(mktemp -d)
  echo "$UNHEALTHY_CODE" > "$tmpdir/origin.py"
  (cd "$tmpdir" && zip -q origin.zip origin.py)

  aws lambda update-function-code --function-name "$fn_name" --region "$aws_region" \
    --zip-file "fileb://$tmpdir/origin.zip" --query 'LastModified' --output text > /dev/null

  aws lambda update-function-configuration --function-name "$fn_name" --region "$aws_region" \
    --handler origin.handler --query 'Handler' --output text > /dev/null

  rm -rf "$tmpdir"

  echo "✅ Error injected. ${label} now returns 503 on /health"
  echo "⏱️  Route 53 will detect failure in ~30s (3 checks × 10s interval)"
}

revert_error() {
  local region_name="$1"
  local aws_region="${AWS_REGIONS[$region_name]}"
  local fn_name="${FUNCTION_NAMES[$region_name]}"
  local label="${LABELS[$region_name]}"

  echo "🟢 Reverting ${label} to healthy..."

  local tmpdir=$(mktemp -d)
  echo "$HEALTHY_CODE" > "$tmpdir/origin.py"
  (cd "$tmpdir" && zip -q origin.zip origin.py)

  aws lambda update-function-code --function-name "$fn_name" --region "$aws_region" \
    --zip-file "fileb://$tmpdir/origin.zip" --query 'LastModified' --output text > /dev/null

  aws lambda update-function-configuration --function-name "$fn_name" --region "$aws_region" \
    --handler origin.handler --query 'Handler' --output text > /dev/null

  rm -rf "$tmpdir"

  echo "✅ Reverted. ${label} now returns 200 on /health"
  echo "⏱️  Route 53 will detect recovery in ~30s"
}

show_status() {
  echo "═══════════════════════════════════════════"
  echo "  Route 53 Health Check Status"
  echo "═══════════════════════════════════════════"
  for region_name in americas emea apac; do
    local hc_id="${HEALTH_CHECKS[$region_name]}"
    local label="${LABELS[$region_name]}"
    local status=$(aws route53 get-health-check-status --health-check-id "$hc_id" \
      --query 'HealthCheckObservations[0].StatusReport.Status' --output text 2>/dev/null)
    
    if echo "$status" | grep -q "Success"; then
      echo "  ✅ ${label}: HEALTHY"
    else
      echo "  ❌ ${label}: UNHEALTHY"
    fi
  done
  echo "═══════════════════════════════════════════"
}

case "$ACTION" in
  inject)
    if [[ -z "$REGION" || ! "${AWS_REGIONS[$REGION]+x}" ]]; then
      echo "Usage: $0 inject <americas|emea|apac>"
      exit 1
    fi
    inject_error "$REGION"
    echo ""
    sleep 2
    show_status
    ;;
  revert)
    if [[ -z "$REGION" || ! "${AWS_REGIONS[$REGION]+x}" ]]; then
      echo "Usage: $0 revert <americas|emea|apac>"
      exit 1
    fi
    revert_error "$REGION"
    echo ""
    sleep 2
    show_status
    ;;
  status)
    show_status
    ;;
  help|*)
    echo "Geo Routing DNS — Failure Injection Tool"
    echo ""
    echo "Usage:"
    echo "  $0 inject <region>   Inject 503 error (simulate outage)"
    echo "  $0 revert <region>   Restore to healthy"
    echo "  $0 status            Show current health check status"
    echo ""
    echo "Regions: americas | emea | apac"
    echo ""
    echo "Example demo flow:"
    echo "  1. $0 status                    # Show all healthy"
    echo "  2. $0 inject emea               # Break EMEA"
    echo "  3. (wait 30s, show R53 failover in test client)"
    echo "  4. $0 revert emea               # Restore EMEA"
    echo "  5. (wait 30s, show R53 recovery)"
    ;;
esac
