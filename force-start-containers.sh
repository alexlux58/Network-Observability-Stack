#!/bin/bash
# Force start all containers that are in Created status

echo "Force starting all containers..."

# List all containers in Created status
CREATED_CONTAINERS=$(docker ps -a --filter "status=created" --format "{{.Names}}")

if [ -z "$CREATED_CONTAINERS" ]; then
    echo "No containers in Created status found."
    exit 0
fi

echo "Found containers in Created status:"
echo "$CREATED_CONTAINERS"
echo ""

# Start each container
for container in $CREATED_CONTAINERS; do
    echo "Starting $container..."
    docker start "$container" 2>&1 || echo "Failed to start $container"
done

echo ""
echo "Waiting 5 seconds..."
sleep 5

echo ""
echo "Current container status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

