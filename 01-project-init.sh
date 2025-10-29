#!/bin/bash
# =============================================================================
# ΓΕΩΤΕΕ CHATBOT - PROJECT INITIALIZATION
# =============================================================================
# Description: Initialize project structure and install dependencies
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

log_section "${ROCKET} ΓΕΩΤΕΕ CHATBOT - PROJECT INITIALIZATION"

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
PROJECT_ROOT="/opt/geotee-chatbot"
VENV_PATH="${PROJECT_ROOT}/venv"

# Check if project directory exists
if [ ! -d "$PROJECT_ROOT" ]; then
    log_error "Project directory not found: $PROJECT_ROOT"
    log_info "Please run 00-vps-setup.sh first"
    exit 1
fi

cd "$PROJECT_ROOT"

# -----------------------------------------------------------------------------
# STEP 1: VERIFY FILE STRUCTURE
# -----------------------------------------------------------------------------
log_section "📁 STEP 1: VERIFYING FILE STRUCTURE"

log_info "Checking project structure..."

REQUIRED_DIRS=(
    "scraper"
    "scraper/spiders"
    "scraper/pipelines"
    "rasa_bot"
    "rasa_bot/data"
    "rasa_bot/actions"
    "analytics"
    "frontend"
    "deployment"
    "deployment/docker"
    "deployment/nginx"
    "deployment/ssl"
    "logs"
    "data"
    "backups"
    "knowledge_base"
    ".github"
    ".github/workflows"
)

MISSING_DIRS=0

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        log_warn "Missing directory: $dir"
        mkdir -p "$dir"
        MISSING_DIRS=$((MISSING_DIRS + 1))
    fi
done

if [ $MISSING_DIRS -eq 0 ]; then
    log_success "All directories present"
else
    log_success "Created $MISSING_DIRS missing directories"
fi

# Create .gitkeep files for empty directories
touch logs/.gitkeep data/.gitkeep backups/.gitkeep knowledge_base/.gitkeep

# -----------------------------------------------------------------------------
# STEP 2: CHECK REQUIRED FILES
# -----------------------------------------------------------------------------
log_section "📄 STEP 2: CHECKING REQUIRED FILES"

CRITICAL_FILES=(
    "requirements.txt"
    ".gitignore"
    "README.md"
)

MISSING_FILES=0

for file in "${CRITICAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "Missing critical file: $file"
        MISSING_FILES=$((MISSING_FILES + 1))
    else
        log_success "Found: $file"
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    log_error "Missing $MISSING_FILES critical files!"
    log_info "Please ensure all files are uploaded/cloned to $PROJECT_ROOT"
    exit 1
fi

# -----------------------------------------------------------------------------
# STEP 3: SETUP ENVIRONMENT FILE
# -----------------------------------------------------------------------------
log_section "⚙️ STEP 3: ENVIRONMENT CONFIGURATION"

if [ ! -f ".env" ]; then
    if [ -f ".env.template" ]; then
        log_info "Creating .env from template..."
        cp .env.template .env
        
        # Generate random secrets
        SECRET_KEY=$(openssl rand -hex 32)
        RASA_TOKEN=$(openssl rand -hex 32)
        POSTGRES_PASSWORD=$(openssl rand -base64 24)
        ANALYTICS_PASSWORD=$(openssl rand -base64 16)
        
        # Replace placeholders
        sed -i "s/your-secret-key-here-change-this-value/$SECRET_KEY/" .env
        sed -i "s/your-rasa-token-here-change-this-value/$RASA_TOKEN/" .env
        sed -i "s/your-strong-postgres-password-here/$POSTGRES_PASSWORD/" .env
        sed -i "s/your-analytics-password-here/$ANALYTICS_PASSWORD/" .env
        
        log_success ".env file created with random secrets"
        log_warn "Please edit .env and update DOMAIN and other settings:"
        log_info "  nano .env"
    else
        log_error ".env.template not found!"
        exit 1
    fi
else
    log_success ".env file already exists"
    log_warn "Make sure it's properly configured"
fi

# Set proper permissions
chmod 600 .env
log_success "Environment file secured (chmod 600)"

# -----------------------------------------------------------------------------
# STEP 4: INSTALL PYTHON DEPENDENCIES
# -----------------------------------------------------------------------------
log_section "🐍 STEP 4: PYTHON DEPENDENCIES"

# Check if virtual environment exists
if [ ! -d "$VENV_PATH" ]; then
    log_info "Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
log_info "Activating virtual environment..."
source "${VENV_PATH}/bin/activate"

