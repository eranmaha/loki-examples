#!/bin/bash
# deploy.sh — One-command deployment for CloudFront Geo-Routing with Health Checks
# Usage: ./deploy.sh [stack-name] [alert-email]
set -euo pipefail

STACK_NAME="${1:-geo-routing-demo}"
ALERT_EMAIL="${2:-}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TEMPLATE="$(dirname "$0")/cloudformation/geo-routing-stack.yaml"

echo "═══════════════════════════════════════════════════════════"
echo "  CloudFront Geo-Routing — Automated Deployment"
echo "═══════════════════════════════════════════════════════════"
echo "Stack:    $STACK_NAME"
echo "Region:   $REGION"
echo "Template: $TEMPLATE"
echo ""

# ─── Step 1: Delete existing stack if present ────────────────────────────────
echo "▶ Step 1: Checking for existing stack..."
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" != "DOES_NOT_EXIST" ]; then
  echo "  Found existing stack (status: $STACK_STATUS). Cleaning up..."

  # Stop canaries before deletion
  echo "  Stopping canaries..."
  for i in 0 1 2; do
    aws synthetics stop-canary --name "${STACK_NAME}-origin-${i}" --region "$REGION" 2>/dev/null || true
  done
  sleep 10

  # Empty the canary artifacts bucket
  BUCKET="${STACK_NAME}-canary-artifacts-$(aws sts get-caller-identity --query Account --output text)"
  echo "  Emptying bucket $BUCKET..."
  aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" 2>/dev/null || true

  # Delete the stack
  echo "  Deleting stack..."
  aws cloudformation delete-stack --stack-name "$STACK_NAME" --region "$REGION"
  aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region "$REGION"
  echo "  ✓ Old stack deleted"
else
  echo "  No existing stack found"
fi

# ─── Step 2: Clean up SSM params and deploy ──────────────────────────────────
echo ""
echo "▶ Step 2: Deploying CloudFormation stack..."
for i in 0 1 2; do
  aws ssm delete-parameter --name "/geo-routing/origin-${i}-healthy" --region "$REGION" 2>/dev/null || true
done

PARAMS="ParameterKey=ProjectName,ParameterValue=$STACK_NAME"
if [ -n "$ALERT_EMAIL" ]; then
  PARAMS="$PARAMS ParameterKey=AlertEmail,ParameterValue=$ALERT_EMAIL"
fi

aws cloudformation create-stack \
  --stack-name "$STACK_NAME" \
  --template-body "file://$TEMPLATE" \
  --parameters $PARAMS \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION"

echo "  Waiting for stack creation (CloudFront takes ~5 min)..."
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
echo "  ✓ Stack deployed"

# ─── Step 3: Get stack outputs ───────────────────────────────────────────────
echo ""
echo "▶ Step 3: Reading stack outputs..."
get_output() {
  aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

DIST_URL=$(get_output DistributionUrl)
DIST_ID=$(get_output DistributionId)
KVS_ARN=$(get_output KvsArn)
MAINT_URL=$(get_output MaintenanceApiUrl)
echo "  Distribution: $DIST_URL"
echo "  KVS ARN:      $KVS_ARN"

# ─── Step 4: Get origin API Gateway domains ──────────────────────────────────
echo ""
echo "▶ Step 4: Discovering origin domains..."
ORIGIN_0_DOMAIN=$(aws cloudfront get-distribution-config --id "$DIST_ID" --region "$REGION" \
  --query "DistributionConfig.Origins.Items[?Id=='origin-0'].DomainName" --output text)
ORIGIN_1_DOMAIN=$(aws cloudfront get-distribution-config --id "$DIST_ID" --region "$REGION" \
  --query "DistributionConfig.Origins.Items[?Id=='origin-1'].DomainName" --output text)
ORIGIN_2_DOMAIN=$(aws cloudfront get-distribution-config --id "$DIST_ID" --region "$REGION" \
  --query "DistributionConfig.Origins.Items[?Id=='origin-2'].DomainName" --output text)
echo "  Origin 0 (Americas): $ORIGIN_0_DOMAIN"
echo "  Origin 1 (EMEA):     $ORIGIN_1_DOMAIN"
echo "  Origin 2 (APAC):     $ORIGIN_2_DOMAIN"

# ─── Step 5: Populate KVS ────────────────────────────────────────────────────
echo ""
echo "▶ Step 5: Populating Key Value Store..."
put_kvs() {
  local KEY="$1" VALUE="$2"
  local ETAG
  ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn "$KVS_ARN" --query ETag --output text --region "$REGION")
  aws cloudfront-keyvaluestore put-key --kvs-arn "$KVS_ARN" --key "$KEY" --value "$VALUE" --if-match "$ETAG" --region "$REGION" > /dev/null
}

