# Network Observability Stack

One-command ELK + Prometheus + Grafana stack for a single host. Tested with Docker Engine and snap-docker.

## Table of Contents

- [Quick Start](#-quick-start)
- [Architecture Overview](#-architecture-overview)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Dashboard Setup](#-dashboard-setup)
- [Troubleshooting](#-troubleshooting)
- [Maintenance](#-maintenance)
- [Security](#-security)

---

## 🚀 Quick Start

Get the stack running in 5 minutes:

```bash
# 1. Clone and enter the repo
git clone https://github.com/<your-username>/observability-stack-master.git
cd observability-stack-master

# 2. Run setup (creates directories, sets permissions, generates .env)
./manage.sh setup

# 3. Start all services
./manage.sh start

# 4. Check status
./manage.sh status
```

**Access the dashboards:**
- **Grafana**: `http://<your-server-ip>:3000` (default: `admin` / `admin`)
- **Kibana**: `http://<your-server-ip>:5601`
- **Prometheus**: `http://<your-server-ip>:9090`
- **Elasticsearch**: `http://<your-server-ip>:9200`

---

## 🏗️ Architecture Overview

This repository wires together an end-to-end observability stack for a single host, combining log collection, metrics, and alerting.

### Components

- **Filebeat** - Collects system and Docker logs
- **Logstash** - Processes and enriches log events
- **Elasticsearch** - Stores log data
- **Kibana** - Log exploration and visualization
- **Prometheus** - Metrics collection and alerting
- **Alertmanager** - Alert routing and notifications
- **Grafana** - Unified dashboards for metrics and logs
- **cAdvisor** - Container metrics exporter
- **Node Exporter** - Host metrics exporter

### Data Flow

```
System Logs → Filebeat → Logstash → Elasticsearch → Kibana
Docker Logs ↗                                    ↘ Grafana

Host Metrics → Node Exporter → Prometheus → Grafana
Container Metrics → cAdvisor ↗            ↘ Alertmanager
```

### How Everything Fits Together

1. **Filebeat** collects system and Docker logs and ships them to Logstash
2. **Logstash** processes the events and indexes them in Elasticsearch
3. **Kibana** queries Elasticsearch to explore and visualize log data
4. **Prometheus** scrapes metrics from exporters and evaluates alert rules
5. **Alertmanager** receives alerts from Prometheus and dispatches notifications
6. **Grafana** dashboards read from both Elasticsearch and Prometheus for a unified view

---

## 📦 Installation

### Requirements

- Ubuntu (root or sudo access)
- Docker Engine with Docker Compose v2 (`docker compose`)
- For snap-docker, Filebeat needs the real Docker root dir (handled automatically by `manage.sh setup`)

### Manual Setup (Alternative)

If you prefer manual setup instead of `./manage.sh setup`:

```bash
# 1. Create .env file with Docker root directory
echo "DOCKER_ROOTDIR=$(docker info --format '{{.DockerRootDir}}')" > .env
echo "GRAFANA_ADMIN_USER=admin" >> .env
echo "GRAFANA_ADMIN_PASSWORD=admin" >> .env

# 2. Create data directories
sudo mkdir -p data/{elasticsearch,kibana,logstash,filebeat,prometheus,alertmanager,grafana}

# 3. Set permissions
sudo chown -R 1000:1000 data/elasticsearch data/kibana
sudo chown -R 1000:1000 data/logstash
sudo chown -R root:root data/filebeat
sudo chown -R 65534:65534 data/prometheus data/alertmanager
sudo chown -R 472:472 data/grafana

# 4. Set Filebeat config permissions
sudo chown root:root filebeat/filebeat.yml
sudo chmod 0640 filebeat/filebeat.yml
```

---

## ⚙️ Configuration

### Environment Variables

Create a `.env` file (or use `.env.example` as a template):

```bash
# Docker root directory (required for snap-docker)
DOCKER_ROOTDIR=/var/lib/docker

# Grafana admin credentials (optional, defaults shown)
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin
```

### Service Configuration Files

- `filebeat/filebeat.yml` - Log collection configuration
- `logstash/pipeline/logstash.conf` - Log processing pipeline
- `prometheus/prometheus.yml` - Metrics scraping and alerting rules
- `prometheus/alerts.yml` - Alert definitions
- `alertmanager/alertmanager.yml` - Alert routing configuration

### Docker Compose Features

The `docker-compose.yml` includes several enhancements for better reliability and monitoring:

**Health Checks:**
- All services have health checks configured
- Docker automatically monitors and restarts unhealthy containers
- Services wait for dependencies to be healthy before starting

**Logging:**
- Automatic log rotation (10MB per file, max 3 files per service)
- Prevents disk space issues from log growth
- Logs accessible via `docker logs` or `./manage.sh logs <service>`

**Resource Limits:**
- Memory limits set for exporters (cAdvisor, Node Exporter)
- Prevents resource exhaustion

**Service Labels:**
- Services labeled with `com.observability.service` and `com.observability.role`
- Helps organize and filter containers

### Data Collection

**Filebeat collects:**
- Ubuntu system logs (`/var/log/syslog`, `/var/log/auth.log`, `/var/log/kern.log`)
- Docker container logs (JSON format with metadata)

**Prometheus scrapes:**
- Node Exporter (host metrics)
- cAdvisor (container metrics)
- Prometheus itself (self-monitoring)

---

## 🎮 Usage

### Management Script

Use `./manage.sh` for all operations:

```bash
./manage.sh [command] [options]

Commands:
  setup      - Initial setup (permissions, directories, .env)
  start      - Start all services
  stop       - Stop all services
  restart    - Restart all services
  status     - Show service status and health
  logs       - View logs for a service (e.g., ./manage.sh logs filebeat)
  fix        - Fix common issues (lock files, permissions, stuck containers)
  clean      - Clean up containers/volumes (with options)
  health     - Run health checks on all services
  user       - Manage Grafana users (create, list, delete, change-password)
```

### Examples

```bash
# Start services
./manage.sh start

# Check what's running
./manage.sh status

# View Filebeat logs
./manage.sh logs filebeat

# Fix Filebeat lock file issue
./manage.sh fix

# Clean up everything (keeps volumes)
./manage.sh clean

# Run health checks
./manage.sh health

# Create a Grafana user
./manage.sh user create john john@example.com password123 Editor

# List Grafana users
./manage.sh user list

# Change user password
./manage.sh user change-password john newpassword456

# Delete a Grafana user
./manage.sh user delete john
```

### Manual Docker Compose Commands

You can also use `docker compose` directly:

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f [service-name]

# Restart a specific service
docker compose restart [service-name]
```

---

## 📊 Dashboard Setup

### Grafana Dashboards

#### Step 1: Configure Data Sources

**Add Prometheus Data Source:**
1. Log into Grafana at `http://<your-server-ip>:3000`
2. Go to **Configuration** → **Data sources** → **Add data source**
3. Select **Prometheus**
4. Configure:
   - **Name**: `Prometheus`
   - **URL**: `http://prometheus:9090` (use Docker service name)
   - **Access**: Server (default)
5. Click **Save & test**

**Add Elasticsearch Data Source (Optional - for log visualization):**
1. Go to **Configuration** → **Data sources** → **Add data source**
2. Select **Elasticsearch**
3. Configure:
   - **Name**: `Elasticsearch`
   - **URL**: `http://elasticsearch:9200`
   - **Access**: Server
   - **Index name**: `filebeat-*`
   - **Time field name**: `@timestamp`
4. Click **Save & test** (may show error until data is indexed - see Troubleshooting)

#### Step 2: Import Pre-built Dashboards

Grafana has thousands of community dashboards. Recommended ones:

**Host Monitoring:**
- Dashboard ID: **1860** (Node Exporter Full) - Comprehensive host metrics

**Container Monitoring:**
- Dashboard ID: **11074** (Node Exporter for Prometheus) - Modern React-based dashboard
- Dashboard ID: **6417** (Docker Container Stats) - Container metrics dashboard
- **Note:** Dashboard 179 uses deprecated Angular and may not work in newer Grafana versions

**Prometheus Stats:**
- Dashboard ID: **893** (Prometheus 2.0 Stats) - Prometheus monitoring dashboard
- **Note:** Dashboard 3662 uses deprecated Angular and may not work in newer Grafana versions

**Search Tips:**
- Look for dashboards marked as "React" or "Modern" in Grafana dashboard library
- Filter by "Updated" date to find recently maintained dashboards
- Avoid dashboards marked as "Angular" or "Legacy"

**To import:**
1. Go to **Dashboards** → **Import**
2. Enter the dashboard ID
3. Select **Prometheus** data source
4. Click **Import**

Browse more at: https://grafana.com/grafana/dashboards/

#### Step 3: Create Custom Dashboards

**Host System Overview:**

- **CPU Usage**: `100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
- **Memory Usage**: `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100`
- **Disk Usage**: `100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})`
- **Network Traffic**: `rate(node_network_receive_bytes_total[5m])` and `rate(node_network_transmit_bytes_total[5m])`
- **Load Average**: `node_load1`, `node_load5`, `node_load15`

**Container Metrics:**

- **Container CPU**: `rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100`
- **Container Memory**: `container_memory_usage_bytes{name!=""}`
- **Container Network I/O**: `rate(container_network_receive_bytes_total[5m])` and `rate(container_network_transmit_bytes_total[5m])`
- **Running Containers**: `count(container_last_seen{name=~".+"})`

**Useful Prometheus Queries:**

```promql
# CPU usage percentage
100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Container CPU usage
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# Top 10 containers by CPU
topk(10, rate(container_cpu_usage_seconds_total{name!=""}[5m]))
```

### Kibana Dashboards

#### Step 1: Create Data View

1. Open Kibana at `http://<your-server-ip>:5601`
2. Go to **Analytics** → **Discover**
3. Create data view:
   - **Name**: `filebeat-*`
   - **Time field**: `@timestamp`
4. Click **Create data view**

#### Step 2: Create Visualizations

**Log Volume Over Time:**
- Visualization: Line chart
- Y-axis: Count
- X-axis: `@timestamp` (Date Histogram)
- Split by: Optional - `log.level` or `container.name`

**Top Container Logs:**
- Visualization: Data table
- Metrics: Count
- Buckets: Terms aggregation on `container.name`
- Size: 10

**Error Logs by Level:**
- Visualization: Pie chart
- Slice by: Terms on `log.level`
- Filter: `log.level: error OR log.level: warning`

**Recent Error Logs:**
- Visualization: Data table
- Filter: `log.level: error`
- Columns: `@timestamp`, `container.name`, `message`
- Sort: `@timestamp` descending

### Alerting

Alert rules are configured in `prometheus/alerts.yml` and automatically loaded. The file includes:

- **Host Alerts**: High CPU, memory, disk usage
- **Container Alerts**: High CPU/memory, container restarts
- **Prometheus Alerts**: Service down, scrape failures

To customize alerts, edit `prometheus/alerts.yml` and restart Prometheus:

```bash
docker compose restart prometheus
```

---

## 🔧 Troubleshooting

### Common Issues

#### Filebeat Lock File Error

**Symptoms:** Filebeat container restarting with error: "data path already locked by another beat"

**Solution:**
```bash
./manage.sh fix
```

Or manually:
```bash
docker stop observability-stack-master-filebeat-1
sudo rm -f ./data/filebeat/filebeat.lock
docker start observability-stack-master-filebeat-1
```

#### Logstash Permission Errors

**Symptoms:** Logstash container failing with permission denied errors

**Solution:**
```bash
sudo chown -R 1000:1000 ./data/logstash
docker compose restart logstash
```

#### Elasticsearch "No date field named @timestamp found" in Grafana

**Symptoms:** Grafana Elasticsearch data source shows error about missing `@timestamp` field

**Causes:**
1. No data indexed yet (most common)
2. Index pattern mismatch
3. Services not running

**Solution:**
1. Verify services are running: `./manage.sh status`
2. Check if indices exist:
   ```bash
   curl -s http://localhost:9200/_cat/indices/filebeat-*?v
   ```
3. Check document count:
   ```bash
   curl -s 'http://localhost:9200/filebeat-*/_count'
   ```
4. Wait 2-5 minutes for data to be indexed
5. Verify Grafana configuration:
   - URL: `http://elasticsearch:9200` (Docker service name)
   - Index name: `filebeat-*` (with wildcard)
   - Time field: `@timestamp`
6. Click "Save & test" again in Grafana

**If still failing:**
- Check Filebeat logs: `./manage.sh logs filebeat`
- Check Logstash logs: `./manage.sh logs logstash`
- Verify data pipeline: `curl -s http://localhost:9600/_node/stats/pipelines?pretty`

#### Containers Stuck in "Created" Status

**Symptoms:** Containers created but not starting

**Solution:**
```bash
./manage.sh start
```

This automatically handles stuck containers. Or manually:
```bash
docker ps -a --filter "status=created" --format "{{.Names}}" | xargs -r docker start
```

#### Elasticsearch Red/Unassigned Shards

**Symptoms:** Elasticsearch cluster health shows red status

**Solution:**
```bash
# Set replicas to 0 (single node)
curl -s -X PUT "http://localhost:9200/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'

curl -s -X POST "http://localhost:9200/_cluster/reroute?retry_failed=true"
```

#### Permission Denied Errors

**Symptoms:** Docker commands fail with permission denied

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in, or use:
newgrp docker
```

### Diagnostic Commands

```bash
# Check all services status
./manage.sh status

# Check Elasticsearch health
curl -s http://localhost:9200/_cluster/health?pretty

# Check indices
curl -s http://localhost:9200/_cat/indices/filebeat-*?v

# Check document count
curl -s 'http://localhost:9200/filebeat-*/_count' | jq

# Check Filebeat output
docker exec observability-stack-master-filebeat-1 filebeat test output

# Check Logstash pipeline
curl -s http://localhost:9600/_node/stats/pipelines?pretty

# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl,health,lastError}'
```

---

## 🔄 Maintenance

### Health Checks

Run comprehensive health checks:
```bash
./manage.sh health
```

This checks:
- All containers are running
- Elasticsearch cluster health
- Prometheus targets
- Service endpoints

**Note:** All services now have health checks configured in `docker-compose.yml`. Docker automatically monitors service health and can restart unhealthy containers. Health check status is visible in `docker ps` output.

### User Management

Manage Grafana users via CLI:

**Create a user:**
```bash
./manage.sh user create <username> <email> <password> [role]
# Roles: Admin, Editor, Viewer (default: Viewer)
# Example:
./manage.sh user create alice alice@example.com secret123 Editor
```

**List all users:**
```bash
./manage.sh user list
```

**Change user password:**
```bash
./manage.sh user change-password <username> <new-password>
```

**Delete a user:**
```bash
./manage.sh user delete <username>
# Requires confirmation
```

**User Roles:**
- **Admin** - Full access to all features and settings
- **Editor** - Can create and edit dashboards, data sources, and alerts
- **Viewer** - Read-only access to dashboards and data sources

### Index Management

**Set replicas to 0 (single node friendly):**
```bash
curl -s -X PUT "http://localhost:9200/_index_template/filebeat-template" \
  -H 'Content-Type: application/json' -d '{
    "index_patterns": ["filebeat-*"],
    "template": { "settings": { "index.number_of_replicas": 0 } },
    "priority": 500
  }'
```

**Configure 14-day retention:**
```bash
# Create ILM policy
curl -s -X PUT "http://localhost:9200/_ilm/policy/filebeat-retain-14d" \
  -H 'Content-Type: application/json' -d '{
    "policy": {
      "phases": {
        "hot": { "actions": {} },
        "delete": { "min_age": "14d", "actions": { "delete": {} } }
      }
    }
  }'

# Apply to template
curl -s -X PUT "http://localhost:9200/_index_template/filebeat-template" \
  -H 'Content-Type: application/json' -d '{
    "index_patterns": ["filebeat-*"],
    "template": {
      "settings": {
        "index.number_of_replicas": 0,
        "index.lifecycle.name": "filebeat-retain-14d"
      }
    },
    "priority": 500
  }'
