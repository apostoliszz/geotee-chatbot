#!/bin/bash
# =============================================================================
# ΓΕΩΤΕΕ CHATBOT - VPS INITIAL SETUP
# =============================================================================
# Description: Initial server setup for AlmaLinux/Rocky Linux/CentOS
# Author: GEOTEE DevOps Team
# Version: 1.0
# Last Updated: October 2024
# =============================================================================

set -e  # Exit on error

# -----------------------------------------------------------------------------
# COLORS & FORMATTING
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
WARN="⚠️"
ROCKET="🚀"

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}${INFO} [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}${SUCCESS} [SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}${WARN} [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}${ERROR} [ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# CHECK ROOT ACCESS
# -----------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root or with sudo"
    exit 1
fi

log_section "${ROCKET} ΓΕΩΤΕΕ CHATBOT - VPS SETUP"

log_info "Starting VPS setup for AlmaLinux/Rocky Linux..."
log_info "This will take approximately 15-20 minutes"
echo ""

# -----------------------------------------------------------------------------
# SYSTEM UPDATE
# -----------------------------------------------------------------------------
log_section "📦 STEP 1: SYSTEM UPDATE"

log_info "Updating system packages..."
dnf update -y
dnf upgrade -y

log_success "System updated"

# -----------------------------------------------------------------------------
# INSTALL ESSENTIAL TOOLS
# -----------------------------------------------------------------------------
log_section "🔧 STEP 2: ESSENTIAL TOOLS"

log_info "Installing essential development tools..."

dnf install -y epel-release
dnf groupinstall -y "Development Tools"
dnf install -y \
    wget \
    curl \
    vim \
    nano \
    git \
    htop \
    jq \
    unzip \
    tar \
    bzip2 \
    tree \
    net-tools \
    bind-utils \
    openssl \
    ca-certificates

log_success "Essential tools installed"

# -----------------------------------------------------------------------------
# INSTALL PYTHON 3.11
# -----------------------------------------------------------------------------
log_section "🐍 STEP 3: PYTHON 3.11"

log_info "Installing Python 3.11..."

dnf install -y python3.11 python3.11-devel python3.11-pip
alternatives --set python3 /usr/bin/python3.11

# Verify Python version
PYTHON_VERSION=$(python3 --version)
log_success "Installed: $PYTHON_VERSION"

# Upgrade pip
python3 -m pip install --upgrade pip

log_success "Python 3.11 configured"

# -----------------------------------------------------------------------------
# INSTALL DOCKER
# -----------------------------------------------------------------------------
log_section "🐳 STEP 4: DOCKER & DOCKER COMPOSE"

log_info "Installing Docker..."

# Remove old versions if any
dnf remove -y docker docker-common docker-selinux docker-engine-selinux docker-engine

# Install Docker
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Verify Docker
DOCKER_VERSION=$(docker --version)
log_success "Installed: $DOCKER_VERSION"

# Install Docker Compose standalone (v2)
DOCKER_COMPOSE_VERSION="v2.23.0"
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

COMPOSE_VERSION=$(docker-compose --version)
log_success "Installed: $COMPOSE_VERSION"

# -----------------------------------------------------------------------------
# INSTALL NGINX
# -----------------------------------------------------------------------------
log_section "🌐 STEP 5: NGINX"

log_info "Installing Nginx..."

dnf install -y nginx

systemctl enable nginx
# Don't start yet - will be configured later

log_success "Nginx installed"

# -----------------------------------------------------------------------------
# INSTALL REDIS
# -----------------------------------------------------------------------------
log_section "💾 STEP 6: REDIS"

log_info "Installing Redis..."

dnf install -y redis

systemctl start redis
systemctl enable redis

# Test Redis
redis-cli ping > /dev/null 2>&1
log_success "Redis installed and running"

# -----------------------------------------------------------------------------
# INSTALL POSTGRESQL
# -----------------------------------------------------------------------------
log_section "🐘 STEP 7: POSTGRESQL 15"

log_info "Installing PostgreSQL 15..."

# Add PostgreSQL repository
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Disable built-in PostgreSQL module
dnf -qy module disable postgresql

# Install PostgreSQL 15
dnf install -y postgresql15-server postgresql15-contrib

# Initialize database
/usr/pgsql-15/bin/postgresql-15-setup initdb

# Start and enable
systemctl start postgresql-15
systemctl enable postgresql-15

log_success "PostgreSQL 15 installed"

# -----------------------------------------------------------------------------
# FIREWALL CONFIGURATION
# -----------------------------------------------------------------------------
log_section "🔥 STEP 8: FIREWALL"

log_info "Configuring firewall..."

# Enable firewalld
systemctl start firewalld
systemctl enable firewalld

# Allow HTTP and HTTPS
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https

# Allow SSH (if not already)
firewall-cmd --permanent --add-service=ssh

# Reload firewall
firewall-cmd --reload

log_success "Firewall configured"

# -----------------------------------------------------------------------------
# SSL CERTIFICATE (CERTBOT)
# -----------------------------------------------------------------------------
log_section "🔐 STEP 9: SSL CERTIFICATE"

log_info "Installing Certbot for Let's Encrypt..."

dnf install -y certbot python3-certbot-nginx

log_success "Certbot installed"
log_warn "SSL certificate generation will be done after DNS is configured"
log_info "Run this command after DNS setup:"
echo ""
echo "  certbot --nginx -d your-domain.com"
echo ""

# -----------------------------------------------------------------------------
# CREATE PROJECT DIRECTORY
# -----------------------------------------------------------------------------
log_section "📁 STEP 10: PROJECT STRUCTURE"

log_info "Creating project directory..."

PROJECT_DIR="/opt/geotee-chatbot"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Create subdirectories
mkdir -p logs data backups knowledge_base deployment/ssl

log_success "Project directory created: $PROJECT_DIR"

# -----------------------------------------------------------------------------
# CREATE VIRTUAL ENVIRONMENT
# -----------------------------------------------------------------------------
log_section "🐍 STEP 11: PYTHON VIRTUAL ENVIRONMENT"

log_info "Creating Python virtual environment..."

cd "$PROJECT_DIR"
python3 -m venv venv

log_success "Virtual environment created"

# Activate and upgrade pip
source venv/bin/activate
pip install --upgrade pip
deactivate

log_success "Virtual environment ready"

# -----------------------------------------------------------------------------
# INSTALL SYSTEM DEPENDENCIES FOR RASA
# -----------------------------------------------------------------------------
log_section "📚 STEP 12: RASA DEPENDENCIES"

log_info "Installing system dependencies for Rasa..."

dnf install -y \
    gcc \
    gcc-c++ \
    make \
    cmake \
    libffi-devel \
    openssl-devel \
    bzip2-devel \
    readline-devel \
    sqlite-devel \
    libicu-devel

log_success "Rasa dependencies installed"

# -----------------------------------------------------------------------------
# INSTALL SPACY LANGUAGE MODEL
# -----------------------------------------------------------------------------
log_section "🇬🇷 STEP 13: SPACY GREEK MODEL"

log_info "Installing Spacy Greek language model..."

source "$PROJECT_DIR/venv/bin/activate"
pip install spacy --break-system-packages
python3 -m spacy download el_core_news_sm
deactivate

log_success "Greek language model installed"

# -----------------------------------------------------------------------------
# SETUP SWAP (IF NEEDED)
# -----------------------------------------------------------------------------
log_section "💿 STEP 14: SWAP SPACE"

SWAP_SIZE=$(free -m | awk '/^Swap:/ {print $2}')

if [ "$SWAP_SIZE" -lt 2048 ]; then
    log_warn "Low swap space detected (${SWAP_SIZE}MB)"
    log_info "Creating 4GB swap file..."
    
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Make it permanent
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    
    log_success "Swap space increased to 4GB"
else
    log_success "Swap space is adequate (${SWAP_SIZE}MB)"
fi

# -----------------------------------------------------------------------------
# OPTIMIZE SYSTEM SETTINGS
# -----------------------------------------------------------------------------
log_section "⚙️ STEP 15: SYSTEM OPTIMIZATION"

log_info "Optimizing system settings..."

# Increase file descriptors
cat >> /etc/security/limits.conf << EOF
* soft nofile 65536
* hard nofile 65536
EOF

# Optimize sysctl
cat >> /etc/sysctl.conf << EOF

# Networking optimizations
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.ip_local_port_range = 10000 65535

# Memory optimizations
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

sysctl -p > /dev/null 2>&1

log_success "System optimized"

# -----------------------------------------------------------------------------
# SETUP CRON FOR BACKUPS
# -----------------------------------------------------------------------------
log_section "⏰ STEP 16: AUTOMATED BACKUPS"

log_info "Setting up automated backups..."

CRON_FILE="/etc/cron.d/geotee-backup"

cat > "$CRON_FILE" << 'EOF'
# ΓΕΩΤΕΕ Chatbot - Automated Daily Backup
# Runs every day at 02:00 AM

0 2 * * * root /opt/geotee-chatbot/backup.sh >> /opt/geotee-chatbot/logs/backup.log 2>&1
EOF

chmod 644 "$CRON_FILE"

log_success "Automated backups configured (daily at 02:00)"

# -----------------------------------------------------------------------------
# INSTALL MONITORING TOOLS
# -----------------------------------------------------------------------------
log_section "📊 STEP 17: MONITORING TOOLS"

log_info "Installing monitoring tools..."

dnf install -y \
    sysstat \
    iotop \
    iftop \
    nethogs

# Enable sysstat
systemctl enable sysstat
systemctl start sysstat

log_success "Monitoring tools installed"

# -----------------------------------------------------------------------------
# SETUP LOG ROTATION
# -----------------------------------------------------------------------------
log_section "📝 STEP 18: LOG ROTATION"

log_info "Configuring log rotation..."

cat > /etc/logrotate.d/geotee-chatbot << 'EOF'
/opt/geotee-chatbot/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload docker > /dev/null 2>&1 || true
    endscript
}
EOF

