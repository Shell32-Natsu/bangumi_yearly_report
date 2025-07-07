#!/bin/bash

cd "$(dirname "$0")/.."

echo "Starting Bangumi Yearly Report server..."
docker-compose up -d

if [ $? -eq 0 ]; then
    echo "Server started successfully!"
    echo "Access the server at: http://localhost:8080"
    echo ""
    echo "To view logs: docker-compose logs -f"
    echo "To stop: ./docker/stop.sh"
else
    echo "Failed to start server!"
    exit 1
fi