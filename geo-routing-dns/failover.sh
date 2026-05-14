#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Geo Routing DNS — Failure Injection / Recovery Script
#
# Usage:
#   ./failover.sh inject <region> [--profile <aws-profile>]
#   ./failover.sh revert <region> [--profile <aws-profile>]
#   ./failover.sh status [--profile <aws-profile>]
#
# Regions: americas | emea | apac
#
# Examples:
#   ./failover.sh status                        # Check health (default profile)
#   ./failover.sh inject emea                   # Break EMEA origin (default profile)
#   ./failover.sh revert emea                   # Restore EMEA origin
#   ./failover.sh inject apac --profile prod    # Break APAC using 'prod' AWS profile
#   ./failover.sh status --profile my-account   # Check status with specific profile
#
# Demo flow:
#   1. ./failover.sh status                     # Verify all healthy
#   2. ./failover.sh inject emea                # Simulate EMEA outage
#   3. (wait ~30s, observe R53 failover in test client)
#   4. ./failover.sh revert emea                # Restore EMEA
#   5. (wait ~30s, observe R53 recovery)
# ═══════════════════════════════════════════════════════════════

set -eo pipefail

ACTION="${1:-help}"
REGION="${2:-}"
PROFILE_FLAG=""

# Parse --profile flag
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE_FLAG="--profile $2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# If REGION was --profile, clear it
if [[ "$REGION" == "--profile" ]]; then
  REGION=""
fi

# Helper: get AWS region for origin name
get_aws_region() {
  case "$1" in
    americas) echo "us-east-1" ;;
    emea) echo "eu-west-1" ;;
    apac) echo "ap-southeast-1" ;;
    *) echo "" ;;
  esac
}

# Helper: get Lambda function name
get_function_name() {
  echo "geo-routing-dns-origin-$1"
}

# Helper: get health check ID
get_health_check_id() {
  case "$1" in
    americas) echo "591d4d0d-044d-45d9-acd1-9ea6f73b0bad" ;;
    emea) echo "240f864c-4c0e-4386-b245-f47dbb4ff5e4" ;;
    apac) echo "ab055823-7ae9-4c5b-950f-1264914cbc4e" ;;
  esac
}

# Helper: get label
get_label() {
  case "$1" in
    americas) echo "Americas (us-east-1)" ;;
    emea) echo "EMEA (eu-west-1)" ;;
    apac) echo "APAC (ap-southeast-1)" ;;
  esac
}

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
  local aws_region=$(get_aws_region "$region_name")
  local fn_name=$(get_function_name "$region_name")
  local label=$(get_label "$region_name")

  echo "🔴 Injecting failure into ${label}..."

  local tmpdir=$(mktemp -d)
  echo "$UNHEALTHY_CODE" > "$tmpdir/origin.py"
  (cd "$tmpdir" && zip -q origin.zip origin.py)

  aws $PROFILE_FLAG lambda update-function-code --function-name "$fn_name" --region "$aws_region" \
    --zip-file "fileb://$tmpdir/origin.zip" --query 'LastModified' --output text > /dev/null

  aws $PROFILE_FLAG lambda update-function-configuration --function-name "$fn_name" --region "$aws_region" \
    --handler origin.handler --query 'Handler' --output text > /dev/null

  rm -rf "$tmpdir"

  echo "✅ Error injected. ${label} now returns 503 on /health"
  echo "⏱️  Route 53 will detect failure in ~30s (3 checks × 10s interval)"
}

revert_error() {
  local region_name="$1"
  local aws_region=$(get_aws_region "$region_name")
  local fn_name=$(get_function_name "$region_name")
  local label=$(get_label "$region_name")

  echo "🟢 Reverting ${label} to healthy..."

  local tmpdir=$(mktemp -d)
  echo "$HEALTHY_CODE" > "$tmpdir/origin.py"
  (cd "$tmpdir" && zip -q origin.zip origin.py)

  aws $PROFILE_FLAG lambda update-function-code --function-name "$fn_name" --region "$aws_region" \
    --zip-file "fileb://$tmpdir/origin.zip" --query 'LastModified' --output text > /dev/null

  aws $PROFILE_FLAG lambda update-function-configuration --function-name "$fn_name" --region "$aws_region" \
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
    local hc_id=$(get_health_check_id "$region_name")
    local label=$(get_label "$region_name")
    local status=$(aws $PROFILE_FLAG route53 get-health-check-status --health-check-id "$hc_id" \
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
    if [[ -z "$REGION" ]] || [[ -z "$(get_aws_region "$REGION")" ]]; then
      echo "Usage: $0 inject <americas|emea|apac> [--profile <profile>]"
      exit 1
    fi
    inject_error "$REGION"
    echo ""
    sleep 2
    show_status
    ;;
  revert)
    if [[ -z "$REGION" ]] || [[ -z "$(get_aws_region "$REGION")" ]]; then
      echo "Usage: $0 revert <americas|emea|apac> [--profile <profile>]"
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
    echo "  $0 inject <region> [--profile <aws-profile>]"
    echo "  $0 revert <region> [--profile <aws-profile>]"
    echo "  $0 status [--profile <aws-profile>]"
    echo ""
    echo "Regions: americas | emea | apac"
    echo ""
    echo "Examples:"
    echo "  $0 status                        # Check health (default profile)"
    echo "  $0 inject emea                   # Break EMEA origin"
    echo "  $0 revert emea                   # Restore EMEA origin"
    echo "  $0 inject apac --profile prod    # Break APAC using 'prod' profile"
    echo "  $0 status --profile my-account   # Status with specific profile"
    echo ""
    echo "Demo flow:"
    echo "  1. $0 status                    # Show all healthy"
    echo "  2. $0 inject emea               # Break EMEA"
    echo "  3. (wait 30s, show R53 failover in test client)"
    echo "  4. $0 revert emea               # Restore EMEA"
    echo "  5. (wait 30s, show R53 recovery)"
    ;;
esac
