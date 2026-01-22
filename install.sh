#!/bin/bash
set -euo pipefail

# ERPNext/Frappe Installation Script for Debian 13
# Interactive menu-driven installer with safety checks and rollback options

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/erpnext-install.log"
MYSQL_CRED_FILE="/root/mysql_credentials.txt"
ADMIN_CRED_FILE="/root/admin_credentials.txt"
SECURE_DIR="/root/.erpnext-install"
DEFAULT_DOMAIN="erp.local"
DEFAULT_NODE_VERSION="22"
DEFAULT_FRAPPE_USER="frappe"
BENCH_DIR=""

# Installation mode
INSTALL_MODE="interactive"  # interactive, quick, automated

# Completed steps for rollback
COMPLETED_STEPS=()

# Load config if exists
if [ -f "./config.sh" ]; then
    source ./config.sh
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            INSTALL_MODE="quick"
            DEFAULT_DOMAIN="site1.local"
            shift
            ;;
        --silent|--automated)
            INSTALL_MODE="automated"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --quick      Quick installation with default settings"
            echo "  --silent     Automated installation (requires environment variables)"
            echo "  --help       Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Check system requirements
check_requirements() {
    log "${BLUE}=== Checking System Requirements ===${NC}"

    # Check Debian version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" != "debian" ]] || [[ "${VERSION_ID}" != "13" ]]; then
            warning "This script is designed for Debian 13. Detected: $PRETTY_NAME"
            if ! ask_yes_no "Continue anyway?" "n"; then
                exit 1
            fi
        fi
    fi

    # Check RAM (minimum 4GB recommended)
    local total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 4 ]; then
        warning "System has ${total_ram}GB RAM. Recommended: 4GB+"
        if [ "$INSTALL_MODE" = "interactive" ] && ! ask_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi

    # Check free disk space (minimum 20GB)
    local free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$free_space" -lt 20 ]; then
        error_exit "Insufficient disk space. Need 20GB+, have ${free_space}GB"
    fi

    success "System requirements check passed"
}

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    log "${YELLOW}Installation failed. Check log at $LOG_FILE${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}✓ $1${NC}"
}

# Warning message
warning() {
    log "${YELLOW}⚠ $1${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ $1${NC}"
}

# Check if package is installed
is_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Install package if not present
install_package() {
    local package="$1"
    if ! is_installed "$package"; then
        info "Installing $package..."
        apt-get install -y "$package" || error_exit "Failed to install $package"
        success "$package installed"
    else
        info "$package already installed, skipping..."
    fi
}

# Interactive yes/no prompt
ask_yes_no() {
    if [ "$INSTALL_MODE" = "quick" ] || [ "$INSTALL_MODE" = "automated" ]; then
        return 0  # Default to yes for non-interactive modes
    fi
    local question="$1"
    local default="$2"
    local answer
    while true; do
        read -p "$question (y/n) [default: $default]: " -r answer
        case ${answer:-$default} in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# Interactive input with validation
ask_input() {
    local question="$1"
    local default="$2"
    if [ "$INSTALL_MODE" = "quick" ] || [ "$INSTALL_MODE" = "automated" ]; then
        echo "$default"
        return
    fi
    local input
    read -p "$question [default: $default]: " input
    echo "${input:-$default}"
}

# Validate domain name
validate_domain() {
    local domain="$1"
    if [[ $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$|^[a-zA-Z0-9][a-zA-Z0-9-]*\.local$ ]]; then
        return 0
    else
        return 1
    fi
}

# Ask for domain with validation
ask_domain() {
    local domain
    while true; do
        if [ "$INSTALL_MODE" = "interactive" ]; then
            domain=$(ask_input "Enter domain for ERPNext site" "$DEFAULT_DOMAIN")
        else
            domain="$DEFAULT_DOMAIN"
        fi
        if validate_domain "$domain"; then
            echo "$domain"
            return
        else
            if [ "$INSTALL_MODE" = "interactive" ]; then
                warning "Invalid domain format. Please use a valid domain name."
            else
                warning "Using default domain $DEFAULT_DOMAIN due to invalid format"
                echo "$DEFAULT_DOMAIN"
                return
            fi
        fi
    done
}

# Track completed steps for rollback
track_step() {
    COMPLETED_STEPS+=("$1")
}

# Rollback function
rollback() {
    log "${RED}Rolling back changes...${NC}"
    for step in "${COMPLETED_STEPS[@]}"; do
        case $step in
            "mariadb")
                systemctl stop mariadb 2>/dev/null || true
                apt-get remove -y mariadb-server mariadb-client 2>/dev/null || true
                ;;
            "frappe_user")
                userdel -r "$FRAPPE_USER" 2>/dev/null || true
                ;;
            "redis")
                systemctl stop redis-server 2>/dev/null || true
                apt-get remove -y redis-server 2>/dev/null || true
                ;;
        esac
    done
}

