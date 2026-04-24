#!/bin/bash
# storage/create-artifacts-bucket.sh
# Create artifacts bucket in Ozone

set -e

echo "Creating artifacts bucket in Ozone..."

kubectl exec -n data-storage ozone-om-0 -- ozone sh bucket create /s3v/artifacts

if [ $? -eq 0 ]; then
    echo "Artifacts bucket created successfully!"
    echo "To verify the bucket exists, run:"
    echo "kubectl exec -n data-storage ozone-om-0 -- ozone sh bucket list /s3v"
else
    echo "Failed to create artifacts bucket"
    exit 1
fi
