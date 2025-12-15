#!/usr/bin/env bash
# Network Observability Stack - Remote VM Monitoring Setup Script
# This script installs node_exporter and Filebeat on a Linux VM to enable monitoring
# by the Network Observability Stack running at 192.168.5.34

set -euo pipefail

# Configuration
OBSERVABILITY_STACK_HOST="${OBSERVABILITY_STACK_HOST:-192.168.5.34}"
OBSERVABILITY_STACK_PORT="${OBSERVABILITY_STACK_PORT:-5044}"
NODE_EXPORTER_VERSION="1.8.2"
FILEBEAT_VERSION="8.15.0"
HOSTNAME=$(hostname)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (use sudo)"
    exit 1
fi

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        error "Cannot detect OS. This script supports Ubuntu/Debian and RHEL/CentOS"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update -qq
        apt-get install -y -qq curl wget systemd
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y -q curl wget systemd
        else
            yum install -y -q curl wget systemd
        fi
    else
        error "Unsupported OS: $OS"
        exit 1
    fi
    success "Dependencies installed"
}

# Install node_exporter
install_node_exporter() {
    info "Installing node_exporter v${NODE_EXPORTER_VERSION}..."
    
    # Check if already installed
    if systemctl is-active --quiet node_exporter 2>/dev/null; then
        warn "node_exporter service is already running"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Skipping node_exporter installation"
            return
        fi
        systemctl stop node_exporter || true
    fi
    
    # Download and install
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    DOWNLOAD_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
    
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    info "Downloading node_exporter from $DOWNLOAD_URL"
    curl -L -o node_exporter.tar.gz "$DOWNLOAD_URL"
    
    tar -xzf node_exporter.tar.gz
    cp node_exporter-*/node_exporter /usr/local/bin/node_exporter
    chmod +x /usr/local/bin/node_exporter
    
    cd /
    rm -rf "$TMP_DIR"
    
    # Create systemd service
    info "Creating systemd service for node_exporter"
    cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    # Wait a moment and check status
    sleep 2
    if systemctl is-active --quiet node_exporter; then
        success "node_exporter installed and running on port 9100"
    else
        error "node_exporter failed to start. Check logs: journalctl -u node_exporter"
        exit 1
    fi
}

