#!/usr/bin/env bash
set -euo pipefail

# Network Observability Stack Management Script
# Unified interface for managing the observability stack

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color output functions
info() { printf "\033[1;36m==> %s\033[0m\n" "$*"; }
success() { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$*"; }
error() { printf "\033[1;31m✗ %s\033[0m\n" "$*"; }

# Detect Docker command (handle snap-docker)
detect_docker() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        echo "docker"
    elif sudo docker info >/dev/null 2>&1; then
        echo "sudo docker"
    else
        error "Cannot connect to Docker daemon"
        exit 1
    fi
}

DOCKER_CMD=$(detect_docker)

# Get server IP
get_server_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "<your-server-ip>"
}

# Show usage
usage() {
    cat << EOF
Network Observability Stack Management

Usage: $0 [command] [options]

Commands:
  setup      - Initial setup (permissions, directories, .env)
  start      - Start all services
  stop       - Stop all services
  restart    - Restart all services
  status     - Show service status and health
  logs       - View logs for a service
               Usage: $0 logs [service-name]
  fix        - Fix common issues (lock files, permissions, stuck containers)
  clean      - Clean up containers/volumes
               Options: --remove-volumes (DANGEROUS: removes all data)
  health     - Run health checks on all services
  user       - Manage Grafana users
               Usage: $0 user [create|list|delete|change-password] [options]
               Examples:
                 $0 user create john john@example.com password123 Viewer
                 $0 user list
                 $0 user delete john
                 $0 user change-password john newpassword123
  help       - Show this help message

Examples:
  $0 setup
  $0 start
  $0 status
  $0 logs filebeat
  $0 fix
  $0 clean
  $0 user create alice alice@example.com secret123 Editor

EOF
}