# Improved error handling with rollback option
error_exit() {
    log "${RED}ERROR: $1${NC}" "ERROR"
    log "${YELLOW}Installation failed. Check log at $LOG_FILE${NC}" "ERROR"
    if [ ${#COMPLETED_STEPS[@]} -gt 0 ] && ask_yes_no "Attempt rollback of completed steps?" "y"; then
        rollback
    fi
    exit 1
}

# Logging function with timestamps and levels
log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Fix Debian 13 repository configuration
fix_debian_repositories() {
    log "${BLUE}=== Fixing Debian 13 Repository Configuration ===${NC}"

    # Install basic certificates first
    info "Installing basic certificates and keys..."
    apt-get install -y --no-install-recommends ca-certificates debian-archive-keyring 2>/dev/null || true

    # Check if we're on Debian 13 and fix sources
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "debian" && "${VERSION_ID}" == "13" ]]; then
            info "Detected Debian 13, checking repository configuration..."

            # Check if using new .sources format
            if [ -f /etc/apt/sources.list.d/debian.sources ]; then
                info "Updating debian.sources format..."
                # Backup original
                cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.backup 2>/dev/null || true

                # Ensure contrib and non-free are enabled
                if ! grep -q "contrib" /etc/apt/sources.list.d/debian.sources; then
                    sed -i 's/Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
                    success "Added contrib and non-free components to debian.sources"
                fi
            elif [ -f /etc/apt/sources.list ]; then
                info "Updating sources.list format..."
                # Backup original
                cp /etc/apt/sources.list /etc/apt/sources.list.backup 2>/dev/null || true

                # Ensure contrib and non-free are enabled
                if ! grep -q "contrib" /etc/apt/sources.list; then
                    sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
                    success "Added contrib and non-free components to sources.list"
                fi
            fi

            # Force update package lists
            info "Updating package lists with new repositories..."
            apt-get update --allow-releaseinfo-change || apt-get update || warning "Failed to update package lists"
        fi
    fi

    success "Repository configuration fixed"
}

# Step 1: System Preparation
prepare_system() {
    log "${BLUE}=== Step 1: System Preparation ===${NC}"

    # Fix repositories first (especially important for Debian 13)
    fix_debian_repositories

    if ask_yes_no "Update system packages?" "y"; then
        info "Updating package lists..."
        apt-get update || error_exit "Failed to update package lists"
        apt-get upgrade -y || warning "Some packages failed to upgrade"
    fi

    # Install basic utilities
    local packages=("sudo" "curl" "git" "build-essential" "wget" "pwgen")
    for pkg in "${packages[@]}"; do
        install_package "$pkg"
    done

    success "System preparation complete"
}

# Step 2: Create Frappe User
create_frappe_user() {
    log "${BLUE}=== Step 2: Create Frappe User ===${NC}"

    FRAPPE_USER=$(ask_input "Enter username for Frappe installation" "$DEFAULT_FRAPPE_USER")
    BENCH_DIR="/home/$FRAPPE_USER/frappe-bench"

    if id "$FRAPPE_USER" &>/dev/null; then
        warning "User $FRAPPE_USER already exists"
    else
        info "Creating user $FRAPPE_USER..."
        adduser --disabled-password --gecos "" "$FRAPPE_USER" || error_exit "Failed to create user"
        usermod -aG sudo "$FRAPPE_USER" || error_exit "Failed to add user to sudo group"

        # Setup limited sudo privileges for specific commands only
        cat > "/etc/sudoers.d/$FRAPPE_USER" << EOF
$FRAPPE_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/sbin/nginx, /usr/bin/supervisorctl
EOF
        chmod 440 "/etc/sudoers.d/$FRAPPE_USER"
        success "User $FRAPPE_USER created with limited sudo privileges"
    fi

    track_step "frappe_user"

    # Store username for later use
    echo "$FRAPPE_USER" > /tmp/frappe_username
}

