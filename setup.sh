#!/usr/bin/env bash
set -Eeuo pipefail

echo -e "\n==> Setup (install, CLEANUP, launch) — Observability Stack (Master)\n"

# --- Normalize compose: drop any hard-coded container_name (stay idempotent) ---
echo "==> Normalizing compose (strip hard-coded container names)"
sed -i.bak '/^\s*container_name:/d' docker-compose.yml || true

# --- Prereqs (quiet if already installed) ---
echo -e "\n==> Installing prerequisites"
sudo apt-get update -qq
sudo apt-get install -y -qq lsb-release ca-certificates curl gnupg >/dev/null || true
if ! command -v docker >/dev/null 2>&1; then
  echo "[*] Please install Docker (engine + compose plugin) and rerun."
  exit 1
else
  echo "[*] Docker already installed."
fi

# --- Cleanup previous stack (data preserved) ---
echo -e "\n==> Cleaning previous stack (data preserved)"
# project name is set via 'name:' in compose; use label to scope
docker compose down --remove-orphans || true
docker ps -aq --filter 'label=com.docker.compose.project=observability-stack-master' | xargs -r docker rm -f || true

# --- Ensure persistent dirs & permissions ---
echo -e "\n==> Ensuring persistent directories & permissions"
export DOCKER_ROOTDIR="$(docker info -f '{{ .DockerRootDir }}' 2>/dev/null || echo /var/lib/docker)"
echo "[*] Docker root: ${DOCKER_ROOTDIR}"

mkdir -p ./data/prometheus ./data/alertmanager ./data/grafana ./data/kibana ./data/logstash ./data/elasticsearch ./data/filebeat

# Prometheus & Alertmanager run as nobody (65534)
sudo chown -R 65534:65534 ./data/prometheus ./data/alertmanager || true
sudo chmod -R u+rwX,g+rwX ./data/prometheus ./data/alertmanager || true

# Grafana runs as uid 472
sudo chown -R 472:472 ./data/grafana || true
sudo chmod -R u+rwX,g+rwX ./data/grafana || true

# Kibana/ES data (UID 1000 typically)
sudo chown -R 1000:1000 ./data/kibana ./data/elasticsearch || true
sudo chmod -R u+rwX,g+rwX ./data/kibana ./data/elasticsearch || true

# Logstash and Filebeat (root inside container)
sudo chown -R root:root ./data/logstash ./data/filebeat || true
sudo chmod -R u+rwX,g+rwX ./data/logstash ./data/filebeat || true

# --- Validate compose ---
echo -e "\n==> Validating compose file"
docker compose config >/dev/null

# --- Launch ---
echo -e "\n==> Launching containers"
docker compose up -d

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo -e "\n==> Endpoints (use your server IP)"
echo "[*] Kibana:        http://${IP:-<host>}:5601"
echo "[*] Grafana:       http://${IP:-<host>}:3000"
echo "[*] Prometheus:    http://${IP:-<host>}:9090"
echo "[*] Elasticsearch: http://${IP:-<host>}:9200"
echo "[*] Alertmanager:  http://${IP:-<host>}:9093"
echo "[*] cAdvisor:      http://${IP:-<host>}:8080"
echo "[*] Node Exporter: http://${IP:-<host>}:9100/metrics"
echo "Done ✅"