# Setup command
cmd_setup() {
    info "Running initial setup..."
    
    # Check Docker
    if ! $DOCKER_CMD info >/dev/null 2>&1; then
        error "Docker is not running or not accessible"
        exit 1
    fi
    
    # Create .env if it doesn't exist
    if [ ! -f .env ]; then
        info "Creating .env file..."
        DOCKER_ROOTDIR=$($DOCKER_CMD info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
        cat > .env << EOF
# Docker root directory (required for snap-docker)
DOCKER_ROOTDIR=${DOCKER_ROOTDIR}

# Grafana admin credentials (optional, defaults shown)
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin
EOF
        success "Created .env file"
    else
        warn ".env file already exists, skipping"
    fi
    
    # Create data directories
    info "Creating data directories..."
    sudo mkdir -p data/{elasticsearch,kibana,logstash,filebeat,prometheus,alertmanager,grafana} 2>/dev/null || true
    
    # Set permissions
    info "Setting directory permissions..."
    sudo chown -R 1000:1000 data/elasticsearch data/kibana 2>/dev/null || true
    sudo chown -R 1000:1000 data/logstash 2>/dev/null || true
    sudo chown -R root:root data/filebeat 2>/dev/null || true
    sudo chown -R 65534:65534 data/prometheus data/alertmanager 2>/dev/null || true
    sudo chown -R 472:472 data/grafana 2>/dev/null || true
    
    # Set Filebeat config permissions
    if [ -f filebeat/filebeat.yml ]; then
        info "Setting Filebeat config permissions..."
        sudo chown root:root filebeat/filebeat.yml 2>/dev/null || true
        sudo chmod 0640 filebeat/filebeat.yml 2>/dev/null || true
    fi
    
    success "Setup complete!"
    info "Next steps:"
    echo "  1. Review .env file: cat .env"
    echo "  2. Start services: $0 start"
    echo "  3. Check status: $0 status"
}

# Start command
cmd_start() {
    info "Starting all services..."
    
    # Remove stuck containers in Created status
    CREATED_CONTAINERS=$($DOCKER_CMD ps -a --filter "status=created" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$CREATED_CONTAINERS" ]; then
        warn "Removing stuck containers in Created status..."
        echo "$CREATED_CONTAINERS" | xargs -r $DOCKER_CMD rm -f 2>/dev/null || true
    fi
    
    # Start services
    $DOCKER_CMD compose up -d
    
    info "Waiting for services to initialize..."
    sleep 5
    
    # Show status
    info "Service status:"
    $DOCKER_CMD ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|observability" || true
    
    IP=$(get_server_ip)
    echo ""
    success "Services started!"
    info "Access endpoints:"
    echo "  Grafana:       http://${IP}:3000"
    echo "  Kibana:        http://${IP}:5601"
    echo "  Prometheus:    http://${IP}:9090"
    echo "  Elasticsearch: http://${IP}:9200"
    echo ""
    info "Wait 2-3 minutes for services to fully initialize, then check: $0 status"
}

# Stop command
cmd_stop() {
    info "Stopping all services..."
    $DOCKER_CMD compose down
    success "Services stopped"
}

# Restart command
cmd_restart() {
    info "Restarting all services..."
    $DOCKER_CMD compose restart
    success "Services restarted"
}

# Status command
cmd_status() {
    info "Service Status:"
    echo ""
    $DOCKER_CMD ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|observability" || warn "No services running"
    
    echo ""
    info "Health Checks:"
    
    # Check Elasticsearch
    if curl -s http://localhost:9200/_cluster/health?pretty >/dev/null 2>&1; then
        ES_HEALTH=$(curl -s http://localhost:9200/_cluster/health?pretty | grep -o '"status" : "[^"]*"' | cut -d'"' -f4)
        if [ "$ES_HEALTH" = "green" ] || [ "$ES_HEALTH" = "yellow" ]; then
            success "Elasticsearch: $ES_HEALTH"
        else
            warn "Elasticsearch: $ES_HEALTH"
        fi
    else
        warn "Elasticsearch: Not responding"
    fi
    
    # Check Prometheus
    if curl -s http://localhost:9090/-/healthy >/dev/null 2>&1; then
        success "Prometheus: Healthy"
    else
        warn "Prometheus: Not responding"
    fi
    
    # Check indices
    if curl -s http://localhost:9200/_cat/indices/filebeat-*?v >/dev/null 2>&1; then
        INDEX_COUNT=$(curl -s 'http://localhost:9200/filebeat-*/_count' 2>/dev/null | grep -o '"count":[0-9]*' | cut -d':' -f2 || echo "0")
        if [ "$INDEX_COUNT" != "0" ] && [ -n "$INDEX_COUNT" ]; then
            success "Filebeat indices: $INDEX_COUNT documents"
        else
            warn "Filebeat indices: No data yet (wait 2-5 minutes)"
        fi
    fi
}

# Logs command
cmd_logs() {
    SERVICE=${1:-}
    if [ -z "$SERVICE" ]; then
        error "Please specify a service name"
        echo "Available services: filebeat, logstash, elasticsearch, kibana, grafana, prometheus, alertmanager, cadvisor, node_exporter"
        exit 1
    fi
    
    CONTAINER_NAME="observability-stack-master-${SERVICE}-1"
    if $DOCKER_CMD ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        info "Showing logs for $SERVICE (Ctrl+C to exit)..."
        $DOCKER_CMD logs -f "$CONTAINER_NAME"
    else
        error "Container $CONTAINER_NAME not found or not running"
        echo "Run '$0 status' to see running services"
        exit 1
    fi
}

# Fix command
cmd_fix() {
    info "Fixing common issues..."
    
    # Fix Filebeat lock file
    if [ -f ./data/filebeat/filebeat.lock ]; then
        warn "Removing Filebeat lock file..."
        sudo rm -f ./data/filebeat/filebeat.lock
        success "Filebeat lock file removed"
    fi
    
    # Fix Logstash permissions
    if [ -d ./data/logstash ]; then
        warn "Fixing Logstash permissions..."
        sudo chown -R 1000:1000 ./data/logstash 2>/dev/null || true
        success "Logstash permissions fixed"
    fi
    
    # Remove stuck containers
    STUCK_CONTAINERS=$($DOCKER_CMD ps -a --filter "status=created" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$STUCK_CONTAINERS" ]; then
        warn "Removing stuck containers..."
        echo "$STUCK_CONTAINERS" | xargs -r $DOCKER_CMD rm -f 2>/dev/null || true
        success "Stuck containers removed"
    fi
    
    # Force stop and remove Filebeat/Logstash if restarting
    RESTARTING=$($DOCKER_CMD ps --filter "status=restarting" --format "{{.Names}}" 2>/dev/null || true)
    if echo "$RESTARTING" | grep -q "filebeat\|logstash"; then
        warn "Stopping restarting containers..."
        echo "$RESTARTING" | grep -E "filebeat|logstash" | xargs -r $DOCKER_CMD kill 2>/dev/null || true
        echo "$RESTARTING" | grep -E "filebeat|logstash" | xargs -r $DOCKER_CMD rm -f 2>/dev/null || true
        success "Restarting containers stopped"
    fi
    
    success "Fix complete! Run '$0 start' to restart services"
}

# Clean command
cmd_clean() {
    REMOVE_VOLUMES=0
    for arg in "$@"; do
        case "$arg" in
            --remove-volumes) REMOVE_VOLUMES=1 ;;
            *) ;;
        esac
    done
    
    if [ "$REMOVE_VOLUMES" -eq 1 ]; then
        warn "WARNING: This will remove ALL volumes and data!"
        read -p "Are you sure? Type 'yes' to continue: " confirm
        if [ "$confirm" != "yes" ]; then
            info "Cancelled"
            exit 0
        fi
        info "Removing containers, images, and volumes..."
        $DOCKER_CMD compose down -v
        $DOCKER_CMD system prune -a -f
        $DOCKER_CMD volume prune -f
    else
        info "Cleaning containers and images (keeping volumes)..."
        $DOCKER_CMD compose down
        $DOCKER_CMD system prune -a -f --volumes=false
    fi
    
    success "Cleanup complete"
}

# Health command
cmd_health() {
    info "Running health checks..."
    echo ""
    
    # Check containers
    RUNNING=$($DOCKER_CMD ps --format "{{.Names}}" | grep observability | wc -l)
    TOTAL=9
    if [ "$RUNNING" -eq "$TOTAL" ]; then
        success "All $TOTAL containers running"
    else
        warn "Only $RUNNING/$TOTAL containers running"
    fi
    
    echo ""
    
    # Elasticsearch
    if curl -s http://localhost:9200/_cluster/health?pretty >/dev/null 2>&1; then
        ES_STATUS=$(curl -s http://localhost:9200/_cluster/health?pretty | grep '"status"' | cut -d'"' -f4)
        if [ "$ES_STATUS" = "green" ] || [ "$ES_STATUS" = "yellow" ]; then
            success "Elasticsearch: $ES_STATUS"
        else
            error "Elasticsearch: $ES_STATUS"
        fi
    else
        error "Elasticsearch: Not responding"
    fi
    
    # Prometheus
    if curl -s http://localhost:9090/-/healthy >/dev/null 2>&1; then
        success "Prometheus: Healthy"
    else
        error "Prometheus: Not responding"
    fi
    
    # Grafana
    if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
        success "Grafana: Healthy"
    else
        error "Grafana: Not responding"
    fi
    
    # Kibana
    if curl -s http://localhost:5601/api/status >/dev/null 2>&1; then
        success "Kibana: Healthy"
    else
        error "Kibana: Not responding"
    fi
    
    # Check data flow
    echo ""
    info "Data Flow:"
    INDEX_COUNT=$(curl -s 'http://localhost:9200/filebeat-*/_count' 2>/dev/null | grep -o '"count":[0-9]*' | cut -d':' -f2 || echo "0")
    if [ "$INDEX_COUNT" != "0" ] && [ -n "$INDEX_COUNT" ]; then
        success "Filebeat data: $INDEX_COUNT documents indexed"
    else
        warn "Filebeat data: No documents yet (wait 2-5 minutes after start)"
    fi
}

# Main command router
main() {
    COMMAND=${1:-help}
    
    case "$COMMAND" in
        setup)
            cmd_setup
            ;;
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        status)
            cmd_status
            ;;
        logs)
            cmd_logs "${2:-}"
            ;;
        fix)
            cmd_fix
            ;;
        clean)
            shift
            cmd_clean "$@"
            ;;
        health)
            cmd_health
            ;;
        user)
            shift
            cmd_user "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $COMMAND"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# User management command