# Secure directory for credentials
setup_secure_dir() {
    if [ ! -d "$SECURE_DIR" ]; then
        mkdir -p "$SECURE_DIR"
        chmod 700 "$SECURE_DIR"
    fi
}

# Step 3: MariaDB Setup
setup_mariadb() {
    log "${BLUE}=== Step 3: MariaDB Setup ===${NC}"

    setup_secure_dir

    # Install MariaDB
    install_package "mariadb-server"
    install_package "mariadb-client"
    install_package "libmariadb-dev"

    # Ask for root password or generate
    local root_password
    if [ -f "$MYSQL_CRED_FILE" ]; then
        root_password=$(grep "root password" "$MYSQL_CRED_FILE" | awk '{print $NF}')
        warning "MariaDB root password already exists in $MYSQL_CRED_FILE"
    else
        if ask_yes_no "Generate random MariaDB root password?" "y"; then
            root_password=$(pwgen -s 24 1)
        else
            read -sp "Enter MariaDB root password: " root_password
            echo
        fi
        echo "MariaDB root password: $root_password" > "$MYSQL_CRED_FILE"
        chmod 600 "$MYSQL_CRED_FILE"
        success "MariaDB root password saved to $MYSQL_CRED_FILE"
    fi

    # Start MariaDB if not running
    systemctl start mariadb || error_exit "Failed to start MariaDB"
    systemctl enable mariadb || error_exit "Failed to enable MariaDB"

    # Apply root password if not set
    if mysql -u root -e "SELECT 1;" &>/dev/null 2>&1; then
        info "Setting MariaDB root password..."
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_password';"
    fi

    # Secure installation
    if ask_yes_no "Run MariaDB secure installation?" "y"; then
        info "Securing MariaDB installation..."
        mysql -u root -p"$root_password" -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
        mysql -u root -p"$root_password" -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
        mysql -u root -p"$root_password" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
        mysql -u root -p"$root_password" -e "FLUSH PRIVILEGES;" 2>/dev/null || true
    fi

    # Configure MariaDB for Frappe
    info "Creating MariaDB configuration for Frappe..."
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

    systemctl restart mariadb || error_exit "Failed to restart MariaDB"
    success "MariaDB configured for Frappe"

    track_step "mariadb"

    # Store root password securely
    echo "$root_password" > "$SECURE_DIR/mysql_root_password"
    chmod 600 "$SECURE_DIR/mysql_root_password"
}

# Step 4: Node.js Setup
setup_nodejs() {
    log "${BLUE}=== Step 4: Node.js Setup ===${NC}"
    
    echo "Select Node.js version:"
    echo "1) Node.js 22 (LTS - Recommended)"
    echo "2) Node.js 24 (Current)"
    read -p "Enter choice [1-2, default: 1]: " node_choice
    
    local node_version
    case ${node_choice:-1} in
        1) node_version="22" ;;
        2) node_version="24" ;;
        *) node_version="22" ;;
    esac
    
    # Check if Node.js is already installed with correct version
    if command -v node &>/dev/null; then
        local current_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$current_version" == "$node_version" ]; then
            info "Node.js v$node_version already installed, skipping..."
            echo "$node_version" > /tmp/node_version
            return
        else
            if ask_yes_no "Node.js v$current_version found. Replace with v$node_version?" "y"; then
                apt-get remove -y nodejs npm || true
            else
                echo "$current_version" > /tmp/node_version
                return
            fi
        fi
    fi
    
    # Install Node.js
    info "Installing Node.js v$node_version..."
    curl -fsSL "https://deb.nodesource.com/setup_${node_version}.x" | bash - || error_exit "Failed to setup Node.js repository"
    install_package "nodejs"
    
    # Install Yarn
    if ! command -v yarn &>/dev/null; then
        info "Installing Yarn..."
        npm install -g yarn || error_exit "Failed to install Yarn"
    fi
    
    success "Node.js v$node_version and Yarn installed"
    echo "$node_version" > /tmp/node_version
}

