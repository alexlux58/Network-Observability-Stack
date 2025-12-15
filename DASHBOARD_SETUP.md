# Monitoring Dashboard Setup Guide

This guide helps you create useful monitoring dashboards for your observability stack.

## 📊 Available Data Sources

### Metrics (via Prometheus)
- **Node Exporter** (`node_exporter:9100`) - Host metrics (CPU, memory, disk, network)
- **cAdvisor** (`cadvisor:8080`) - Container metrics (CPU, memory, I/O per container)
- **Prometheus** (`prometheus:9090`) - Prometheus self-monitoring

### Logs (via Elasticsearch)
- **System logs** - Ubuntu syslog, auth.log, kern.log
- **Docker container logs** - All container logs with metadata

---

## 🎯 Step 1: Configure Grafana Data Sources

### Add Prometheus Data Source

1. Log into Grafana at `http://192.168.5.13:3000`
2. Go to **Configuration** → **Data sources** → **Add data source**
3. Select **Prometheus**
4. Configure:
   - **Name**: `Prometheus`
   - **URL**: `http://prometheus:9090` (use service name from docker-compose)
   - **Access**: Server (default)
5. Click **Save & test** (should show "Data source is working")

### Add Elasticsearch Data Source (Optional - for log visualization)

1. Go to **Configuration** → **Data sources** → **Add data source**
2. Select **Elasticsearch**
3. Configure:
   - **Name**: `Elasticsearch`
   - **URL**: `http://elasticsearch:9200`
   - **Access**: Server
   - **Index name**: `filebeat-*`
   - **Time field name**: `@timestamp`
4. Click **Save & test**

---

## 📈 Step 2: Create Dashboards

### Option A: Import Pre-built Dashboards (Recommended)

Grafana has thousands of community dashboards. Here are useful ones for your stack:

#### Host Monitoring Dashboard
1. Go to **Dashboards** → **Import**
2. Enter dashboard ID: **1860** (Node Exporter Full)
3. Select **Prometheus** data source
4. Click **Import**

#### Container Monitoring Dashboard
1. Go to **Dashboards** → **Import**
2. Enter dashboard ID: **179** (Docker Container & Host Metrics)
3. Select **Prometheus** data source
4. Click **Import**

#### Prometheus Stats Dashboard
1. Go to **Dashboards** → **Import**
2. Enter dashboard ID: **3662** (Prometheus Stats)
3. Select **Prometheus** data source
4. Click **Import**

### Option B: Create Custom Dashboards

#### Dashboard 1: Host System Overview

**Panel 1: CPU Usage**
- **Query**: `100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
- **Visualization**: Stat or Gauge
- **Unit**: Percent (0-100)

**Panel 2: Memory Usage**
- **Query**: `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`
- **Visualization**: Stat or Gauge
- **Unit**: Percent (0-100)

**Panel 3: Disk Usage**
- **Query**: `100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})`
- **Visualization**: Stat or Gauge
- **Unit**: Percent (0-100)

**Panel 4: Network Traffic (Graph)**
- **Query A**: `rate(node_network_receive_bytes_total[5m])` (label: "Received")
- **Query B**: `rate(node_network_transmit_bytes_total[5m])` (label: "Transmitted")
- **Visualization**: Time series
- **Unit**: bytes/sec

**Panel 5: Load Average**
- **Query**: `node_load1`, `node_load5`, `node_load15`
- **Visualization**: Time series
- **Legend**: `{{job}} - {{instance}}`

#### Dashboard 2: Container Metrics

**Panel 1: Container CPU Usage**
- **Query**: `rate(container_cpu_usage_seconds_total[5m]) * 100`
- **Visualization**: Time series
- **Legend**: `{{name}}`
- **Unit**: Percent (0-100)

**Panel 2: Container Memory Usage**
- **Query**: `container_memory_usage_bytes`
- **Visualization**: Time series
- **Legend**: `{{name}}`
- **Unit**: bytes

**Panel 3: Container Memory Limit**
- **Query**: `container_spec_memory_limit_bytes`
- **Visualization**: Bar gauge
- **Legend**: `{{name}}`
- **Unit**: bytes

**Panel 4: Container Network I/O**
- **Query A**: `rate(container_network_receive_bytes_total[5m])` (label: "RX")
- **Query B**: `rate(container_network_transmit_bytes_total[5m])` (label: "TX")
- **Visualization**: Time series
- **Unit**: bytes/sec

**Panel 5: Running Containers**
- **Query**: `count(container_last_seen{name=~".+"})`
- **Visualization**: Stat
- **Unit**: short

#### Dashboard 3: Service Health Overview

**Panel 1: Prometheus Targets**
- **Query**: `up`
- **Visualization**: Table or Stat
- **Format**: Table
- **Columns**: `job`, `instance`, `up`

**Panel 2: Target Health Status**
- **Query**: `up`
- **Visualization**: Stat
- **Calculation**: Last value
- **Thresholds**: 0 = red, 1 = green

**Panel 3: Scrape Duration**
- **Query**: `prometheus_target_interval_length_seconds`
- **Visualization**: Time series
- **Unit**: seconds

---

## 📋 Step 3: Create Kibana Dashboards for Logs

### Create Log Analysis Dashboard in Kibana

1. Go to Kibana at `http://192.168.5.13:5601`
2. Ensure data view `filebeat-*` is created (see README.md)
3. Go to **Analytics** → **Dashboard** → **Create dashboard**