put_kvs "origin_0_domain" "$ORIGIN_0_DOMAIN"
put_kvs "origin_1_domain" "$ORIGIN_1_DOMAIN"
put_kvs "origin_2_domain" "$ORIGIN_2_DOMAIN"
put_kvs "origin_0_enabled" "true"
put_kvs "origin_1_enabled" "true"
put_kvs "origin_2_enabled" "true"
echo "  ✓ KVS populated (6 keys)"

# ─── Step 6: Update CF Function with correct header priority ─────────────────
echo ""
echo "▶ Step 6: Updating CloudFront Function..."
FN_NAME="${STACK_NAME}-viewer-request"
CF_FN_FILE="$(dirname "$0")/src/viewer-request-deploy.js"

# Generate the deploy version of the CF Function
cat > "$CF_FN_FILE" << 'CFEOF'
import cf from 'cloudfront';
const kvsHandle = cf.kvs();
const AMERICAS = ['US','CA','MX','BR','AR','CL','CO','PE','VE','EC','BO','PY','UY','GY','SR','PA','CR','NI','HN','SV','GT','BZ','CU','JM','HT','DO','PR','TT','BB','BS','AG','DM','GD','KN','LC','VC','AW','CW','SX'];
const EMEA = ['GB','DE','FR','IT','ES','NL','BE','AT','CH','SE','NO','DK','FI','IE','PT','PL','CZ','RO','HU','GR','BG','HR','SK','SI','LT','LV','EE','LU','MT','CY','IL','AE','SA','QA','BH','KW','OM','JO','LB','IQ','IR','TR','EG','ZA','NG','KE','GH','TZ','ET','MA','TN','DZ','LY','SN','CI','CM','UG','AO','MZ','MG','RW','UA','RS','BA','ME','MK','AL','MD','GE','AM','AZ'];
const APAC = ['CN','JP','KR','IN','AU','NZ','SG','MY','TH','ID','PH','VN','TW','HK','MO','BD','PK','LK','NP','MM','KH','LA','BN','MN','FJ','PG','WS','TO','MV','AF','KZ','UZ','TM','KG','TJ'];
function getOrigin(cc) { if (AMERICAS.includes(cc)) return '0'; if (EMEA.includes(cc)) return '1'; if (APAC.includes(cc)) return '2'; return null; }
async function getKvs(key) { try { return await kvsHandle.get(key, { format: 'string' }); } catch(e) { return null; } }
async function handler(event) {
  const request = event.request;
  const cc = ((request.headers['x-viewer-country'] || {}).value || (request.headers['cloudfront-viewer-country'] || {}).value || '').toUpperCase();
  let originId = getOrigin(cc);
  let fallback = null;
  if (originId) { const e = await getKvs('origin_' + originId + '_enabled'); if (e === 'false') { fallback = 'origin_' + originId + '_maintenance'; originId = null; } }
  else { fallback = 'unmapped_' + (cc || 'UNKNOWN'); }
  if (!originId) { originId = '0'; if (fallback) console.log(JSON.stringify({ event: 'geo_routing_fallback', reason: fallback, country: cc })); }
  const domain = await getKvs('origin_' + originId + '_domain');
  if (domain) { cf.updateRequestOrigin({ domainName: domain, originId: 'origin-' + originId }); }
  request.headers['x-routed-origin'] = { value: originId };
  request.headers['x-routed-region'] = { value: originId };
  request.headers['x-viewer-country-resolved'] = { value: cc || 'UNKNOWN' };
  return request;
}
CFEOF

