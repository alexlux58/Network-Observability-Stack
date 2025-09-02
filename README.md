bservability Stack (Master)

One-command ELK + Prometheus + Grafana stack for a single host. Tested
with both classic Docker and snap-docker.

## Contents

-   Elasticsearch + Kibana + Logstash + Filebeat
-   Prometheus + Alertmanager
-   Grafana
-   cAdvisor + Node Exporter

## Requirements

-   Ubuntu (root or sudo)
-   Docker + docker compose

For snap-docker, Filebeat needs the real root dir:

We auto-read it via:

``` bash
DOCKER_ROOTDIR=$(docker info --format '{{.DockerRootDir}}')
```

## 🚀 Quickstart

``` bash
# 0) Clone and enter the repo
git clone https://github.com/<your-username>/observability-stack-master.git
cd observability-stack-master

# 1) Export or write the Docker root dir (works for both classic & snap-docker)
echo "DOCKER_ROOTDIR=$(docker info --format '{{.DockerRootDir}}')" > .env
cat .env

# 2) (First run only) Fix owners for bind mounts so containers can write
sudo mkdir -p data/{elasticsearch,kibana,logstash,filebeat,prometheus,alertmanager,grafana}
sudo chown -R 1000:1000 data/elasticsearch data/kibana
sudo chown -R 1000:1000 data/logstash
sudo chown -R root:root  data/filebeat
sudo chown -R 65534:65534 data/prometheus data/alertmanager
sudo chown -R 472:472   data/grafana

# 3) Filebeat config must be owned by root
sudo chown root:root filebeat/filebeat.yml
sudo chmod 0640 filebeat/filebeat.yml

# 4) Bring the stack up
docker compose up -d

# 5) (Optional, once) Load Filebeat/Kibana assets
docker exec -it observability-stack-master-filebeat-1 filebeat test config -e
# If OK:
# docker exec -it observability-stack-master-filebeat-1 filebeat setup --dashboards
```

### Endpoints (replace with your server IP):

-   Kibana: `http://<IP>:5601`
-   Grafana: `http://<IP>:3000` (default `admin` / `admin`)
-   Prometheus: `http://<IP>:9090`
-   Elasticsearch: `http://<IP>:9200`
-   Alertmanager: `http://<IP>:9093`
-   cAdvisor: `http://<IP>:8080`
-   Node Exporter: `http://<IP>:9100/metrics`

## 🧩 Integrations (Docker + Ubuntu logs)

We already wired Filebeat and Logstash to collect:

**filebeat/filebeat.yml highlights** - Ubuntu logs via filestream -
Docker logs via filestream on `*-json.log` + ndjson parser -
`add_docker_metadata` (requires `/var/run/docker.sock` mount) - Output:
Logstash `logstash:5044`

**docker-compose.yml mounts for Filebeat**

``` yaml
volumes:
  - ./filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
  - /var/log:/var/log:ro
  - ${DOCKER_ROOTDIR}/containers:/var/lib/docker/containers:ro
  - /var/run/docker.sock:/var/run/docker.sock:ro
  - ./data/filebeat:/usr/share/filebeat/data
```

**logstash/pipeline/01-beats.conf highlights** - Input:
`beats { port => 5044 }` - (Optional) promote decoded docker log JSON
into message - Output: Elasticsearch with ILM rollover alias `filebeat`

## 📊 Kibana: Create the Data View

1.  Open Kibana → Discover
2.  Create data view
    -   Name: `filebeat-*`
    -   Time field: `@timestamp`
3.  Filter examples:
    -   `container.name : "observability-stack-master-kibana-1"`
    -   `host.hostname : "<your-hostname>"`
    -   `log.level : "error"`

## 🧹 Index Settings & Retention (single node friendly)

