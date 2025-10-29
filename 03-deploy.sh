#!/bin/bash
# =============================================================================
# ΓΕΩΤΕΕ CHATBOT - FULL DEPLOYMENT SCRIPT
# =============================================================================
# Description: Complete deployment pipeline - scraping, indexing, training, deployment
# Author: GEOTEE DevOps Team
# Version: 1.0
# Last Updated: October 2024
# =============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# -----------------------------------------------------------------------------
# COLORS & FORMATTING
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Emojis
SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
WARN="⚠️"
ROCKET="🚀"
GEAR="⚙️"
DATABASE="🗄️"
SPIDER="🕷️"
ROBOT="🤖"

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
# CONFIGURATION
# -----------------------------------------------------------------------------
PROJECT_ROOT="/opt/geotee-chatbot"
VENV_PATH="${PROJECT_ROOT}/venv"
DATA_DIR="${PROJECT_ROOT}/data"
BACKUP_DIR="${PROJECT_ROOT}/backups"
LOG_DIR="${PROJECT_ROOT}/logs"
DEPLOY_LOG="${LOG_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Check if .env exists
if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    log_error ".env file not found!"
    log_info "Please copy .env.template to .env and configure it:"
    log_info "  cp .env.template .env"
    log_info "  nano .env"
    exit 1
fi

# Load environment variables
source "${PROJECT_ROOT}/.env"

# -----------------------------------------------------------------------------
# PRE-FLIGHT CHECKS
# -----------------------------------------------------------------------------
log_section "${ROCKET} PRE-FLIGHT CHECKS"

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run with sudo"
    exit 1
fi

# Check required directories
for dir in "$DATA_DIR" "$BACKUP_DIR" "$LOG_DIR"; do
    if [ ! -d "$dir" ]; then
        log_warn "Directory $dir does not exist. Creating..."
        mkdir -p "$dir"
    fi
done

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    log_error "Docker is not running!"
    log_info "Start Docker with: systemctl start docker"
    exit 1
fi

# Check if virtual environment exists
if [ ! -d "$VENV_PATH" ]; then
    log_error "Virtual environment not found at $VENV_PATH"
    log_info "Please run 01-project-init.sh first"
    exit 1
fi

log_success "Pre-flight checks passed"

# -----------------------------------------------------------------------------
# ACTIVATE VIRTUAL ENVIRONMENT
# -----------------------------------------------------------------------------
log_section "${GEAR} ACTIVATING VIRTUAL ENVIRONMENT"
source "${VENV_PATH}/bin/activate"
log_success "Virtual environment activated"

# -----------------------------------------------------------------------------
# STEP 1: WEB SCRAPING
# -----------------------------------------------------------------------------
log_section "${SPIDER} STEP 1: WEB SCRAPING"

log_info "Starting web scraper for ${SCRAPER_START_URL}..."
log_info "This may take 10-15 minutes..."

cd "${PROJECT_ROOT}/scraper"

SCRAPED_FILE="${DATA_DIR}/scraped_data_$(date +%Y%m%d).json"

scrapy crawl geotee -o "$SCRAPED_FILE" 2>&1 | tee -a "$DEPLOY_LOG"

if [ -f "$SCRAPED_FILE" ]; then
    SCRAPED_COUNT=$(jq length "$SCRAPED_FILE" 2>/dev/null || echo "0")
    log_success "Scraped $SCRAPED_COUNT pages"
    log_success "Data saved to: $SCRAPED_FILE"
else
    log_error "Scraping failed! File not created."
    exit 1
fi

cd "${PROJECT_ROOT}"

# -----------------------------------------------------------------------------
# STEP 2: VECTOR DATABASE INDEXING
# -----------------------------------------------------------------------------
log_section "${DATABASE} STEP 2: VECTOR DATABASE INDEXING"

log_info "Creating Qdrant collection and indexing documents..."
log_info "Using model: ${EMBEDDINGS_MODEL}"

# Start Qdrant if not running
if ! docker ps | grep -q qdrant; then
    log_info "Starting Qdrant..."
    cd "${PROJECT_ROOT}/deployment/docker"
    docker-compose up -d qdrant
    sleep 10
    cd "${PROJECT_ROOT}"
fi

# Python script for indexing
python3 << 'INDEXING_SCRIPT'
import os
import json
from qdrant_client import QdrantClient
from qdrant_client.http import models
from sentence_transformers import SentenceTransformer
from tqdm import tqdm

print("🔄 Loading embeddings model...")
model = SentenceTransformer(os.getenv('EMBEDDINGS_MODEL', 'paraphrase-multilingual-MiniLM-L12-v2'))