# Step 5: Python and Redis Setup
setup_python_redis() {
    log "${BLUE}=== Step 5: Python and Redis Setup ===${NC}"

    # Install Python dependencies
    local python_packages=("python3-dev" "python3-venv" "python3-pip" "python3-setuptools")
    for pkg in "${python_packages[@]}"; do
        install_package "$pkg"
    done

    # Install Redis
    install_package "redis-server"

    # Install other dependencies
    local other_packages=("xvfb" "libfontconfig" "libssl-dev" "libcrypto++-dev" "nginx")

    # Try to install wkhtmltopdf, but don't fail if not available
    info "Installing wkhtmltopdf (if available)..."
    if apt-get install -y wkhtmltopdf 2>/dev/null; then
        success "wkhtmltopdf installed"
    else
        warning "wkhtmltopdf not available in repositories, skipping (PDF generation may not work)"
        # Try to install from backports if available
        if apt-get install -y -t trixie-backports wkhtmltopdf 2>/dev/null; then
            success "wkhtmltopdf installed from backports"
        fi
    fi

    for pkg in "${other_packages[@]}"; do
        install_package "$pkg"
    done

    # Enable and start Redis
    systemctl enable redis-server || error_exit "Failed to enable Redis"
    systemctl start redis-server || error_exit "Failed to start Redis"

    track_step "redis"

    success "Python and Redis setup complete"
}

# Step 6: Frappe Bench Installation
install_frappe_bench() {
    log "${BLUE}=== Step 6: Frappe Bench Installation ===${NC}"

    local frappe_user=$(cat /tmp/frappe_username)

    # Switch to frappe user and install bench
    su - "$frappe_user" << 'EOFUSER'
        # Install frappe-bench
        pip3 install --user frappe-bench --break-system-packages 2>/dev/null || pip3 install --user frappe-bench

        # Add to PATH
        if ! grep -q '.local/bin' ~/.bashrc; then
            echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
        fi
        export PATH=$PATH:$HOME/.local/bin

        # Configure yarn to use npm registry to avoid network issues
        yarn config set registry https://registry.npmjs.org/
        yarn cache clean

        # Initialize bench if not exists
        if [ ! -d "frappe-bench" ]; then
            bench init frappe-bench --frappe-branch version-15 --python python3
        else
            echo "Bench directory already exists, skipping initialization"
        fi
EOFUSER

    if [ $? -ne 0 ]; then
        error_exit "Failed to install Frappe Bench"
    fi

    success "Frappe Bench installed"
}

# Test services function
test_services() {
    log "${BLUE}=== Testing Services ===${NC}"

    # Test MariaDB
    local mysql_root_password=$(cat "$SECURE_DIR/mysql_root_password")
    if mysql -u root -p"$mysql_root_password" -e "SELECT 1;" &>/dev/null; then
        success "MariaDB connection test passed"
    else
        error_exit "MariaDB test failed"
    fi

    # Test Redis
    if redis-cli ping | grep -q "PONG"; then
        success "Redis test passed"
    else
        warning "Redis test failed"
    fi

    # Test ERPNext site
    local domain=$(cat /tmp/erpnext_domain 2>/dev/null || echo "$DEFAULT_DOMAIN")
    local frappe_user=$(cat /tmp/frappe_username)
    su - "$frappe_user" << EOFUSER
        export PATH=\$PATH:\$HOME/.local/bin
        cd frappe-bench
        if bench --site $domain doctor &>/dev/null; then
            echo "ERPNext site $domain is healthy"
        else
            echo "Warning: ERPNext site test failed"
        fi
EOFUSER
}

# Step 7: ERPNext Installation
install_erpnext() {
    log "${BLUE}=== Step 7: ERPNext Installation ===${NC}"

    local frappe_user=$(cat /tmp/frappe_username)
    local mysql_root_password=$(cat "$SECURE_DIR/mysql_root_password")
    local domain

    if [ "$INSTALL_MODE" = "interactive" ]; then
        domain=$(ask_domain)
    else
        domain="$DEFAULT_DOMAIN"
    fi

    # Generate random admin password
    local admin_password=$(pwgen -s 16 1)
    echo "ERPNext admin password: $admin_password" > "$ADMIN_CRED_FILE"
    chmod 600 "$ADMIN_CRED_FILE"
    success "Admin credentials saved to $ADMIN_CRED_FILE"

    # Store domain for later use
    echo "$domain" > /tmp/erpnext_domain

    # Create site and install ERPNext
    # Use printf to avoid heredoc variable expansion issues
    printf 'export PATH=$PATH:$HOME/.local/bin\ncd frappe-bench\n\n# Check if site exists\nif [ -d "sites/%s" ]; then\n    echo "Site %s already exists"\nelse\n    # Create new site with secure password transmission\n    echo "%s" | bench new-site %s --mariadb-root-password - --admin-password "%s"\nfi\n\n# Get and install ERPNext if not already\nif [ ! -d "apps/erpnext" ]; then\n    bench get-app erpnext --branch version-15\n    \n    # Install Node.js dependencies for ERPNext\n    cd apps/erpnext\n    yarn install --check-files || yarn install --network-timeout 100000\n    cd ../..\nfi\n\n# Install ERPNext on site\nbench --site %s install-app erpnext || echo "ERPNext may already be installed"\n\n# Set as default site\nbench use %s\n' "$mysql_root_password" "$domain" "$domain" "$mysql_root_password" "$domain" "$admin_password" "$domain" "$domain" | su - "$frappe_user"

    if [ $? -ne 0 ]; then
        warning "Some ERPNext installation steps may have failed"
    else
        success "ERPNext installed on site $domain"
        test_services
    fi
}

