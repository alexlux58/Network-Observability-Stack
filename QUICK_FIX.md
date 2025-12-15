# Quick Fix for Filebeat/Logstash Restart Loop

## Problem
- Filebeat: "data path already locked by another beat"
- Logstash: Restarting continuously
- Permission denied when trying to stop containers

## Solution

Run these commands **in order**:

```bash
# 1. Force kill and remove containers
docker kill observability-stack-master-filebeat-1 2>/dev/null || true
docker kill observability-stack-master-logstash-1 2>/dev/null || true
docker rm -f observability-stack-master-filebeat-1 2>/dev/null || true
docker rm -f observability-stack-master-logstash-1 2>/dev/null || true

# 2. Remove Filebeat lock file
sudo rm -f ./data/filebeat/filebeat.lock

# 3. Check Logstash data directory permissions (may need fixing)
sudo chown -R 1000:1000 ./data/logstash 2>/dev/null || true

# 4. Restart services
docker compose up -d filebeat logstash

# 5. Wait and check status
sleep 5
docker ps | grep -E "filebeat|logstash"

# 6. Check logs
echo "=== Filebeat logs ==="
docker logs observability-stack-master-filebeat-1 --tail=30

echo ""
echo "=== Logstash logs ==="
docker logs observability-stack-master-logstash-1 --tail=30
```

## If Permission Denied Persists

If you still get permission denied errors, you may need to:

1. **Check Docker daemon status:**
   ```bash
   sudo systemctl status docker
   ```

2. **Add your user to docker group (if not already):**
   ```bash
   sudo usermod -aG docker $USER
   # Then log out and back in
   ```

3. **Or use sudo for all docker commands:**
   ```bash
   sudo docker kill observability-stack-master-filebeat-1
   sudo docker rm -f observability-stack-master-filebeat-1
   sudo rm -f ./data/filebeat/filebeat.lock
   sudo docker compose up -d filebeat logstash
   ```

## Verify Fix

After running the commands, check:

```bash
# Containers should be running (not restarting)
docker ps

# Filebeat should show no lock errors
docker logs observability-stack-master-filebeat-1 --tail=20 | grep -i lock

# Logstash should be running
docker logs observability-stack-master-logstash-1 --tail=20 | grep -i error
```

## After Services Are Running

Wait 2-3 minutes, then check if data is being indexed:

```bash
# Check for filebeat indices
curl -s http://localhost:9200/_cat/indices/filebeat-*?v

# Check document count
curl -s 'http://localhost:9200/filebeat-*/_count'

# Get a sample document to verify @timestamp field exists
curl -s 'http://localhost:9200/filebeat-*/_search?size=1&pretty' | grep -A 2 "@timestamp"
```

Once you see documents being indexed, go back to Grafana and:

1. **Click "Save & test"** at the bottom of the Elasticsearch data source configuration page
2. You should see: ✅ "Data source is working" (instead of the red error)
3. The "@timestamp" error should be gone once data exists

## Verify Configuration is Correct

Your Grafana Elasticsearch data source should have:
- ✅ **URL**: `http://elasticsearch:9200` (using Docker service name)
- ✅ **Index name**: `filebeat-*` (with wildcard)
- ✅ **Time field name**: `@timestamp`
- ✅ **Message field name**: `_source` (or `message` if your logs use that field)
- ✅ **Access**: Server (default)

If you still see the "@timestamp" error after data is indexed, try:
1. Click "Save & test" again
2. Delete and recreate the data source
3. Verify the index pattern matches: `curl -s http://localhost:9200/_cat/indices/filebeat-*?v`