print("🔌 Connecting to Qdrant...")
client = QdrantClient(
    host=os.getenv('QDRANT_HOST', 'localhost'),
    port=int(os.getenv('QDRANT_PORT', 6333))
)

collection_name = os.getenv('QDRANT_COLLECTION_NAME', 'geotee_kb')

# Delete existing collection if exists
try:
    client.delete_collection(collection_name=collection_name)
    print(f"🗑️  Deleted existing collection: {collection_name}")
except:
    pass

# Create new collection
print(f"📦 Creating collection: {collection_name}")
client.create_collection(
    collection_name=collection_name,
    vectors_config=models.VectorParams(
        size=int(os.getenv('QDRANT_VECTOR_SIZE', 384)),
        distance=models.Distance.COSINE
    )
)

# Load scraped data
data_dir = os.getenv('DATA_DIR', '/opt/geotee-chatbot/data')
scraped_files = sorted([f for f in os.listdir(data_dir) if f.startswith('scraped_data_') and f.endswith('.json')])

if not scraped_files:
    print("❌ No scraped data files found!")
    exit(1)

latest_file = os.path.join(data_dir, scraped_files[-1])
print(f"📂 Loading: {latest_file}")

with open(latest_file, 'r', encoding='utf-8') as f:
    documents = json.load(f)

print(f"📊 Found {len(documents)} documents")

# Prepare data for indexing
points = []
for idx, doc in enumerate(tqdm(documents, desc="Creating embeddings")):
    text = f"{doc.get('title', '')} {doc.get('content', '')}"
    
    # Generate embedding
    embedding = model.encode(text).tolist()
    
    # Create point
    point = models.PointStruct(
        id=idx,
        vector=embedding,
        payload={
            "url": doc.get('url', ''),
            "title": doc.get('title', ''),
            "content": doc.get('content', ''),
            "meta_description": doc.get('meta_description', ''),
            "scraped_at": doc.get('scraped_at', '')
        }
    )
    points.append(point)

# Upload to Qdrant
print(f"⬆️  Uploading {len(points)} vectors to Qdrant...")
client.upsert(
    collection_name=collection_name,
    points=points
)

# Verify
collection_info = client.get_collection(collection_name=collection_name)
print(f"✅ Successfully indexed {collection_info.points_count} documents")
print(f"🎯 Collection: {collection_name}")
print(f"📐 Vector size: {collection_info.config.params.vectors.size}")

INDEXING_SCRIPT

if [ $? -eq 0 ]; then
    log_success "Vector database indexing completed"
else
    log_error "Indexing failed!"
    exit 1
fi

# -----------------------------------------------------------------------------
# STEP 3: TRAIN RASA MODEL
# -----------------------------------------------------------------------------
log_section "${ROBOT} STEP 3: TRAINING RASA MODEL"

log_info "Training Rasa NLU model..."
log_info "This may take 5-10 minutes..."

cd "${PROJECT_ROOT}/rasa_bot"

# Validate training data first
log_info "Validating training data..."
rasa data validate 2>&1 | tee -a "$DEPLOY_LOG"

# Train model
log_info "Starting training..."
rasa train --fixed-model-name geotee_model 2>&1 | tee -a "$DEPLOY_LOG"

if [ -f "models/geotee_model.tar.gz" ]; then
    MODEL_SIZE=$(du -h "models/geotee_model.tar.gz" | cut -f1)
    log_success "Model trained successfully (Size: $MODEL_SIZE)"
else
    log_error "Training failed! Model file not created."
    exit 1
fi

cd "${PROJECT_ROOT}"

# -----------------------------------------------------------------------------
# STEP 4: START DOCKER SERVICES
# -----------------------------------------------------------------------------
log_section "${GEAR} STEP 4: STARTING DOCKER SERVICES"

cd "${PROJECT_ROOT}/deployment/docker"

log_info "Stopping existing containers..."
docker-compose down 2>&1 | tee -a "$DEPLOY_LOG"

log_info "Building Docker images..."
docker-compose build --no-cache 2>&1 | tee -a "$DEPLOY_LOG"

log_info "Starting all services..."
docker-compose up -d 2>&1 | tee -a "$DEPLOY_LOG"

# Wait for services to start
log_info "Waiting for services to initialize (30 seconds)..."
sleep 30

# Check if all services are running
log_info "Checking service status..."
docker-compose ps

SERVICES=("postgres" "redis" "qdrant" "rasa" "rasa-actions" "analytics" "nginx")
ALL_RUNNING=true

for service in "${SERVICES[@]}"; do
    if docker-compose ps | grep "$service" | grep -q "Up"; then
        log_success "$service is running"
    else
        log_error "$service is NOT running"
        ALL_RUNNING=false
    fi
done

