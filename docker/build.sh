#!/bin/bash

cd "$(dirname "$0")/.."

echo "Building Bangumi Yearly Report Docker image..."
docker-compose build --no-cache

if [ $? -eq 0 ]; then
    echo "Build completed successfully!"
else
    echo "Build failed!"
    exit 1
fi