# Step 8: Additional Frappe Apps Selection
select_additional_apps() {
    log "${BLUE}=== Step 8: Additional Frappe Apps ===${NC}"
    
    local frappe_user=$(cat /tmp/frappe_username)
    local domain=$(cat /tmp/erpnext_domain)
    
    if ! ask_yes_no "Do you want to install additional Frappe apps?" "n"; then
        return
    fi
    
    # List of available apps compatible with ERPNext 15
    declare -A apps
    apps["hrms"]="frappe/hrms:version-15"
    apps["payments"]="frappe/payments:version-15"
    apps["webshop"]="frappe/webshop:version-15"
    apps["wiki"]="frappe/wiki:version-15"
    apps["helpdesk"]="frappe/helpdesk:version-15"
    apps["lms"]="frappe/lms:version-15"
    apps["builder"]="frappe/builder:main"
    apps["print_designer"]="frappe/print_designer:main"
    
    info "Available Frappe apps compatible with ERPNext v15:"
    for app in "${!apps[@]}"; do
        echo "  - $app"
    done
    
    for app in "${!apps[@]}"; do
        if ask_yes_no "Install $app?" "n"; then
            local repo="${apps[$app]}"
            su - "$frappe_user" << EOFUSER
                export PATH=\$PATH:\$HOME/.local/bin
                cd frappe-bench
                bench get-app $repo || echo "Failed to get $app"
                bench --site $domain install-app $app || echo "Failed to install $app"
EOFUSER
            if [ $? -eq 0 ]; then
                success "$app installed"
            else
                warning "Failed to install $app"
            fi
        fi
    done
    
    success "Additional apps selection complete"
}

# Step 9: Production Setup
setup_production() {
    log "${BLUE}=== Step 9: Production Setup ===${NC}"
    
    if ! ask_yes_no "Setup production mode (Nginx + Supervisor)?" "y"; then
        return
    fi
    
    local frappe_user=$(cat /tmp/frappe_username)
    local domain=$(cat /tmp/erpnext_domain)
    
    # Setup production
    su - "$frappe_user" << EOFUSER
        export PATH=\$PATH:\$HOME/.local/bin
        cd frappe-bench
        sudo bench setup production $frappe_user --yes
EOFUSER
    
    # Restart services
    systemctl restart nginx || warning "Failed to restart Nginx"
    supervisorctl reload || warning "Failed to reload Supervisor"
    
    success "Production setup complete"
}

# Step 10: Firewall Setup
setup_firewall() {
    log "${BLUE}=== Step 10: Firewall Setup ===${NC}"
    
    if ! ask_yes_no "Setup UFW firewall?" "y"; then
        return
    fi
    
    install_package "ufw"
    
    # Configure UFW
    ufw allow "Nginx Full" || warning "Failed to allow Nginx in UFW"
    ufw allow ssh || warning "Failed to allow SSH in UFW"
    ufw --force enable || warning "Failed to enable UFW"
    
    success "Firewall configured"
}

# Cleanup function
cleanup() {
    log "${YELLOW}Cleaning up temporary files...${NC}"
    rm -f /tmp/mysql_root_password
}

