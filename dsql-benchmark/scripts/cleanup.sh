#!/usr/bin/env bash
# cleanup.sh — Delete DSQL clusters and clean up resources
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config.json"

REGION_PRIMARY="us-east-1"
REGION_SECONDARY="us-west-2"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Aurora DSQL Benchmark — Cleanup                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
  echo "config.json not found at $CONFIG_FILE"
  echo "Nothing to clean up. To delete clusters manually, run:"
  echo "  aws dsql list-clusters --region us-east-1"
  echo "  aws dsql list-clusters --region us-west-2"
  exit 0
fi

SINGLE_ID=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('singleRegion',{}).get('clusterId',''))" 2>/dev/null || true)
MULTI_PRIMARY_ID=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('multiRegion',{}).get('primaryClusterId',''))" 2>/dev/null || true)
MULTI_SECONDARY_ID=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('multiRegion',{}).get('secondaryClusterId',''))" 2>/dev/null || true)

echo "Will delete:"
[ -n "$SINGLE_ID" ]          && echo "  Single-region cluster:          $SINGLE_ID ($REGION_PRIMARY)"
[ -n "$MULTI_PRIMARY_ID" ]   && echo "  Multi-region primary cluster:   $MULTI_PRIMARY_ID ($REGION_PRIMARY)"
[ -n "$MULTI_SECONDARY_ID" ] && echo "  Multi-region secondary cluster: $MULTI_SECONDARY_ID ($REGION_SECONDARY)"
echo ""

read -r -p "Are you sure you want to delete these clusters? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# ── Delete clusters ────────────────────────────────────────────────────────────
delete_cluster() {
  local cluster_id="$1"
  local region="$2"
  local label="$3"
  if [ -n "$cluster_id" ]; then
    echo "▶ Deleting $label ($cluster_id) in $region..."
    aws dsql delete-cluster --identifier "$cluster_id" --region "$region" 2>&1 && \
      echo "  ✓ Delete initiated" || \
      echo "  Warning: delete failed (may already be deleted or not found)"
  fi
}

delete_cluster "$MULTI_SECONDARY_ID" "$REGION_SECONDARY" "multi-region secondary"
delete_cluster "$MULTI_PRIMARY_ID"   "$REGION_PRIMARY"   "multi-region primary"
delete_cluster "$SINGLE_ID"          "$REGION_PRIMARY"   "single-region"

# ── Remove config ──────────────────────────────────────────────────────────────
echo ""
echo "▶ Removing config.json..."
rm -f "$CONFIG_FILE"
echo "  ✓ config.json removed"

echo ""
echo "✓ Cleanup complete. Results preserved at $PROJECT_DIR/results/"
echo ""
echo "Note: Clusters may take a few minutes to fully terminate."
echo "Verify with:"
echo "  aws dsql list-clusters --region $REGION_PRIMARY"
echo "  aws dsql list-clusters --region $REGION_SECONDARY"