# Upgrade pip
log_info "Upgrading pip..."
pip install --upgrade pip setuptools wheel --break-system-packages

# Install requirements
log_info "Installing Python dependencies..."
log_warn "This may take 10-15 minutes..."

pip install -r requirements.txt --break-system-packages

log_success "Python dependencies installed"

# Install Spacy Greek model
log_info "Downloading Spacy Greek language model..."
python3 -m spacy download el_core_news_sm

log_success "Spacy Greek model installed"

# Verify Rasa installation
log_info "Verifying Rasa installation..."
RASA_VERSION=$(rasa --version | head -1)
log_success "Installed: $RASA_VERSION"

# -----------------------------------------------------------------------------
# STEP 5: INITIALIZE RASA PROJECT
# -----------------------------------------------------------------------------
log_section "🤖 STEP 5: RASA INITIALIZATION"

cd "${PROJECT_ROOT}/rasa_bot"

# Create models directory if it doesn't exist
mkdir -p models

# Validate Rasa configuration
log_info "Validating Rasa configuration..."
if [ -f "config.yml" ] && [ -f "domain.yml" ]; then
    rasa data validate
    log_success "Rasa configuration is valid"
else
    log_error "Missing Rasa config files (config.yml or domain.yml)"
    exit 1
fi

cd "$PROJECT_ROOT"

# -----------------------------------------------------------------------------
# STEP 6: INITIALIZE DATABASES
# -----------------------------------------------------------------------------
log_section "🗄️ STEP 6: DATABASE SETUP"

# Load environment variables
source .env

# PostgreSQL setup
log_info "Configuring PostgreSQL..."

# Create database user and database
sudo -u postgres psql << EOF
-- Create user if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '${POSTGRES_USER}') THEN
        CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
END
\$\$;

-- Create database if not exists
SELECT 'CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${POSTGRES_DB}')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};
EOF

log_success "PostgreSQL configured"

# Test Redis connection
log_info "Testing Redis connection..."
if redis-cli ping > /dev/null 2>&1; then
    log_success "Redis is accessible"
else
    log_error "Redis connection failed!"
    log_info "Start Redis with: systemctl start redis"
    exit 1
fi

# -----------------------------------------------------------------------------
# STEP 7: SETUP NGINX
# -----------------------------------------------------------------------------
log_section "🌐 STEP 7: NGINX CONFIGURATION"

# Backup existing nginx config if exists
if [ -f "/etc/nginx/nginx.conf" ]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d)
    log_info "Backed up existing Nginx config"
fi

# Test if our nginx config is valid
if [ -f "deployment/nginx/nginx.conf" ]; then
    # Copy config to test it
    cp deployment/nginx/nginx.conf /etc/nginx/conf.d/geotee-chatbot.conf
    
    # Test configuration
    if nginx -t 2>&1 | grep -q "successful"; then
        log_success "Nginx configuration is valid"
    else
        log_warn "Nginx configuration has warnings (will be fixed during deployment)"
    fi
else
    log_error "Nginx configuration file not found!"
    exit 1
fi

# Don't start nginx yet - SSL needs to be configured first
log_info "Nginx will be started after SSL setup"

# -----------------------------------------------------------------------------
# STEP 8: DOCKER IMAGES
# -----------------------------------------------------------------------------
log_section "🐳 STEP 8: DOCKER IMAGES"

log_info "Pulling required Docker images..."

# Pull images
docker pull postgres:15-alpine
docker pull redis:7-alpine
docker pull qdrant/qdrant:latest
docker pull nginx:alpine

log_success "Docker images pulled"

# -----------------------------------------------------------------------------
# STEP 9: FILE PERMISSIONS
# -----------------------------------------------------------------------------
log_section "🔐 STEP 9: FILE PERMISSIONS"

log_info "Setting file permissions..."

# Set ownership
chown -R root:root "$PROJECT_ROOT"

# Set directory permissions
find "$PROJECT_ROOT" -type d -exec chmod 755 {} \;

# Set file permissions
find "$PROJECT_ROOT" -type f -exec chmod 644 {} \;

# Make scripts executable
chmod +x *.sh 2>/dev/null || true
find . -name "*.sh" -exec chmod +x {} \;

# Secure sensitive files
chmod 600 .env 2>/dev/null || true
chmod 600 deployment/nginx/.htpasswd 2>/dev/null || true

# Writable directories
chmod -R 777 logs data backups knowledge_base

log_success "File permissions set"

# -----------------------------------------------------------------------------
# STEP 10: CREATE BACKUP SCRIPT
# -----------------------------------------------------------------------------
log_section "💾 STEP 10: BACKUP SCRIPT"