```

### Backup and Restore

**Backup Elasticsearch indices:**
```bash
# Create snapshot repository
curl -X PUT "http://localhost:9200/_snapshot/backup" -H 'Content-Type: application/json' -d '{
  "type": "fs",
  "settings": {
    "location": "/usr/share/elasticsearch/backup"
  }
}'

# Create snapshot
curl -X PUT "http://localhost:9200/_snapshot/backup/snapshot_1?wait_for_completion=true"
```

**Backup Grafana dashboards:**
- Export dashboards as JSON from Grafana UI
- Or backup `./data/grafana` directory

### Cleanup

**Clean containers and images (keeps volumes):**
```bash
./manage.sh clean
```

**Remove everything including volumes (DANGEROUS):**
```bash
docker compose down -v
docker system prune -a -f
docker volume prune -f
```

### Updates

**Update services:**
1. Stop services: `./manage.sh stop`
2. Pull new images: `docker compose pull`
3. Start services: `./manage.sh start`

---

## 🔐 Security

### Current Configuration

This stack runs **without security** for lab/testing use:
- Elasticsearch: `xpack.security.enabled=false`
- Grafana: Default admin/admin credentials
- No TLS/HTTPS
- No authentication on Prometheus/Elasticsearch

### Production Hardening

**Enable Elasticsearch Security:**
1. Edit `docker-compose.yml`:
   ```yaml
   environment:
     - xpack.security.enabled=true
     - ELASTIC_PASSWORD=your-secure-password
   ```
2. Update Kibana environment:
   ```yaml
   environment:
     - ELASTICSEARCH_USERNAME=elastic
     - ELASTICSEARCH_PASSWORD=your-secure-password
   ```

**Change Grafana Credentials:**
- Edit `.env` file:
  ```bash
  GRAFANA_ADMIN_USER=your-username
  GRAFANA_ADMIN_PASSWORD=your-secure-password
  ```

**Add Reverse Proxy:**
- Use Nginx or Traefik with TLS
- Add authentication (OAuth, basic auth)
- Restrict access to internal network

**Network Security:**
- Use Docker networks to isolate services
- Restrict port exposure to necessary services only
- Use firewall rules to limit access

---

## 📚 Additional Resources

### Service Endpoints

- **Kibana**: `http://<IP>:5601`
- **Grafana**: `http://<IP>:3000` (default `admin` / `admin`)
- **Prometheus**: `http://<IP>:9090`
- **Elasticsearch**: `http://<IP>:9200`
- **Alertmanager**: `http://<IP>:9093`
- **cAdvisor**: `http://<IP>:8080`
- **Node Exporter**: `http://<IP>:9100/metrics`

