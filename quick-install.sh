#!/bin/bash
set -euo pipefail

# Quick ERPNext Installation Script for Debian 13
# Based on simplified installation process with security improvements

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (can be overridden by config.sh)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/erpnext-quick-install.log"
MYSQL_CRED_FILE="/root/mysql_credentials.txt"
ADMIN_CRED_FILE="/root/admin_credentials.txt"
SECURE_DIR="/root/.erpnext-install"
DEFAULT_DOMAIN="site1.local"
DEFAULT_FRAPPE_USER="frappe"

# Load config if exists
if [ -f "./config.sh" ]; then
    source ./config.sh
    DEFAULT_DOMAIN="${CONFIG_DEFAULT_DOMAIN:-site1.local}"
    DEFAULT_FRAPPE_USER="${CONFIG_DEFAULT_USER:-frappe}"
fi

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2
    exit 1
}

success() {
    log "${GREEN}✓ $1${NC}"
}

warning() {
    log "${YELLOW}⚠ $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root"
fi

# Fix Debian 13 repository configuration
fix_debian_repositories() {
    log "Fixing Debian 13 repository configuration..."

    # Install basic certificates first
    apt-get install -y --no-install-recommends ca-certificates debian-archive-keyring 2>/dev/null || true

    # Check if we're on Debian 13 and fix sources
    . /etc/os-release
    if [[ "$ID" == "debian" && "${VERSION_ID}" == "13" ]]; then
        # Check if using new .sources format
        if [ -f /etc/apt/sources.list.d/debian.sources ]; then
            # Backup original
            cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.backup 2>/dev/null || true

            # Ensure contrib and non-free are enabled
            if ! grep -q "contrib" /etc/apt/sources.list.d/debian.sources; then
                sed -i 's/Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
                success "Added contrib and non-free components to debian.sources"
            fi
        elif [ -f /etc/apt/sources.list ]; then
            # Backup original
            cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true

            # Ensure contrib and non-free are enabled
            if ! grep -q "contrib" /etc/apt/sources.list; then
                sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
                success "Added contrib and non-free components to sources.list"
            fi
        fi

        # Force update package lists
        apt-get update --allow-releaseinfo-change || apt-get update || warning "Failed to update package lists"
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."

    # Check Debian version
    . /etc/os-release
    if [[ "$ID" != "debian" ]] || [[ "${VERSION_ID}" != "13" ]]; then
        warning "This script is designed for Debian 13. Detected: $PRETTY_NAME"
    fi

    # Check RAM
    local ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$ram_gb" -lt 4 ]; then
        error_exit "Need at least 4GB RAM, have ${ram_gb}GB"
    fi

    # Check disk space
    local disk_gb=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$disk_gb" -lt 20 ]; then
        error_exit "Need at least 20GB free disk space, have ${disk_gb}GB"
    fi

    success "System requirements check passed"
}

# Create secure directory
setup_secure_dir() {
    if [ ! -d "$SECURE_DIR" ]; then
        mkdir -p "$SECURE_DIR"
        chmod 700 "$SECURE_DIR"
    fi
}

# Main installation function
main() {
    log "Starting quick ERPNext installation on Debian 13"

    # Fix repositories first (critical for Debian 13)
    fix_debian_repositories

    check_requirements
    setup_secure_dir

    # 1. System preparation
    log "Step 1: System preparation"
    apt update && apt upgrade -y
    apt install -y sudo curl git build-essential wget pwgen

    # 2. Create frappe user with limited sudo
    log "Step 2: Creating frappe user"
    if ! id "$DEFAULT_FRAPPE_USER" &>/dev/null; then
        adduser --disabled-password --gecos "" "$DEFAULT_FRAPPE_USER"
        usermod -aG sudo "$DEFAULT_FRAPPE_USER"

        # Limited sudo privileges instead of NOPASSWD:ALL
        cat > "/etc/sudoers.d/$DEFAULT_FRAPPE_USER" << EOF
$DEFAULT_FRAPPE_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/nginx, /usr/bin/supervisorctl
EOF
        chmod 440 "/etc/sudoers.d/$DEFAULT_FRAPPE_USER"
    fi

    # 3. MariaDB setup with secure password generation
    log "Step 3: MariaDB setup"
    apt install -y mariadb-server mariadb-client libmariadb-dev

    local db_root_pwd=$(pwgen -s 24 1)
    echo "MariaDB root password: $db_root_pwd" > "$MYSQL_CRED_FILE"
    chmod 600 "$MYSQL_CRED_FILE"

    systemctl start mariadb
    systemctl enable mariadb

    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$db_root_pwd';"
    mysql -u root -p"$db_root_pwd" -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -p"$db_root_pwd" -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -p"$db_root_pwd" -e "FLUSH PRIVILEGES;"

    # MariaDB config for Frappe
    cat > /etc/mysql/mariadb.conf.d/z_frappe.cnf << 'EOF'
[server]
innodb_file_per_table = 1
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
[mysql]
default-character-set = utf8mb4
EOF
    systemctl restart mariadb

    # Store password securely
    echo "$db_root_pwd" > "$SECURE_DIR/mysql_root_password"
    chmod 600 "$SECURE_DIR/mysql_root_password"

    # 4. Node.js setup
    log "Step 4: Node.js setup"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    npm install -g yarn

    # 5. Python and dependencies
    log "Step 5: Python and dependencies"
    apt install -y python3-dev python3-venv python3-pip redis-server \
        xvfb libfontconfig wkhtmltopdf libssl-dev libcrypto++-dev nginx

    systemctl enable --now redis-server

    # 6. Frappe Bench installation
    log "Step 6: Frappe Bench installation"
    su - "$DEFAULT_FRAPPE_USER" << 'EOF'
export PATH=$PATH:$HOME/.local/bin
pip3 install --user frappe-bench --break-system-packages
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
source ~/.bashrc
bench init frappe-bench --frappe-branch version-15 --python python3
EOF

    # 7. ERPNext installation
    log "Step 7: ERPNext installation"
    local admin_pwd=$(pwgen -s 16 1)
    echo "ERPNext admin password: $admin_pwd" > "$ADMIN_CRED_FILE"
    chmod 600 "$ADMIN_CRED_FILE"

    su - "$DEFAULT_FRAPPE_USER" << EOF
export PATH=\$PATH:\$HOME/.local/bin
cd frappe-bench
echo "$db_root_pwd" | bench new-site $DEFAULT_DOMAIN --mariadb-root-password - --admin-password "$admin_pwd"
bench get-app erpnext --branch version-15
bench --site $DEFAULT_DOMAIN install-app erpnext
EOF

    # 8. Production setup
    log "Step 8: Production setup"
    su - "$DEFAULT_FRAPPE_USER" << EOF
export PATH=\$PATH:\$HOME/.local/bin
cd frappe-bench
sudo bench setup production $DEFAULT_FRAPPE_USER --yes
EOF

    # 9. Firewall setup
    log "Step 9: Firewall setup"
    apt install -y ufw
    ufw allow "Nginx Full"
    ufw allow ssh
    ufw --force enable

    # 10. Test installation
    log "Step 10: Testing installation"
    if mysql -u root -p"$db_root_pwd" -e "SELECT 1;" &>/dev/null; then
        success "MariaDB test passed"
    else
        warning "MariaDB test failed"
    fi

    if redis-cli ping | grep -q "PONG"; then
        success "Redis test passed"
    else
        warning "Redis test failed"
    fi

    # Completion message
    log ""
    log "${GREEN}=========================================="
    log "  Quick Installation Complete!"
    log "==========================================${NC}"
    log ""
    log "${BLUE}Access Information:${NC}"
    log "• ERPNext URL: http://$DEFAULT_DOMAIN"
    log "• Admin Username: administrator"
    log "• Admin Password: $admin_pwd"
    log "• Credentials saved in: $ADMIN_CRED_FILE"
    log "• MariaDB root password saved in: $MYSQL_CRED_FILE"
    log ""
    log "${YELLOW}Security Notes:${NC}"
    log "• Change admin password immediately after first login"
    log "• Consider setting up SSL certificates"
    log "• Review firewall rules and sudo permissions"
    log ""
    log "${BLUE}Next Steps:${NC}"
    log "1. Access ERPNext at http://$DEFAULT_DOMAIN"
    log "2. Login with administrator / $admin_pwd"
    log "3. Configure SSL: bench setup add-domain $DEFAULT_DOMAIN --ssl-certificate"
    log "4. Setup backup: bench setup add-backup $DEFAULT_DOMAIN"
}

# Show usage
usage() {
    echo "Quick ERPNext Installation Script for Debian 13"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help     Show this help message"
    echo "  --test     Run system requirements check only"
    echo ""
    echo "Configuration can be customized in config.sh"
    echo "Default domain: $DEFAULT_DOMAIN"
    echo "Default user: $DEFAULT_FRAPPE_USER"
}

# Parse arguments
case "${1:-}" in
    --help)
        usage
        exit 0
        ;;
    --test)
        check_requirements
        echo "System requirements check completed successfully"
        exit 0
        ;;
    "")
        main "$@"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