log_success "Log rotation configured"

# -----------------------------------------------------------------------------
# CLONE REPOSITORY (OPTIONAL)
# -----------------------------------------------------------------------------
log_section "📦 STEP 19: PROJECT FILES"

log_info "You can now:"
echo ""
echo "  1. Clone from GitHub:"
echo "     cd /opt/geotee-chatbot"
echo "     git clone https://github.com/YOUR_ORG/geotee-chatbot.git ."
echo ""
echo "  2. Or upload files manually via SFTP/SCP"
echo ""

# -----------------------------------------------------------------------------
# SETUP COMPLETED
# -----------------------------------------------------------------------------
log_section "${SUCCESS} VPS SETUP COMPLETED"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   🎉 VPS SETUP SUCCESSFUL! 🎉${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}📊 Installation Summary:${NC}"
echo -e "  ${GREEN}✓${NC} System updated and optimized"
echo -e "  ${GREEN}✓${NC} Python 3.11 installed"
echo -e "  ${GREEN}✓${NC} Docker & Docker Compose installed"
echo -e "  ${GREEN}✓${NC} Nginx installed"
echo -e "  ${GREEN}✓${NC} Redis installed and running"
echo -e "  ${GREEN}✓${NC} PostgreSQL 15 installed"
echo -e "  ${GREEN}✓${NC} Certbot (Let's Encrypt) ready"
echo -e "  ${GREEN}✓${NC} Firewall configured"
echo -e "  ${GREEN}✓${NC} Project directory created: /opt/geotee-chatbot"
echo -e "  ${GREEN}✓${NC} Virtual environment ready"
echo -e "  ${GREEN}✓${NC} Greek language model installed"
echo -e "  ${GREEN}✓${NC} Automated backups scheduled"
echo -e "  ${GREEN}✓${NC} Monitoring tools installed"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo -e "  1. Upload/clone your project files to /opt/geotee-chatbot"
echo -e "  2. Configure DNS for your domain"
echo -e "  3. Run: bash 01-project-init.sh"
echo -e "  4. Configure .env file"
echo -e "  5. Run: bash 03-deploy.sh"
echo ""
echo -e "${YELLOW}⚠️  Important:${NC}"
echo -e "  • Change SSH port for security"
echo -e "  • Setup SSH key authentication"
echo -e "  • Disable root SSH login"
echo -e "  • Configure fail2ban (optional)"
echo ""
echo -e "${BLUE}🔐 SSL Certificate Setup:${NC}"
echo -e "  After DNS is configured, run:"
echo -e "  ${GREEN}certbot --nginx -d your-domain.com${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"

# -----------------------------------------------------------------------------
# SYSTEM INFO
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}📊 System Information:${NC}"
echo -e "  Hostname: $(hostname)"
echo -e "  OS: $(cat /etc/redhat-release)"
echo -e "  Kernel: $(uname -r)"
echo -e "  CPU: $(nproc) cores"
echo -e "  RAM: $(free -h | awk '/^Mem:/ {print $2}')"
echo -e "  Disk: $(df -h / | awk 'NR==2 {print $4}') available"
echo -e "  IP: $(hostname -I | awk '{print $1}')"
echo ""

log_success "VPS is ready for ΓΕΩΤΕΕ Chatbot deployment! 🚀"

exit 0
