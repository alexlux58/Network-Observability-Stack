#!/bin/bash
# Start all observability stack services

echo "Starting all observability stack services..."

# Remove any stuck containers first
echo "Cleaning up stuck containers..."
docker ps -a | grep -E "filebeat|logstash|elasticsearch|kibana|grafana|prometheus|alertmanager|cadvisor|node_exporter" | grep "Created" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

# Start all services
echo "Starting services..."
docker compose up -d

# Wait for services to start
echo "Waiting for services to initialize..."
sleep 10

# Check status
echo ""
echo "Service Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Checking critical services..."

# Check Elasticsearch
echo -n "Elasticsearch: "
if curl -s http://localhost:9200/_cluster/health?pretty | grep -q "green\|yellow"; then
    echo "Running"
else
    echo "Not responding"
fi

# Check if services are running (not just created)
echo ""
echo "Services that should be running:"
docker ps --format "{{.Names}}" | grep -E "elasticsearch|logstash|filebeat|kibana|grafana|prometheus" || echo "None running"

echo ""
echo "Done! Wait 2-3 minutes for data to start flowing, then check:"
echo "   curl -s http://localhost:9200/_cat/indices/filebeat-*?v"

