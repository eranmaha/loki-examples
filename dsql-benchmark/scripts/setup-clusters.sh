#!/usr/bin/env bash
# setup-clusters.sh — Create Aurora DSQL clusters and write config.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config.json"

REGION_PRIMARY="us-east-1"
REGION_SECONDARY="us-west-2"
REGION_WITNESS="us-east-2"  # Witness region for multi-region quorum

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Aurora DSQL Benchmark — Cluster Setup                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Helper: wait for cluster ACTIVE ───────────────────────────────────────────
wait_active() {
  local cluster_id="$1"
  local region="$2"
  local label="$3"
  echo "  Waiting for $label ($cluster_id) to become ACTIVE..."
  for i in $(seq 1 40); do
    STATUS=$(aws dsql get-cluster --identifier "$cluster_id" --region "$region" \
      --query 'status' --output text 2>/dev/null || echo "PENDING")
    echo "  [$i/40] Status: $STATUS"
    if [ "$STATUS" = "ACTIVE" ]; then
      return 0
    fi
    sleep 15
  done
  echo "  Warning: cluster did not reach ACTIVE within timeout"
}

# ── Single-Region Cluster ──────────────────────────────────────────────────────
echo "▶ Creating single-region DSQL cluster in $REGION_PRIMARY..."
SINGLE_OUTPUT=$(aws dsql create-cluster \
  --region "$REGION_PRIMARY" \
  --no-deletion-protection-enabled \
  --tags Purpose=benchmark,Tier=single-region \
  --output json)

echo "$SINGLE_OUTPUT" | python3 -m json.tool 2>/dev/null || echo "$SINGLE_OUTPUT"

SINGLE_ID=$(echo "$SINGLE_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['identifier'])")
echo "  Cluster ID: $SINGLE_ID"

wait_active "$SINGLE_ID" "$REGION_PRIMARY" "single-region"

SINGLE_ENDPOINT="${SINGLE_ID}.dsql.${REGION_PRIMARY}.on.aws"
echo "  Endpoint: $SINGLE_ENDPOINT"

SINGLE_ARN=$(aws dsql get-cluster --identifier "$SINGLE_ID" --region "$REGION_PRIMARY" \
  --query 'arn' --output text)
echo "  ARN: $SINGLE_ARN"

# ── Multi-Region Cluster (Primary in us-east-1) ───────────────────────────────
echo ""
echo "▶ Creating multi-region DSQL primary cluster in $REGION_PRIMARY..."
MULTI_PRIMARY_OUTPUT=$(aws dsql create-cluster \
  --region "$REGION_PRIMARY" \
  --no-deletion-protection-enabled \
  --tags Purpose=benchmark,Tier=multi-region-primary \
  --output json)

MULTI_PRIMARY_ID=$(echo "$MULTI_PRIMARY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['identifier'])")
echo "  Primary Cluster ID: $MULTI_PRIMARY_ID"

wait_active "$MULTI_PRIMARY_ID" "$REGION_PRIMARY" "multi-region primary"

MULTI_PRIMARY_ARN=$(aws dsql get-cluster --identifier "$MULTI_PRIMARY_ID" --region "$REGION_PRIMARY" \
  --query 'arn' --output text)
echo "  Primary ARN: $MULTI_PRIMARY_ARN"

# ── Multi-Region Cluster (Secondary in us-west-2, linked to primary) ──────────
echo ""
echo "▶ Creating multi-region DSQL secondary cluster in $REGION_SECONDARY (linked to primary)..."
MULTI_SECONDARY_OUTPUT=$(aws dsql create-cluster \
  --region "$REGION_SECONDARY" \
  --no-deletion-protection-enabled \
  --tags Purpose=benchmark,Tier=multi-region-secondary \
  --multi-region-properties "witnessRegion=${REGION_WITNESS},clusters=${MULTI_PRIMARY_ARN}" \
  --output json)

echo "$MULTI_SECONDARY_OUTPUT" | python3 -m json.tool 2>/dev/null || echo "$MULTI_SECONDARY_OUTPUT"

MULTI_SECONDARY_ID=$(echo "$MULTI_SECONDARY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['identifier'])")
echo "  Secondary Cluster ID: $MULTI_SECONDARY_ID"

wait_active "$MULTI_SECONDARY_ID" "$REGION_SECONDARY" "multi-region secondary"

MULTI_SECONDARY_ARN=$(aws dsql get-cluster --identifier "$MULTI_SECONDARY_ID" --region "$REGION_SECONDARY" \
  --query 'arn' --output text)
echo "  Secondary ARN: $MULTI_SECONDARY_ARN"

MULTI_PRIMARY_ENDPOINT="${MULTI_PRIMARY_ID}.dsql.${REGION_PRIMARY}.on.aws"
MULTI_SECONDARY_ENDPOINT="${MULTI_SECONDARY_ID}.dsql.${REGION_SECONDARY}.on.aws"

echo ""
echo "  Primary Endpoint:   $MULTI_PRIMARY_ENDPOINT"
echo "  Secondary Endpoint: $MULTI_SECONDARY_ENDPOINT"

# ── Write config.json ─────────────────────────────────────────────────────────
echo ""
echo "▶ Writing $CONFIG_FILE..."
python3 - <<PYEOF
import json

config = {
    "singleRegion": {
        "clusterId": "$SINGLE_ID",
        "clusterArn": "$SINGLE_ARN",
        "endpoint": "$SINGLE_ENDPOINT",
        "region": "$REGION_PRIMARY"
    },
    "multiRegion": {
        "primaryClusterId": "$MULTI_PRIMARY_ID",
        "primaryClusterArn": "$MULTI_PRIMARY_ARN",
        "secondaryClusterId": "$MULTI_SECONDARY_ID",
        "secondaryClusterArn": "$MULTI_SECONDARY_ARN",
        "primaryEndpoint": "$MULTI_PRIMARY_ENDPOINT",
        "secondaryEndpoint": "$MULTI_SECONDARY_ENDPOINT",
        "primaryRegion": "$REGION_PRIMARY",
        "secondaryRegion": "$REGION_SECONDARY",
        "witnessRegion": "$REGION_WITNESS"
    }
}

with open("$CONFIG_FILE", "w") as f:
    json.dump(config, f, indent=2)

print(json.dumps(config, indent=2))
PYEOF

echo ""
echo "✓ config.json written"
echo ""
echo "═══ Next Steps ══════════════════════════════════════════════════"
echo "  1. Setup schema:    npm run setup-schema"
echo "  2. Run benchmark:   bash scripts/run-benchmark.sh"
echo "  3. Or full custom:  npm run benchmark -- --workloads select,insert,update --counts 1,100,1000 --visualize"
echo "════════════════════════════════════════════════════════════════"
