#!/bin/bash
# Fix Filebeat lock file issue
# This script removes stale lock files and restarts Filebeat

set -e

echo "🔧 Fixing Filebeat lock file issue..."

# Force stop Filebeat container (if permission denied, try kill)
echo "Stopping Filebeat container..."
docker stop observability-stack-master-filebeat-1 2>/dev/null || \
docker kill observability-stack-master-filebeat-1 2>/dev/null || \
echo "Container may already be stopped"

# Force stop Logstash container too (it's also restarting)
echo "Stopping Logstash container..."
docker stop observability-stack-master-logstash-1 2>/dev/null || \
docker kill observability-stack-master-logstash-1 2>/dev/null || \
echo "Container may already be stopped"

# Remove lock file
echo "Removing stale lock file..."
sudo rm -f ./data/filebeat/filebeat.lock

# Also remove registry file if it's corrupted (optional - uncomment if needed)
# sudo rm -f ./data/filebeat/registry/filebeat/log.json

# Remove containers if they're stuck
echo "Removing containers if stuck..."
docker rm -f observability-stack-master-filebeat-1 2>/dev/null || true
docker rm -f observability-stack-master-logstash-1 2>/dev/null || true

# Restart services
echo "Restarting services..."
docker compose up -d filebeat logstash

# Wait a moment and check status
sleep 5
echo ""
echo "📊 Checking service status..."
docker ps | grep -E "filebeat|logstash" || echo "⚠️  Services not running"

echo ""
echo "📋 Checking Filebeat logs..."
docker logs observability-stack-master-filebeat-1 --tail=20 2>/dev/null || echo "Could not read Filebeat logs"

echo ""
echo "📋 Checking Logstash logs..."
docker logs observability-stack-master-logstash-1 --tail=20 2>/dev/null || echo "Could not read Logstash logs"

echo ""
echo "✅ Done! If services are still restarting, check logs for errors."

