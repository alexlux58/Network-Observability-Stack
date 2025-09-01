# Observability Stack (Master)

One-command ELK + Prometheus + Grafana stack for a single host. Tested with both classic Docker and snap-docker.

## Contents
- Elasticsearch + Kibana + Logstash + Filebeat
- Prometheus + Alertmanager
- Grafana
- cAdvisor + Node Exporter

## Quickstart
```bash
tar -xzf observability-stack-master.tar.gz
cd observability-stack-master
./setup.sh
```

Endpoints (replace with your server IP):
- Kibana:        `http://<IP>:5601`
- Grafana:       `http://<IP>:3000` (default `admin` / `admin`)
- Prometheus:    `http://<IP>:9090`
- Elasticsearch: `http://<IP>:9200`
- Alertmanager:  `http://<IP>:9093`
- cAdvisor:      `http://<IP>:8080`
- Node Exporter: `http://<IP>:9100/metrics`

## Data & Permissions
The setup script creates and fixes ownership for bind mounts:
- **Prometheus & Alertmanager** → `65534:65534` (nobody)
- **Grafana** → `472:472`
- **Kibana/Elasticsearch** → `1000:1000`
- **Logstash/Filebeat** → `root:root`

If you still hit a permission error after manual edits:
```bash
sudo chown -R 65534:65534 data/prometheus data/alertmanager
sudo chown -R 472:472   data/grafana
sudo chown -R 1000:1000 data/kibana data/elasticsearch
sudo chown -R root:root data/logstash data/filebeat
```

## Kibana “upgrade your browser” banner
We set:
```yaml
CSP_ENABLED: "false"
CSP_STRICT: "false"
CSP_WARNLEGACYBROWSERS: "false"
```
so you won’t see that interstitial.

## Using snap-docker
We automatically read the real Docker data root for Filebeat/cAdvisor via the env var `${DOCKER_ROOTDIR}`.
No action required.

## Full reset (keeps volumes)
```bash
./nuke-docker.sh --remove-networks
# If snap-docker is stubborn:
./nuke-docker.sh --bounce-snap --remove-networks
```

> ⚠️ To remove volumes too: `docker volume prune` (this deletes *all* volumes).

## Customize
- Prometheus jobs: edit `prometheus/prometheus.yml`
- Logstash pipeline: edit `logstash/pipeline/logstash.conf`
- Filebeat inputs: edit `filebeat/filebeat.yml`

## Security
This sample disables Elasticsearch security and leaves the UIs open. For an Internet-exposed host,
enable auth/reverse proxies before deployment.
