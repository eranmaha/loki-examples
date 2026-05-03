#!/bin/bash
set -euo pipefail

echo "═══ Teardown — Destroying all resources ═══"
echo ""
echo "⚠️  This will destroy ALL demo infrastructure."
read -p "Continue? (yes/no): " confirm
[ "$confirm" = "yes" ] || exit 1

cd "$(dirname "$0")/../terraform"
terraform destroy -auto-approve

echo ""
echo "✅ All resources destroyed."