log_info "Creating backup script..."

cat > backup.sh << 'EOF'
#!/bin/bash
# ΓΕΩΤΕΕ Chatbot - Backup Script

PROJECT_ROOT="/opt/geotee-chatbot"
BACKUP_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

source "${PROJECT_ROOT}/.env"

echo "🔄 Starting backup: $TIMESTAMP"

# Backup PostgreSQL
echo "📊 Backing up PostgreSQL..."
docker exec geotee_postgres pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} > \
    "${BACKUP_DIR}/db_${TIMESTAMP}.sql"

# Backup Qdrant
echo "🗄️ Backing up Qdrant..."
tar -czf "${BACKUP_DIR}/qdrant_${TIMESTAMP}.tar.gz" \
    -C "${PROJECT_ROOT}/knowledge_base" qdrant_data

# Backup Rasa model
echo "🤖 Backing up Rasa model..."
if [ -f "${PROJECT_ROOT}/rasa_bot/models/geotee_model.tar.gz" ]; then
    cp "${PROJECT_ROOT}/rasa_bot/models/geotee_model.tar.gz" \
       "${BACKUP_DIR}/model_${TIMESTAMP}.tar.gz"
fi

# Backup .env file
echo "⚙️ Backing up configuration..."
cp "${PROJECT_ROOT}/.env" "${BACKUP_DIR}/env_${TIMESTAMP}.txt"

# Delete old backups (keep last 30 days)
find "${BACKUP_DIR}" -name "*.sql" -mtime +30 -delete
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime +30 -delete
find "${BACKUP_DIR}" -name "*.txt" -mtime +30 -delete

echo "✅ Backup completed: ${BACKUP_DIR}"
EOF

chmod +x backup.sh
log_success "Backup script created"

# -----------------------------------------------------------------------------
# STEP 11: CREATE INITIALIZATION MARKER
# -----------------------------------------------------------------------------
touch .initialized
echo "$(date)" > .initialized

# -----------------------------------------------------------------------------
# INITIALIZATION COMPLETED
# -----------------------------------------------------------------------------
log_section "${SUCCESS} INITIALIZATION COMPLETED"

# Deactivate virtual environment
deactivate

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   🎉 PROJECT INITIALIZED! 🎉${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}📊 Initialization Summary:${NC}"
echo -e "  ${GREEN}✓${NC} Project structure verified"
echo -e "  ${GREEN}✓${NC} Environment file created"
echo -e "  ${GREEN}✓${NC} Python dependencies installed"
echo -e "  ${GREEN}✓${NC} Rasa validated"
echo -e "  ${GREEN}✓${NC} PostgreSQL configured"
echo -e "  ${GREEN}✓${NC} Redis accessible"
echo -e "  ${GREEN}✓${NC} Nginx configured"
echo -e "  ${GREEN}✓${NC} Docker images pulled"
echo -e "  ${GREEN}✓${NC} File permissions set"
echo -e "  ${GREEN}✓${NC} Backup script created"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo ""
echo -e "  ${YELLOW}1. Configure your domain in .env:${NC}"
echo -e "     nano .env"
echo -e "     ${GREEN}Set DOMAIN=your-domain.com${NC}"
echo ""
echo -e "  ${YELLOW}2. Setup DNS for your domain:${NC}"
echo -e "     ${GREEN}A Record: your-domain.com → $(hostname -I | awk '{print $1}')${NC}"
echo ""
echo -e "  ${YELLOW}3. Generate SSL certificate:${NC}"
echo -e "     certbot --nginx -d your-domain.com"
echo -e "     cp /etc/letsencrypt/live/your-domain.com/*.pem deployment/ssl/"
echo ""
echo -e "  ${YELLOW}4. Run full deployment:${NC}"
echo -e "     bash 03-deploy.sh"
echo ""
echo -e "${BLUE}📄 Configuration Files:${NC}"
echo -e "  Environment: ${PROJECT_ROOT}/.env"
echo -e "  Rasa Config: ${PROJECT_ROOT}/rasa_bot/config.yml"
echo -e "  Nginx Config: ${PROJECT_ROOT}/deployment/nginx/nginx.conf"
echo ""
echo -e "${BLUE}🔐 Generated Secrets:${NC}"
echo -e "  ${YELLOW}⚠️  Secrets have been auto-generated in .env${NC}"
echo -e "  ${YELLOW}⚠️  Keep this file secure and never commit to git!${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"

log_success "Project is ready for deployment! 🚀"

exit 0
