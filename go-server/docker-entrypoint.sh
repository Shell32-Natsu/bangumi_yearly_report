#!/bin/sh
set -e

if [ ! -d "/app/data" ]; then
    mkdir -p /app/data
fi

if [ ! -d "/app/reports" ]; then
    mkdir -p /app/reports
fi

echo "Starting Bangumi Yearly Report Server..."
exec ./bangumi-server