### Useful Grafana Dashboard IDs

**Host Metrics:**
- **1860** - Node Exporter Full (comprehensive host metrics)
- **11074** - Node Exporter for Prometheus (modern React-based)

**Container Metrics:**
- **6417** - Docker Container Stats
- **11074** - Node Exporter for Prometheus (includes container metrics)

**Prometheus Monitoring:**
- **893** - Prometheus 2.0 Stats

**AWS S3 Monitoring (requires CloudWatch data source):**
- **22632** - AWS S3 CloudWatch - Monitors S3 buckets, storage metrics, request metrics, and replication metrics
- **Note:** Requires AWS CloudWatch data source configuration and AWS credentials

**Note:** Dashboards 179 and 3662 use deprecated Angular framework and may not work in Grafana 11+. Use the alternatives listed above instead.

Browse more at: https://grafana.com/grafana/dashboards/

### Project Structure

```
.
├── manage.sh                 # Unified management script
├── docker-compose.yml        # Main compose file
├── .env.example             # Environment variable template
├── README.md                # This file
├── alertmanager/
│   └── alertmanager.yml     # Alert routing config
├── filebeat/
│   └── filebeat.yml        # Log collection config
├── logstash/
│   └── pipeline/
│       └── logstash.conf   # Log processing pipeline
└── prometheus/
    ├── prometheus.yml      # Scrape config
    └── alerts.yml          # Alert rules
```

---

## 🗺️ Roadmap

- [ ] Metricbeat for host/container metrics into Elasticsearch
- [ ] Curated Kibana dashboards for Docker + Ubuntu auth
- [ ] Reverse proxy + SSO front-door (e.g., Traefik + OAuth)
- [ ] Automated backup scripts
- [ ] Health check automation and alerting

---

## 📝 License

See repository license file.

## 🤝 Contributing

Contributions welcome! Please open an issue or submit a pull request.
