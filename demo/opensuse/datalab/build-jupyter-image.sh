#!/bin/bash

# Build custom JupyterHub image with Julia kernel
echo "Building custom JupyterHub image..."

# Build the Docker image
docker build -t local_notebook:latest -f Dockerfile .

# Check if Docker build was successful
if [ $? -eq 0 ]; then
    echo "Docker image built successfully!"
    echo "The image is available locally as local_notebook:latest"
    echo ""
    echo "To use this image, update jupyterhub-values.yaml to use the local image:"
    echo "singleuser:"
    echo "  image:"
    echo "    name: local_notebook"
    echo "    tag: latest"
else
    echo "Failed to build Docker image"
    exit 1
fi