cmd_user() {
    SUBCOMMAND=${1:-}
    
    if [ -z "$SUBCOMMAND" ]; then
        error "Please specify a user subcommand: create, list, delete, change-password"
        echo ""
        echo "Examples:"
        echo "  $0 user create <username> <email> <password> [role]"
        echo "  $0 user list"
        echo "  $0 user delete <username>"
        echo "  $0 user change-password <username> <new-password>"
        echo ""
        echo "Roles: Admin, Editor, Viewer (default: Viewer)"
        exit 1
    fi
    
    # Get Grafana admin credentials from .env
    if [ -f .env ]; then
        source .env
    fi
    GRAFANA_USER=${GRAFANA_ADMIN_USER:-admin}
    GRAFANA_PASS=${GRAFANA_ADMIN_PASSWORD:-admin}
    GRAFANA_URL="http://localhost:3000"
    
    # Check if Grafana is running
    if ! curl -s "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
        error "Grafana is not running. Start it with: $0 start"
        exit 1
    fi
    
    case "$SUBCOMMAND" in
        create)
            USERNAME=${2:-}
            EMAIL=${3:-}
            PASSWORD=${4:-}
            ROLE=${5:-Viewer}
            
            if [ -z "$USERNAME" ] || [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
                error "Usage: $0 user create <username> <email> <password> [role]"
                echo "Roles: Admin, Editor, Viewer (default: Viewer)"
                exit 1
            fi
            
            # Validate role
            if [[ ! "$ROLE" =~ ^(Admin|Editor|Viewer)$ ]]; then
                error "Invalid role: $ROLE. Must be Admin, Editor, or Viewer"
                exit 1
            fi
            
            info "Creating Grafana user: $USERNAME"
            
            RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
                -H "Content-Type: application/json" \
                -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                -d "{
                    \"name\": \"$USERNAME\",
                    \"email\": \"$EMAIL\",
                    \"login\": \"$USERNAME\",
                    \"password\": \"$PASSWORD\",
                    \"OrgId\": 1
                }" \
                "${GRAFANA_URL}/api/admin/users")
            
            HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
            BODY=$(echo "$RESPONSE" | sed '$d')
            
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
                USER_ID=$(echo "$BODY" | grep -o '"id":[0-9]*' | cut -d':' -f2)
                
                # Set user role
                curl -s -X PUT \
                    -H "Content-Type: application/json" \
                    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                    -d "{\"role\": \"$ROLE\"}" \
                    "${GRAFANA_URL}/api/org/users/${USER_ID}" >/dev/null
                
                success "User '$USERNAME' created successfully with role '$ROLE'"
            else
                ERROR_MSG=$(echo "$BODY" | grep -o '"message":"[^"]*"' | cut -d'"' -f4 || echo "Unknown error")
                error "Failed to create user: $ERROR_MSG (HTTP $HTTP_CODE)"
                exit 1
            fi
            ;;
            
        list)
            info "Listing Grafana users:"
            echo ""
            
            RESPONSE=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                "${GRAFANA_URL}/api/users")
            
            if echo "$RESPONSE" | grep -q '"id"'; then
                # Try to parse JSON nicely, fallback to raw output
                if command -v jq >/dev/null 2>&1; then
                    echo "$RESPONSE" | jq -r '.[] | "  - \(.login) (\(.email)) - Role: \(.role // "N/A")"'
                elif command -v python3 >/dev/null 2>&1; then
                    echo "$RESPONSE" | python3 -c "import sys, json; [print(f\"  - {u['login']} ({u['email']})\") for u in json.load(sys.stdin)]" 2>/dev/null || echo "$RESPONSE"
                else
                    echo "$RESPONSE" | grep -o '"login":"[^"]*","email":"[^"]*"' | \
                        sed 's/"login":"\([^"]*\)","email":"\([^"]*\)"/  - \1 (\2)/' || echo "$RESPONSE"
                fi
            else
                warn "No users found or unable to fetch users"
            fi
            ;;
            
        delete)
            USERNAME=${2:-}
            
            if [ -z "$USERNAME" ]; then
                error "Usage: $0 user delete <username>"
                exit 1
            fi
            
            # Get user ID
            USER_ID=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                "${GRAFANA_URL}/api/users/lookup?loginOrEmail=${USERNAME}" | \
                grep -o '"id":[0-9]*' | cut -d':' -f2)
            
            if [ -z "$USER_ID" ]; then
                error "User '$USERNAME' not found"
                exit 1
            fi
            
            warn "Deleting user: $USERNAME (ID: $USER_ID)"
            read -p "Are you sure? (yes/no): " confirm
            
            if [ "$confirm" != "yes" ]; then
                info "Cancelled"
                exit 0
            fi
            
            HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE \
                -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                "${GRAFANA_URL}/api/admin/users/${USER_ID}")
            
            if [ "$HTTP_CODE" = "200" ]; then
                success "User '$USERNAME' deleted successfully"
            else
                error "Failed to delete user (HTTP $HTTP_CODE)"
                exit 1
            fi
            ;;
            
        change-password)
            USERNAME=${2:-}
            NEW_PASSWORD=${3:-}
            
            if [ -z "$USERNAME" ] || [ -z "$NEW_PASSWORD" ]; then
                error "Usage: $0 user change-password <username> <new-password>"
                exit 1
            fi
            
            # Get user ID
            USER_ID=$(curl -s -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                "${GRAFANA_URL}/api/users/lookup?loginOrEmail=${USERNAME}" | \
                grep -o '"id":[0-9]*' | cut -d':' -f2)
            
            if [ -z "$USER_ID" ]; then
                error "User '$USERNAME' not found"
                exit 1
            fi
            
            info "Changing password for user: $USERNAME"
            
            HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X PUT \
                -H "Content-Type: application/json" \
                -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                -d "{\"password\": \"$NEW_PASSWORD\"}" \
                "${GRAFANA_URL}/api/admin/users/${USER_ID}/password")
            
            if [ "$HTTP_CODE" = "200" ]; then
                success "Password changed successfully for user '$USERNAME'"
            else
                error "Failed to change password (HTTP $HTTP_CODE)"
                exit 1
            fi
            ;;
            
        *)
            error "Unknown user subcommand: $SUBCOMMAND"
            echo "Available subcommands: create, list, delete, change-password"
            exit 1
            ;;
    esac
}

main "$@"

