#!/usr/bin/env bash
# run-benchmark.sh — Convenience wrapper to run a full benchmark + generate HTML report
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

WORKLOADS="${WORKLOADS:-select,insert,update}"
COUNTS="${COUNTS:-1,100,1000}"
OUTPUT="${OUTPUT:-}"

cd "$PROJECT_DIR"

if [ ! -f "config.json" ]; then
  echo "Error: config.json not found. Run scripts/setup-clusters.sh first."
  exit 1
fi

if [ ! -d "node_modules" ]; then
  echo "Installing dependencies..."
  npm install
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="benchmark-${TIMESTAMP}.json"

echo "Running benchmark..."
echo "  Workloads: $WORKLOADS"
echo "  Counts:    $COUNTS"
echo "  Output:    results/$OUTPUT_FILE"
echo ""

node src/benchmark.js \
  --workloads "$WORKLOADS" \
  --counts "$COUNTS" \
  --output "$OUTPUT_FILE" \
  --visualize

echo ""
echo "✓ Done. Check results/$OUTPUT_FILE and results/${OUTPUT_FILE%.json}.html"
