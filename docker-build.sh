#!/bin/bash
set -e

echo "Building PI.N.S. in Docker container..."
echo ""

# Build the Docker image
docker build -f Dockerfile.build -t pins-builder .

# Run the build
docker run --rm \
    -v "$(pwd):/build" \
    -w /build \
    pins-builder \
    /bin/bash -c "./build-pi-package.sh"

echo ""
echo "Build complete! Artifacts are in ./artifacts/"