# Install Filebeat
install_filebeat() {
    info "Installing Filebeat v${FILEBEAT_VERSION}..."
    
    # Check if already installed and working
    if command -v filebeat >/dev/null 2>&1 && [ -f /etc/filebeat/filebeat.yml ]; then
        if systemctl is-active --quiet filebeat 2>/dev/null; then
            warn "Filebeat is already installed and running"
            read -p "Do you want to reinstall/reconfigure? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Skipping Filebeat installation"
                return
            fi
            systemctl stop filebeat || true
        fi
    fi
    
    # Download and install
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case $ARCH in
        amd64|x86_64) ARCH="x86_64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        # Try installing via Elastic APT repository first (more reliable)
        if ! command -v filebeat >/dev/null 2>&1; then
            info "Installing Filebeat via Elastic APT repository..."
            if ! dpkg -l | grep -q "elasticsearch"; then
                # Install Elastic GPG key and repository
                curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - 2>/dev/null || \
                wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add - 2>/dev/null || true
                
                echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list >/dev/null
                apt-get update -qq
            fi
            
            # Try to install via apt
            if apt-get install -y -qq filebeat=${FILEBEAT_VERSION} 2>/dev/null; then
                success "Filebeat installed via APT repository"
            else
                # Fallback to direct download
                warn "APT installation failed, trying direct download..."
                DOWNLOAD_URL="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FILEBEAT_VERSION}-linux-${ARCH}.deb"
                TMP_DIR=$(mktemp -d)
                cd "$TMP_DIR"
                
                info "Downloading Filebeat from $DOWNLOAD_URL"
                if ! curl -f -L -o filebeat.deb "$DOWNLOAD_URL" 2>/dev/null; then
                    error "Failed to download Filebeat. Check your internet connection."
                    cd /
                    rm -rf "$TMP_DIR"
                    exit 1
                fi
                
                # Check file size (should be > 1MB for a valid deb)
                FILE_SIZE=$(stat -f%z filebeat.deb 2>/dev/null || stat -c%s filebeat.deb 2>/dev/null || echo "0")
                if [ "$FILE_SIZE" -lt 1048576 ]; then
                    error "Downloaded file is too small ($FILE_SIZE bytes). Download may have failed."
                    error "File contents (first 200 chars):"
                    head -c 200 filebeat.deb
                    echo ""
                    cd /
                    rm -rf "$TMP_DIR"
                    exit 1
                fi
                
                # Verify it's a valid deb file
                if ! file filebeat.deb 2>/dev/null | grep -qE "(Debian|ar archive)"; then
                    error "Downloaded file is not a valid Debian package."
                    error "File type: $(file filebeat.deb 2>/dev/null || echo 'unknown')"
                    error "File size: $FILE_SIZE bytes"
                    cd /
                    rm -rf "$TMP_DIR"
                    exit 1
                fi
                
                info "Installing Filebeat package..."
                if ! dpkg -i filebeat.deb 2>/dev/null; then
                    info "Resolving dependencies..."
                    apt-get install -f -y -qq
                fi
                
                cd /
                rm -rf "$TMP_DIR"
            fi
        fi
    elif [ "$OS" = "rhel" ] || [ "$OS" = "centos" ] || [ "$OS" = "fedora" ]; then
        DOWNLOAD_URL="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FILEBEAT_VERSION}-linux-${ARCH}.rpm"
        TMP_DIR=$(mktemp -d)
        cd "$TMP_DIR"
        
        info "Downloading Filebeat from $DOWNLOAD_URL"
        if ! curl -f -L -o filebeat.rpm "$DOWNLOAD_URL"; then
            error "Failed to download Filebeat. Check your internet connection."
            cd /
            rm -rf "$TMP_DIR"
            exit 1
        fi
        
        # Verify it's a valid rpm file
        if ! file filebeat.rpm | grep -q "RPM"; then
            error "Downloaded file is not a valid RPM package. File may be corrupted or wrong format."
            error "File type: $(file filebeat.rpm)"
            cd /
            rm -rf "$TMP_DIR"
            exit 1
        fi
        
        info "Installing Filebeat package..."
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y filebeat.rpm
        else
            yum install -y filebeat.rpm
        fi
        
        cd /
        rm -rf "$TMP_DIR"
    fi
    
    # Verify Filebeat was installed
    if ! command -v filebeat >/dev/null 2>&1; then
        error "Filebeat installation failed. filebeat command not found."
        exit 1
    fi
    
    # Ensure /etc/filebeat directory exists
    mkdir -p /etc/filebeat
    
    # Configure Filebeat
    info "Configuring Filebeat to send logs to ${OBSERVABILITY_STACK_HOST}:${OBSERVABILITY_STACK_PORT}"
    cat > /etc/filebeat/filebeat.yml <<EOF
