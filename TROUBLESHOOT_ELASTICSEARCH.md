# Troubleshooting Elasticsearch Data Source in Grafana

## Error: "No date field named @timestamp found"

This error occurs when Grafana can't find the `@timestamp` field in your Elasticsearch indices. Here's how to fix it:

## ⚠️ Common Issue: Filebeat Lock File Error

If you see this error in Filebeat logs:
```
Exiting: /usr/share/filebeat/data/filebeat.lock: data path already locked by another beat
```

**Quick Fix:**
```bash
# Stop Filebeat
docker stop observability-stack-master-filebeat-1

# Remove lock file
sudo rm -f ./data/filebeat/filebeat.lock

# Restart Filebeat
docker start observability-stack-master-filebeat-1
# OR
docker compose up -d filebeat
```

Or use the provided script:
```bash
chmod +x fix-filebeat-lock.sh
./fix-filebeat-lock.sh
```

---

## Step 1: Verify Elasticsearch Has Data

Check if indices exist and contain data:

```bash
# List all indices
curl -s http://localhost:9200/_cat/indices?v

# Check for filebeat indices specifically
curl -s http://localhost:9200/_cat/indices/filebeat-*?v

# Check if any documents exist
curl -s 'http://localhost:9200/filebeat-*/_count'

# Get a sample document to see the field structure
curl -s 'http://localhost:9200/filebeat-*/_search?size=1&pretty'
```

**Expected output:** You should see indices like `filebeat-2024.01.15-000001` or similar.

**If no indices exist:** Data hasn't been indexed yet. Proceed to Step 2.

---

## Step 2: Verify Data Pipeline is Working

### Check Filebeat Status

```bash
# Check Filebeat logs
docker logs observability-stack-master-filebeat-1 --tail=50

# Check if Filebeat is sending data
docker exec observability-stack-master-filebeat-1 filebeat test output
```

**Look for:**
- No errors in logs
- Connection to Logstash successful
- Files being read

### Check Logstash Status

```bash
# Check Logstash logs
docker logs observability-stack-master-logstash-1 --tail=50

# Check Logstash pipeline status
curl -s http://localhost:9600/_node/stats/pipelines?pretty
```

**Look for:**
- Pipeline running without errors
- Events being processed
- Connection to Elasticsearch successful

### Check Elasticsearch Status

```bash
# Check Elasticsearch health
curl -s http://localhost:9200/_cluster/health?pretty

# Check if Elasticsearch is receiving data
curl -s http://localhost:9200/_cat/indices?v
```

**Expected:** Cluster status should be "green" or "yellow" (yellow is OK for single node).

---

## Step 3: Wait for Data to Index

If the pipeline is working but no data exists yet:

1. **Wait 1-2 minutes** - Filebeat needs time to read logs and send them through the pipeline
2. **Generate some log activity** to trigger indexing:
   ```bash
   # Generate some system logs
   logger "Test log message for Elasticsearch"
   
   # Or check Docker container logs
   docker ps
   ```

3. **Verify data appears:**
   ```bash
   curl -s 'http://localhost:9200/filebeat-*/_count'
   ```

---

## Step 4: Verify Index Pattern in Grafana

Once data exists, verify your Grafana configuration:

1. **Index name pattern:** Should be `filebeat-*` (with wildcard)
2. **Time field name:** Should be `@timestamp`
3. **URL:** Should be `http://elasticsearch:9200` (using Docker service name)

### Alternative: Use Kibana to Verify

1. Open Kibana at `http://192.168.5.13:5601`
2. Go to **Analytics** → **Discover**
3. Create data view:
   - **Name:** `filebeat-*`
   - **Time field:** `@timestamp`
4. If Kibana can see the data, Grafana should too

---

## Step 5: Check Field Mapping

If indices exist but `@timestamp` isn't found, check the field mapping:

```bash
# Get field mappings for filebeat indices
curl -s 'http://localhost:9200/filebeat-*/_mapping?pretty' | grep -A 5 "@timestamp"
```

**Expected:** Should show `@timestamp` as a `date` type field.

---

## Step 6: Common Fixes

### Fix 1: Use Correct URL

In Grafana Elasticsearch data source:
- **URL:** `http://elasticsearch:9200` (Docker service name, not `localhost`)
- **Access:** Server (default)

### Fix 2: Verify Index Pattern

- **Index name:** `filebeat-*` (must include wildcard `*`)
- **Pattern:** Leave as "No pattern" or select appropriate pattern

### Fix 3: Check Time Field

- **Time field name:** `@timestamp` (exact, case-sensitive)
- Filebeat automatically adds this field to all events

### Fix 4: Restart Services

If data pipeline seems stuck:

```bash
# Restart the pipeline
docker compose restart filebeat logstash

# Wait 2-3 minutes, then check again
curl -s 'http://localhost:9200/filebeat-*/_count'
```

---

## Step 7: Test Connection in Grafana

After verifying data exists:

1. In Grafana, go to the Elasticsearch data source configuration
2. Scroll to bottom
3. Click **"Save & test"**
4. Should show: "Data source is working"

If it still fails:
- Check the error message details
- Verify the URL is accessible from Grafana container
- Ensure index pattern matches existing indices

---

## Quick Diagnostic Commands

Run these to get a full picture:

```bash
# 1. Check all services are running
docker compose ps

# 2. Check Elasticsearch has indices
curl -s http://localhost:9200/_cat/indices?v

# 3. Check document count
curl -s 'http://localhost:9200/filebeat-*/_count' | jq

# 4. Get sample document structure
curl -s 'http://localhost:9200/filebeat-*/_search?size=1' | jq '.hits.hits[0]._source | keys'

# 5. Check @timestamp field exists
curl -s 'http://localhost:9200/filebeat-*/_search?size=1' | jq '.hits.hits[0]._source["@timestamp"]'
```

---

## Still Not Working?

If you've verified:
- ✅ Elasticsearch has indices with data
- ✅ Documents contain `@timestamp` field
- ✅ Grafana URL is correct (`http://elasticsearch:9200`)
- ✅ Index pattern is `filebeat-*`

Try:
1. **Delete and recreate** the Elasticsearch data source in Grafana
2. **Check Grafana logs:**
   ```bash
   docker logs observability-stack-master-grafana-1 --tail=50
   ```
3. **Verify network connectivity** from Grafana to Elasticsearch:
   ```bash
   docker exec observability-stack-master-grafana-1 wget -O- http://elasticsearch:9200
   ```

---

## Expected Timeline

- **0-2 minutes:** Services starting up
- **2-5 minutes:** First logs being indexed
- **5+ minutes:** Should have enough data for Grafana to detect `@timestamp`

If it's been more than 10 minutes and still no data, check the pipeline logs for errors.