# Remove existing installation
remove_installation() {
    log "${YELLOW}Removing existing installation...${NC}"
    
    local frappe_user=$(cat /tmp/frappe_username 2>/dev/null || echo "$DEFAULT_FRAPPE_USER")
    local bench_dir="/home/$frappe_user/frappe-bench"
    
    if ask_yes_no "Remove user $frappe_user and all data?" "n"; then
        # Stop services
        supervisorctl stop all 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        
        # Remove bench directory
        rm -rf "$bench_dir" 2>/dev/null || true
        
        # Remove user
        userdel -r "$frappe_user" 2>/dev/null || true
        
        # Remove MariaDB credentials
        rm -f "$MYSQL_CRED_FILE"
        
        # Cleanup temp files
        rm -f /tmp/frappe_username /tmp/node_version /tmp/erpnext_domain
        
        success "Existing installation removed"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "=========================================="
    echo "  ERPNext/Frappe Installation Script"
    echo "  for Debian 13"
    echo "=========================================="
    echo ""
    echo "1) Full Installation (recommended)"
    echo "2) Step-by-step Installation"
    echo "3) Remove Existing Installation"
    echo "4) Exit"
    echo ""
    read -p "Select option [1-4]: " menu_choice
    
    case $menu_choice in
        1) full_installation ;;
        2) step_by_step_installation ;;
        3) remove_installation ;;
        4) exit 0 ;;
        *) show_menu ;;
    esac
}

# Full installation
full_installation() {
    log "${GREEN}Starting full ERPNext/Frappe installation...${NC}"
    log "Log file: $LOG_FILE"

    check_requirements
    prepare_system
    create_frappe_user
    setup_mariadb
    setup_nodejs
    setup_python_redis
    install_frappe_bench
    install_erpnext
    select_additional_apps
    setup_production
    setup_firewall

    show_completion_message
}

# Step by step installation
step_by_step_installation() {
    log "${GREEN}Starting step-by-step installation...${NC}"
    
    if ask_yes_no "Step 1: Prepare system?" "y"; then prepare_system; fi
    if ask_yes_no "Step 2: Create Frappe user?" "y"; then create_frappe_user; fi
    if ask_yes_no "Step 3: Setup MariaDB?" "y"; then setup_mariadb; fi
    if ask_yes_no "Step 4: Setup Node.js?" "y"; then setup_nodejs; fi
    if ask_yes_no "Step 5: Setup Python and Redis?" "y"; then setup_python_redis; fi
    if ask_yes_no "Step 6: Install Frappe Bench?" "y"; then install_frappe_bench; fi
    if ask_yes_no "Step 7: Install ERPNext?" "y"; then install_erpnext; fi
    if ask_yes_no "Step 8: Install additional apps?" "y"; then select_additional_apps; fi
    if ask_yes_no "Step 9: Setup production?" "y"; then setup_production; fi
    if ask_yes_no "Step 10: Setup firewall?" "y"; then setup_firewall; fi
    
    show_completion_message
}

# Show completion message
show_completion_message() {
    local domain=$(cat /tmp/erpnext_domain 2>/dev/null || echo "$DEFAULT_DOMAIN")
    local frappe_user=$(cat /tmp/frappe_username 2>/dev/null || echo "$DEFAULT_FRAPPE_USER")
    local admin_password="admin"

    # Try to get actual admin password
    if [ -f "$ADMIN_CRED_FILE" ]; then
        admin_password=$(grep "admin password" "$ADMIN_CRED_FILE" | awk '{print $NF}' 2>/dev/null || echo "admin")
    fi

    log ""
    log "${GREEN}=========================================="
    log "  Installation Complete!"
    log "==========================================${NC}"
    log ""
    log "${BLUE}Access Information:${NC}"
    log "• ERPNext URL: http://$domain"
    log "• Admin Username: administrator"
    log "• Admin Password: $admin_password"
    log "• MariaDB root password saved in: $MYSQL_CRED_FILE"
    log "• Frappe user: $frappe_user"
    log "• Bench directory: /home/$frappe_user/frappe-bench"
    log ""
    log "${YELLOW}Security recommendations:${NC}"
    log "• Change the default admin password immediately"
    log "• Setup SSL with Let's Encrypt: bench setup add-domain $domain --ssl-certificate"
    log "• Configure Fail2Ban for protection"
    log "• Disable root SSH login"
    log "• Review firewall settings"
    log ""
    log "${BLUE}Useful commands:${NC}"
    log "• Start bench: su - $frappe_user -c 'cd frappe-bench && bench start'"
    log "• Stop bench: su - $frappe_user -c 'cd frappe-bench && bench stop'"
    log "• View logs: tail -f /tmp/erpnext-install.log"
    log ""

    cleanup
}

# Trap cleanup on exit
trap cleanup EXIT

# Start the script
show_menu