cd "${PROJECT_ROOT}"

if [ "$ALL_RUNNING" = false ]; then
    log_error "Some services failed to start!"
    log_info "Check logs with: docker-compose logs"
    exit 1
fi

# -----------------------------------------------------------------------------
# STEP 5: HEALTH CHECKS
# -----------------------------------------------------------------------------
log_section "${INFO} STEP 5: HEALTH CHECKS"

# Wait a bit more for services to be fully ready
sleep 10

# Check Rasa
log_info "Checking Rasa..."
RASA_HEALTH=$(curl -s http://localhost:5005/health || echo "failed")
if echo "$RASA_HEALTH" | grep -q "ok"; then
    log_success "Rasa is healthy"
else
    log_warn "Rasa health check failed (may need more time)"
fi

# Check Analytics API
log_info "Checking Analytics API..."
ANALYTICS_HEALTH=$(curl -s http://localhost:8000/health || echo "failed")
if echo "$ANALYTICS_HEALTH" | grep -q "healthy"; then
    log_success "Analytics API is healthy"
else
    log_warn "Analytics health check failed"
fi

# Check Qdrant
log_info "Checking Qdrant..."
QDRANT_HEALTH=$(curl -s http://localhost:6333/collections/geotee_kb | jq -r '.result.points_count' 2>/dev/null || echo "0")
if [ "$QDRANT_HEALTH" -gt 0 ]; then
    log_success "Qdrant has $QDRANT_HEALTH indexed documents"
else
    log_warn "Qdrant collection may be empty"
fi

# Check Nginx (if available publicly)
if [ ! -z "${DOMAIN:-}" ]; then
    log_info "Checking Nginx at https://${DOMAIN}..."
    NGINX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://${DOMAIN}/health || echo "000")
    if [ "$NGINX_STATUS" = "200" ]; then
        log_success "Nginx is accessible at https://${DOMAIN}"
    else
        log_warn "Nginx returned status: $NGINX_STATUS"
    fi
fi

# -----------------------------------------------------------------------------
# STEP 6: CREATE BACKUP
# -----------------------------------------------------------------------------
log_section "${DATABASE} STEP 6: CREATING BACKUP"

BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Backup Rasa model
log_info "Backing up Rasa model..."
cp "${PROJECT_ROOT}/rasa_bot/models/geotee_model.tar.gz" \
   "${BACKUP_DIR}/model_${BACKUP_TIMESTAMP}.tar.gz"

# Backup scraped data
log_info "Backing up scraped data..."
cp "$SCRAPED_FILE" "${BACKUP_DIR}/scraped_${BACKUP_TIMESTAMP}.json"

# Backup PostgreSQL
log_info "Backing up PostgreSQL database..."
docker exec geotee_postgres pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} > \
    "${BACKUP_DIR}/db_${BACKUP_TIMESTAMP}.sql"

log_success "Backups created in: $BACKUP_DIR"

# -----------------------------------------------------------------------------
# DEPLOYMENT SUMMARY
# -----------------------------------------------------------------------------
log_section "${SUCCESS} DEPLOYMENT COMPLETED"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   🎉 DEPLOYMENT SUCCESSFUL! 🎉${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}📊 Deployment Summary:${NC}"
echo -e "  ${GREEN}✓${NC} Scraped pages: $SCRAPED_COUNT"
echo -e "  ${GREEN}✓${NC} Indexed documents: $QDRANT_HEALTH"
echo -e "  ${GREEN}✓${NC} Rasa model: geotee_model.tar.gz ($MODEL_SIZE)"
echo -e "  ${GREEN}✓${NC} Docker services: All running"
echo -e "  ${GREEN}✓${NC} Backups created: ${BACKUP_TIMESTAMP}"
echo ""
echo -e "${BLUE}🌐 Access Points:${NC}"
echo -e "  ${GREEN}•${NC} Chatbot: https://${DOMAIN}"
echo -e "  ${GREEN}•${NC} Analytics: https://${DOMAIN}/analytics"
echo -e "  ${GREEN}•${NC} API Docs: https://${DOMAIN}/api/docs"
echo -e "  ${GREEN}•${NC} Health: https://${DOMAIN}/health"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo -e "  1. Test the chatbot: bash 05-test-chatbot.sh"
echo -e "  2. Monitor services: bash 04-monitoring.sh"
echo -e "  3. View logs: docker-compose logs -f"
echo -e "  4. Integrate widget: See INTEGRATION_SNIPPET.html"
echo ""
echo -e "${BLUE}📄 Logs saved to:${NC} $DEPLOY_LOG"
echo ""
echo -e "${GREEN}========================================${NC}"

# Deactivate virtual environment
deactivate

exit 0
