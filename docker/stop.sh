#!/bin/bash

cd "$(dirname "$0")/.."

echo "Stopping Bangumi Yearly Report server..."
docker-compose down

if [ $? -eq 0 ]; then
    echo "Server stopped successfully!"
else
    echo "Failed to stop server!"
    exit 1
fi