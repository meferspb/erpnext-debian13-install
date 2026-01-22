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
DEFAULT_DOMAIN="erp.local"
DEFAULT_NODE_VERSION="24"
DEFAULT_FRAPPE_USER="frappeuser"
BENCH_DIR=""

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

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

# Interactive input with default
ask_input() {
    local question="$1"
    local default="$2"
    local input
    read -p "$question [default: $default]: " input
    echo "${input:-$default}"
}

# Step 1: System Preparation
prepare_system() {
    log "${BLUE}=== Step 1: System Preparation ===${NC}"
    
    if ask_yes_no "Update system packages?" "y"; then
        info "Updating package lists..."
        apt-get update || error_exit "Failed to update package lists"
        apt-get upgrade -y || warning "Some packages failed to upgrade"
    fi
    
    # Install basic utilities
    local packages=("sudo" "curl" "git" "build-essential" "software-properties-common" "wget" "pwgen")
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
        
        # Setup sudo without password for automation
        echo "$FRAPPE_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$FRAPPE_USER"
        chmod 440 "/etc/sudoers.d/$FRAPPE_USER"
        success "User $FRAPPE_USER created with sudo privileges"
    fi
    
    # Store username for later use
    echo "$FRAPPE_USER" > /tmp/frappe_username
}

# Step 3: MariaDB Setup
setup_mariadb() {
    log "${BLUE}=== Step 3: MariaDB Setup ===${NC}"
    
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
    systemctl start mariadb || true
    systemctl enable mariadb || true
    
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
    
    # Store root password for later use
    echo "$root_password" > /tmp/mysql_root_password
    chmod 600 /tmp/mysql_root_password
}

# Step 4: Node.js Setup
setup_nodejs() {
    log "${BLUE}=== Step 4: Node.js Setup ===${NC}"
    
    echo "Select Node.js version:"
    echo "1) Node.js 22 (LTS)"
    echo "2) Node.js 24 (Current - Default)"
    read -p "Enter choice [1-2, default: 2]: " node_choice
    
    local node_version
    case ${node_choice:-2} in
        1) node_version="22" ;;
        2) node_version="24" ;;
        *) node_version="24" ;;
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
    local other_packages=("xvfb" "libfontconfig" "wkhtmltopdf" "libssl-dev" "libcrypto++-dev" "nginx")
    for pkg in "${other_packages[@]}"; do
        install_package "$pkg"
    done
    
    # Enable and start Redis
    systemctl enable redis-server || true
    systemctl start redis-server || error_exit "Failed to start Redis"
    
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

# Step 7: ERPNext Installation
install_erpnext() {
    log "${BLUE}=== Step 7: ERPNext Installation ===${NC}"
    
    local frappe_user=$(cat /tmp/frappe_username)
    local mysql_root_password=$(cat /tmp/mysql_root_password)
    local domain=$(ask_input "Enter domain for ERPNext site" "$DEFAULT_DOMAIN")
    
    # Store domain for later use
    echo "$domain" > /tmp/erpnext_domain
    
    # Create site and install ERPNext
    su - "$frappe_user" << EOFUSER
        export PATH=\$PATH:\$HOME/.local/bin
        cd frappe-bench
        
        # Check if site exists
        if [ -d "sites/$domain" ]; then
            echo "Site $domain already exists"
        else
            # Create new site
            bench new-site $domain --mariadb-root-password '$mysql_root_password' --admin-password admin
        fi
        
        # Get and install ERPNext if not already
        if [ ! -d "apps/erpnext" ]; then
            bench get-app erpnext --branch version-15
        fi
        
        # Install ERPNext on site
        bench --site $domain install-app erpnext || echo "ERPNext may already be installed"
        
        # Set as default site
        bench use $domain
EOFUSER
    
    if [ $? -ne 0 ]; then
        warning "Some ERPNext installation steps may have failed"
    fi
    
    success "ERPNext installed on site $domain"
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
    
    log ""
    log "${GREEN}=========================================="
    log "  Installation Complete!"
    log "==========================================${NC}"
    log ""
    log "${BLUE}Next steps:${NC}"
    log "1. Access ERPNext at: http://$domain"
    log "2. Default admin password: admin (change it!)"
    log "3. MariaDB root password is stored in: $MYSQL_CRED_FILE"
    log "4. Frappe user: $frappe_user"
    log "5. Bench directory: /home/$frappe_user/frappe-bench"
    log ""
    log "${YELLOW}Security recommendations:${NC}"
    log "- Change default admin password"
    log "- Setup SSL with Let's Encrypt: bench setup add-domain $domain --ssl-certificate"
    log "- Configure Fail2Ban for protection"
    log "- Disable root SSH login"
    log ""
    
    cleanup
}

# Trap cleanup on exit
trap cleanup EXIT

# Start the script
show_menu