# =========================== Inputs ===========================
filebeat.inputs:
  # System logs
  - type: filestream
    id: syslog
    enabled: true
    paths:
      - /var/log/syslog
      - /var/log/messages
      - /var/log/auth.log
      - /var/log/secure
      - /var/log/kern.log
    prospector.scanner.exclude_files: ['\.gz$']
    
  # Application logs (common locations)
  - type: filestream
    id: app-logs
    enabled: true
    paths:
      - /var/log/*.log
      - /opt/*/logs/*.log
    prospector.scanner.exclude_files: ['\.gz$']

# ============================== Output ==============================
output.logstash:
  hosts: ["${OBSERVABILITY_STACK_HOST}:${OBSERVABILITY_STACK_PORT}"]

# ============================== Processors ================================
processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_fields:
      fields:
        hostname: ${HOSTNAME}
        monitored_by: network-observability-stack
EOF
    
    # Set permissions
    chown root:root /etc/filebeat/filebeat.yml
    chmod 600 /etc/filebeat/filebeat.yml
    
    # Test configuration
    info "Testing Filebeat configuration..."
    if filebeat test config -c /etc/filebeat/filebeat.yml >/dev/null 2>&1; then
        success "Filebeat configuration is valid"
    else
        warn "Filebeat configuration test had warnings (this may be normal)"
    fi
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable filebeat
    systemctl start filebeat
    
    # Wait a moment and check status
    sleep 2
    if systemctl is-active --quiet filebeat; then
        success "Filebeat installed and running"
    else
        error "Filebeat failed to start. Check logs: journalctl -u filebeat"
        warn "Filebeat may need manual configuration. Continuing anyway..."
    fi
}

# Configure firewall
configure_firewall() {
    info "Configuring firewall to allow monitoring..."
    
    # Check if firewall is active
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            info "UFW firewall detected, adding rule for node_exporter (port 9100)"
            ufw allow from ${OBSERVABILITY_STACK_HOST} to any port 9100 comment 'Prometheus node_exporter'
            success "Firewall rule added"
        else
            info "UFW is not active, skipping firewall configuration"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld; then
            info "firewalld detected, adding rule for node_exporter (port 9100)"
            firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='${OBSERVABILITY_STACK_HOST}' port port='9100' protocol='tcp' accept"
            firewall-cmd --reload
            success "Firewall rule added"
        else
            info "firewalld is not active, skipping firewall configuration"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        info "iptables detected, adding rule for node_exporter (port 9100)"
        iptables -C INPUT -p tcp -s ${OBSERVABILITY_STACK_HOST} --dport 9100 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp -s ${OBSERVABILITY_STACK_HOST} --dport 9100 -j ACCEPT
        success "Firewall rule added (note: make this persistent with your iptables-save method)"
    else
        warn "No firewall detected or firewall commands not found. Please manually allow port 9100 from ${OBSERVABILITY_STACK_HOST}"
    fi
}

# Print summary
print_summary() {
    echo ""
    success "Installation complete!"
    echo ""
    info "Services installed:"
    echo "  - node_exporter: running on port 9100"
    echo "  - Filebeat: sending logs to ${OBSERVABILITY_STACK_HOST}:${OBSERVABILITY_STACK_PORT}"
    echo ""
    info "Next steps:"
    echo "  1. Add this VM to Prometheus scrape config:"
    echo "     Edit prometheus/prometheus.yml and add to 'remote_node_exporter' job:"
    echo "       - targets: ['$(hostname -I | awk '{print $1}'):9100']"
    echo "         labels:"
    echo "           host: '${HOSTNAME}'"
    echo ""
    echo "  2. Add this VM to blackbox ping monitoring:"
    echo "     Edit prometheus/prometheus.yml and add to 'blackbox_icmp' job:"
    echo "       - targets: ['$(hostname -I | awk '{print $1}')']"
    echo "         labels:"
    echo "           host: '${HOSTNAME}'"
    echo ""
    echo "  3. Reload Prometheus configuration:"
    echo "     curl -X POST http://${OBSERVABILITY_STACK_HOST}:9090/-/reload"
    echo ""
    info "Check service status:"
    echo "  systemctl status node_exporter"
    echo "  systemctl status filebeat"
    echo ""
    info "View logs:"
    echo "  journalctl -u node_exporter -f"
    echo "  journalctl -u filebeat -f"
    echo ""
}

# Main execution
main() {
    echo ""
    info "Network Observability Stack - Remote VM Monitoring Setup"
    info "Target observability stack: ${OBSERVABILITY_STACK_HOST}"
    echo ""
    
    detect_os
    install_dependencies
    install_node_exporter
    install_filebeat
    configure_firewall
    print_summary
}

main "$@"