ETAG=$(aws cloudfront describe-function --name "$FN_NAME" --stage DEVELOPMENT --region "$REGION" --query 'ETag' --output text)
aws cloudfront update-function --name "$FN_NAME" \
  --function-code "fileb://$CF_FN_FILE" \
  --function-config "{
    \"Comment\": \"Geo routing with updateRequestOrigin\",
    \"Runtime\": \"cloudfront-js-2.0\",
    \"KeyValueStoreAssociations\": {\"Quantity\": 1, \"Items\": [{\"KeyValueStoreARN\": \"$KVS_ARN\"}]}
  }" --if-match "$ETAG" --region "$REGION" > /dev/null

ETAG=$(aws cloudfront describe-function --name "$FN_NAME" --stage DEVELOPMENT --region "$REGION" --query 'ETag' --output text)
aws cloudfront publish-function --name "$FN_NAME" --if-match "$ETAG" --region "$REGION" > /dev/null
echo "  ✓ CF Function updated and published"

# ─── Step 7: Build and attach CRT layer for failover Lambda ──────────────────
echo ""
echo "▶ Step 7: Configuring failover Lambda..."
FAILOVER_FN="${STACK_NAME}-failover"

# Check if layer exists
LAYER_ARN=$(aws lambda list-layer-versions --layer-name botocore-crt-arm64 --region "$REGION" \
  --query 'LayerVersions[0].LayerVersionArn' --output text 2>/dev/null || echo "None")

if [ "$LAYER_ARN" = "None" ] || [ -z "$LAYER_ARN" ]; then
  echo "  ⚠ No botocore-crt-arm64 layer found. Building..."
  LAYER_DIR=$(mktemp -d)
  mkdir -p "$LAYER_DIR/python"
  pip install boto3 botocore awscrt -t "$LAYER_DIR/python" --quiet --upgrade 2>/dev/null
  cd "$LAYER_DIR" && zip -qr /tmp/crt-layer.zip python/
  LAYER_ARN=$(aws lambda publish-layer-version \
    --layer-name botocore-crt-arm64 \
    --zip-file fileb:///tmp/crt-layer.zip \
    --compatible-runtimes python3.9 \
    --compatible-architectures arm64 \
    --region "$REGION" \
    --query 'LayerVersionArn' --output text)
  rm -rf "$LAYER_DIR" /tmp/crt-layer.zip
  echo "  ✓ Layer built: $LAYER_ARN"
else
  echo "  ✓ Layer exists: $LAYER_ARN"
fi

aws lambda update-function-configuration \
  --function-name "$FAILOVER_FN" \
  --runtime python3.9 \
  --layers "$LAYER_ARN" \
  --region "$REGION" > /dev/null 2>&1
echo "  ✓ CRT layer attached to failover Lambda"

# ─── Step 8: Verify ──────────────────────────────────────────────────────────
echo ""
echo "▶ Step 8: Verifying deployment..."
sleep 5

test_origin() {
  local COUNTRY="$1" EXPECTED="$2"
  local RESULT
  RESULT=$(curl -s -H "x-viewer-country: $COUNTRY" "$DIST_URL/?t=$(date +%s%N)" 2>/dev/null | grep -o '"originId":"[0-2]"' | cut -d'"' -f4)
  if [ "$RESULT" = "$EXPECTED" ]; then
    echo "  ✓ $COUNTRY → Origin $RESULT"
  else
    echo "  ✗ $COUNTRY → Origin ${RESULT:-FAILED} (expected $EXPECTED)"
  fi
}

test_origin "US" "0"
test_origin "IL" "1"
test_origin "JP" "2"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Deployment Complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  CloudFront URL:    $DIST_URL"
echo "  Maintenance API:   $MAINT_URL"
echo "  Distribution ID:   $DIST_ID"
echo "  KVS ARN:           $KVS_ARN"
echo ""
echo "  Test commands:"
echo "    curl -H 'x-viewer-country: US' $DIST_URL/"
echo "    curl -H 'x-viewer-country: IL' $DIST_URL/"
echo "    curl -H 'x-viewer-country: JP' $DIST_URL/"
echo ""
echo "  Simulate failure:"
echo "    aws ssm put-parameter --name /geo-routing/origin-1-healthy --value false --type String --overwrite"
echo ""
echo "  Manual toggle:"
echo "    curl -X POST $MAINT_URL -H 'Content-Type: application/json' -d '{\"originId\":1,\"enabled\":false}'"
echo ""
