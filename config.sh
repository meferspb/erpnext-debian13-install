#!/bin/bash

# ERPNext/Frappe Installation Configuration
# This file contains default settings that can be customized

# System Requirements
CONFIG_MIN_RAM_GB=4
CONFIG_MIN_DISK_GB=20

# Default Installation Settings
CONFIG_FRAPPE_VERSION="version-15"
CONFIG_ERPNEXT_VERSION="version-15"
CONFIG_NODE_VERSION="22"
CONFIG_DEFAULT_DOMAIN="erp.local"
CONFIG_DEFAULT_USER="frappe"

# Database Settings
CONFIG_DB_ROOT_PASSWORD_LENGTH=24
CONFIG_DB_SECURE=true

# Security Settings
CONFIG_SUDO_LIMITED=true
CONFIG_FIREWALL_ENABLED=true

# Additional Apps (set to true to install by default in quick mode)
CONFIG_INSTALL_HRMS=false
CONFIG_INSTALL_PAYMENTS=false
CONFIG_INSTALL_WEBSHOP=false
CONFIG_INSTALL_WIKI=false
CONFIG_INSTALL_HELPDESK=false
CONFIG_INSTALL_LMS=false
CONFIG_INSTALL_BUILDER=false
CONFIG_INSTALL_PRINT_DESIGNER=false

# Production Settings
CONFIG_PRODUCTION_MODE=true
CONFIG_SSL_CERTIFICATE=false

# Logging
CONFIG_LOG_LEVEL="INFO"
CONFIG_LOG_TIMESTAMP=true

# Automated Installation (for CI/CD)
# Set these environment variables for automated installation:
# export ERPNEXT_DOMAIN="your-domain.com"
# export ERPNEXT_ADMIN_PASSWORD="your-secure-password"
# export MARIADB_ROOT_PASSWORD="your-db-password"
# export FRAPPE_USER="frappe"