``` bash
# replicas 0 for filebeat indices (template)
curl -s -X PUT "http://localhost:9200/_index_template/filebeat-template"   -H 'Content-Type: application/json' -d '{
    "index_patterns": ["filebeat-*"],
    "template": { "settings": { "index.number_of_replicas": 0 } },
    "priority": 500
  }'

# 14-day ILM delete policy + apply to template
curl -s -X PUT "http://localhost:9200/_ilm/policy/filebeat-retain-14d"   -H 'Content-Type: application/json' -d '{
    "policy": {
      "phases": {
        "hot": { "actions": {} },
        "delete": { "min_age": "14d", "actions": { "delete": {} } }
      }
    }
  }'

curl -s -X PUT "http://localhost:9200/_index_template/filebeat-template"   -H 'Content-Type: application/json' -d '{
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

## 🧯 Common Errors & Fixes

-   **Logstash**: Path "/usr/share/logstash/data" must be a writable
    directory\
    → Ensure host dir exists and is owned by uid 1000:

    ``` bash
    sudo mkdir -p data/logstash
    sudo chown 1000:1000 -R data/logstash
    sudo chmod 0755 data/logstash
    ```

-   **Filebeat**: config file ("filebeat.yml") must be owned by uid=0\
    →

    ``` bash
    sudo chown root:root filebeat/filebeat.yml
    sudo chmod 0640 filebeat/filebeat.yml
    ```

-   **Elasticsearch red / unassigned shards on single node**\
    → Set replicas 0 and free disk; clear read-only and retry:

    ``` bash
    curl -s -X PUT "http://localhost:9200/_all/_settings"     -H 'Content-Type: application/json'     -d '{"index.blocks.read_only_allow_delete": null}'

    curl -s -X POST "http://localhost:9200/_cluster/reroute?retry_failed=true"
    ```

-   **snap-docker bind mount fails at /var/lib/docker**\
    → Use `${DOCKER_ROOTDIR}` from:

    ``` bash
    docker info --format '{{.DockerRootDir}}'
    echo "DOCKER_ROOTDIR=$(docker info --format '{{.DockerRootDir}}')" > .env
    ```

## 🧰 Disk Growth Utility (LVM on Ubuntu)

Grow the VM disk in Proxmox (Hardware → Disk Action → Resize Disk), then
inside Ubuntu:

``` bash
# Install deps once
sudo apt-get update && sudo apt-get install -y cloud-guest-utils lvm2

# Script expands root LV + filesystem (ext4/xfs), single-disk LVM
sudo ./grow-root-lvm.sh      # or --dry-run / --percent 80
```

Verify:

``` bash
df -h /
df -h /usr/share/elasticsearch/data
```

## 🧪 Health & Debug Commands

``` bash
# Elasticsearch
curl -s http://localhost:9200/_cluster/health?pretty
curl -s 'http://localhost:9200/_cat/indices/filebeat-*?v'
curl -s 'http://localhost:9200/filebeat-*/_search?q=container.name:kibana&size=1&sort=@timestamp:desc'

# Filebeat & Logstash logs
docker logs --tail=100 -f observability-stack-master-filebeat-1
docker logs --tail=100 -f observability-stack-master-logstash-1

# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl,health,lastError}'
```

## 🔐 Security (optional)

This sample runs without xpack security (for lab use). For production: -
Enable `xpack.security.enabled: true` in Elasticsearch - Set
`ELASTIC_PASSWORD`, wire Kibana credentials
(`ELASTICSEARCH_USERNAME/PASSWORD`) - Put UIs behind a reverse proxy
(Nginx/Traefik) with TLS + auth

## ♻️ Reset Scripts

Keep volumes:

``` bash
./nuke-docker.sh --remove-networks
```

Prune all unused volumes/images/containers:

``` bash
docker system prune -a -f
docker volume prune -f
```

## 🗺️ Roadmap

-   Metricbeat for host/container metrics into Elasticsearch
-   Curated Kibana dashboards for Docker + Ubuntu auth
-   Reverse proxy + SSO front-door (e.g., Traefik + OAuth)


