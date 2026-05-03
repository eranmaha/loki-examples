#!/bin/bash
set -euo pipefail

echo "═══ Simulate Edge Traffic ═══"

FUNCTION_NAME="hybrid-edge-obs-edge-sim"

echo "Invoking edge simulator (5 transactions)..."
aws lambda invoke --function-name "$FUNCTION_NAME" \
  --payload '{}' --cli-binary-format raw-in-base64-out \
  /tmp/sim-result.json --region us-east-1

echo ""
echo "Results:"
python3 -m json.tool /tmp/sim-result.json

echo ""
echo "Check dashboard: https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=hybrid-edge-obs-network-observability"