#### Useful Visualizations:

**1. Log Volume Over Time**
- **Visualization**: Line chart
- **Y-axis**: Count
- **X-axis**: `@timestamp` (Date Histogram)
- **Split by**: Optional - `log.level` or `container.name`

**2. Top Container Logs**
- **Visualization**: Data table
- **Metrics**: Count
- **Buckets**: Terms aggregation on `container.name`
- **Size**: 10

**3. Error Logs by Level**
- **Visualization**: Pie chart
- **Slice by**: Terms on `log.level`
- **Filter**: `log.level: error OR log.level: warning`

**4. Authentication Failures**
- **Visualization**: Data table
- **Filter**: `message: *authentication* OR message: *failed* OR message: *denied*`
- **Group by**: `host.hostname` or `source`

**5. Recent Error Logs**
- **Visualization**: Data table
- **Filter**: `log.level: error`
- **Columns**: `@timestamp`, `container.name`, `message`
- **Sort**: `@timestamp` descending

---

## 🔔 Step 4: Set Up Alerts (Optional)

### Create Alert Rules in Prometheus

Edit `prometheus/prometheus.yml` to add alerting rules:

```yaml
rule_files:
  - "alerts.yml"

# ... existing config ...
```

Create `prometheus/alerts.yml`:

```yaml
groups:
  - name: host_alerts
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for 5 minutes"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85%"

      - alert: DiskSpaceLow
        expr: 100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"}) > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk space running low"
          description: "Disk usage is above 90%"

  - name: container_alerts
    interval: 30s
    rules:
      - alert: ContainerDown
        expr: up{job="cadvisor"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Container monitoring down"
          description: "cAdvisor is not responding"
```

Then restart Prometheus:
```bash
docker compose restart prometheus
```

---

## 🎨 Quick Dashboard Creation Tips

1. **Start Simple**: Begin with basic CPU, memory, and disk panels
2. **Use Variables**: Create dashboard variables for filtering (e.g., `$container` variable)
3. **Set Refresh Intervals**: Use auto-refresh (e.g., 30s) for real-time monitoring
4. **Organize with Rows**: Group related panels in rows
5. **Add Annotations**: Mark important events (deployments, incidents)
6. **Export Dashboards**: Save dashboard JSON files for backup/sharing

---

## 📚 Useful Grafana Dashboard IDs

- **1860** - Node Exporter Full (comprehensive host metrics)
- **179** - Docker Container & Host Metrics
- **3662** - Prometheus Stats
- **11074** - Node Exporter for Prometheus
- **893** - Prometheus 2.0 Stats
- **6417** - Docker Container Stats

Browse more at: https://grafana.com/grafana/dashboards/

---

## 🔍 Useful Prometheus Queries

### Host Queries
```promql
# CPU usage percentage
100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk I/O
rate(node_disk_io_time_seconds_total[5m])

# Network errors
rate(node_network_receive_errs_total[5m])
```

### Container Queries
```promql
# Container CPU usage
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# Container memory usage
container_memory_usage_bytes{name!=""}

# Container restart count
rate(container_last_seen{name!=""}[5m])

# Top 10 containers by CPU
topk(10, rate(container_cpu_usage_seconds_total{name!=""}[5m]))
```

---

## 🚀 Next Steps

1. Set up data sources in Grafana
2. Import recommended dashboards
3. Customize dashboards for your needs
4. Create Kibana log dashboards
5. Set up alerting rules
6. Create a unified "Operations" dashboard combining key metrics

