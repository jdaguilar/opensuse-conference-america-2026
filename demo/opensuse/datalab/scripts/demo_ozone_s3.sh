#!/bin/bash
# demo_ozone_s3.sh — AWS CLI demo against Apache Ozone S3 gateway
set -eo pipefail

echo "=== Ozone S3 Demo ==="
echo "Endpoint: $AWS_S3_ENDPOINT"
echo ""

echo "--- Buckets ---"
aws s3 ls

echo ""
echo "--- Raw bucket layout ---"
aws s3 ls s3://raw/gh_archive/ || echo "(empty)"

echo ""
echo "--- Curated bucket layout ---"
aws s3 ls s3://curated/ || echo "(empty)"

echo ""
echo "--- Sample: first .json.gz file in raw ---"
FIRST=$(aws s3api list-objects \
    --bucket raw --prefix gh_archive/ \
    --query 'Contents[?ends_with(Key, `.json.gz`)].Key | [0]' \
    --output text 2>/dev/null || echo "")
if [ -n "$FIRST" ] && [ "$FIRST" != "None" ]; then
    echo "s3://raw/$FIRST"
    aws s3 cp "s3://raw/$FIRST" /tmp/sample.json.gz 2>/dev/null
    zcat /tmp/sample.json.gz | python3 -c "
import sys, json
for i, line in enumerate(sys.stdin):
    if i >= 2: break
    print(json.dumps(json.loads(line), indent=2))
" 2>/dev/null || true
    rm -f /tmp/sample.json.gz
else
    echo "No .json.gz files yet — run the Airflow download DAG first."
fi
