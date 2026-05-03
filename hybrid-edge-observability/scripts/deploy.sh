#!/bin/bash
set -euo pipefail

echo "═══ Hybrid Edge-to-Cloud Observability — Deploy ═══"
echo ""

cd "$(dirname "$0")/../terraform"

# Init
echo "[1/3] Terraform init..."
terraform init -input=false

# Plan
echo "[2/3] Terraform plan..."
terraform plan -out=tfplan

# Apply
echo "[3/3] Terraform apply..."
terraform apply tfplan

echo ""
echo "═══ Deploy Complete ═══"
terraform output

echo ""
echo "Next steps:"
echo "  1. Wait ~5 min for EKS cluster + Fargate profile"
echo "  2. Deploy payment-api pods: kubectl apply -f k8s/"
echo "  3. Wait ~10 min for data to populate dashboard"
echo "  4. Run: ../scripts/simulate-traffic.sh"
