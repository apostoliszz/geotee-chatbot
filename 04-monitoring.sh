#!/bin/bash
# =============================================================================
# ΓΕΩΤΕΕ CHATBOT - MONITORING & HEALTH CHECK
# =============================================================================
# Description: Monitor all services and display system health
# Author: GEOTEE DevOps Team
# Version: 1.0
# Last Updated: October 2024
# =============================================================================

# -----------------------------------------------------------------------------
# COLORS & FORMATTING
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
WARN="⚠️"
HEART="❤️"
ROCKET="🚀"

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
PROJECT_ROOT="/opt/geotee-chatbot"

# Check if .env exists
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
fi

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}$1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_service_status() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}${SUCCESS} $service${NC} is ${GREEN}running${NC}"
        return 0
    else
        echo -e "${RED}${ERROR} $service${NC} is ${RED}stopped${NC}"
        return 1
    fi
}

check_docker_container() {
    local container=$1
    local status=$(docker ps --filter "name=$container" --format "{{.Status}}" 2>/dev/null)
    
    if [ -z "$status" ]; then
        echo -e "${RED}${ERROR} $container${NC} is ${RED}not running${NC}"
        return 1
    elif echo "$status" | grep -q "Up"; then
        echo -e "${GREEN}${SUCCESS} $container${NC} is ${GREEN}running${NC} ($status)"
        return 0
    else
        echo -e "${YELLOW}${WARN} $container${NC} status: ${YELLOW}$status${NC}"
        return 1
    fi
}

check_url() {
    local url=$1
    local name=$2
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    
    if [ "$response" = "200" ]; then
        echo -e "${GREEN}${SUCCESS} $name${NC} - ${GREEN}HTTP $response${NC}"
        return 0
    else
        echo -e "${RED}${ERROR} $name${NC} - ${RED}HTTP $response${NC}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# MAIN MONITORING
# -----------------------------------------------------------------------------
clear

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}${HEART}  ΓΕΩΤΕΕ CHATBOT - SYSTEM HEALTH MONITOR  ${HEART}${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Timestamp:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}Hostname:${NC} $(hostname)"
echo ""

# -----------------------------------------------------------------------------
# SYSTEM SERVICES
# -----------------------------------------------------------------------------
print_header "🔧 SYSTEM SERVICES"

check_service_status docker
check_service_status redis
check_service_status postgresql-15
check_service_status nginx

# -----------------------------------------------------------------------------
# DOCKER CONTAINERS
# -----------------------------------------------------------------------------
print_header "🐳 DOCKER CONTAINERS"

CONTAINERS=("geotee_postgres" "geotee_redis" "geotee_qdrant" "geotee_rasa" "geotee_rasa_actions" "geotee_analytics" "geotee_nginx")

RUNNING=0
STOPPED=0

for container in "${CONTAINERS[@]}"; do
    if check_docker_container "$container"; then
        ((RUNNING++))
    else
        ((STOPPED++))
    fi
done

echo ""
echo -e "${BLUE}Summary:${NC} ${GREEN}$RUNNING running${NC}, ${RED}$STOPPED stopped${NC}"

# -----------------------------------------------------------------------------
# HEALTH ENDPOINTS
# -----------------------------------------------------------------------------
print_header "🏥 HEALTH ENDPOINTS"

# Rasa
echo -n "Checking Rasa... "
RASA_HEALTH=$(curl -s http://localhost:5005/health 2>/dev/null)
if echo "$RASA_HEALTH" | grep -q "ok"; then
    echo -e "${GREEN}${SUCCESS} Healthy${NC}"
else
    echo -e "${RED}${ERROR} Unhealthy${NC}"
fi

# Analytics
echo -n "Checking Analytics API... "
ANALYTICS_HEALTH=$(curl -s http://localhost:8000/health 2>/dev/null)
if echo "$ANALYTICS_HEALTH" | grep -q "healthy"; then
    echo -e "${GREEN}${SUCCESS} Healthy${NC}"
else
    echo -e "${RED}${ERROR} Unhealthy${NC}"
fi

# Qdrant
echo -n "Checking Qdrant... "
QDRANT_HEALTH=$(curl -s http://localhost:6333/collections/geotee_kb 2>/dev/null | jq -r '.result.points_count' 2>/dev/null || echo "0")
if [ "$QDRANT_HEALTH" -gt 0 ]; then
    echo -e "${GREEN}${SUCCESS} ${QDRANT_HEALTH} documents indexed${NC}"
else
    echo -e "${RED}${ERROR} No documents or connection failed${NC}"
fi

# Public endpoints (if domain is configured)
if [ ! -z "${DOMAIN:-}" ]; then
    echo ""
    echo -e "${BLUE}Public Endpoints:${NC}"
    check_url "https://${DOMAIN}/health" "Main Site"
    check_url "https://${DOMAIN}/api/docs" "API Docs"
fi

# -----------------------------------------------------------------------------
# DATABASE STATUS
# -----------------------------------------------------------------------------
print_header "🗄️ DATABASE STATUS"

# PostgreSQL
echo -e "${BLUE}PostgreSQL:${NC}"
PG_SIZE=$(docker exec geotee_postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -t -c "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB}'));" 2>/dev/null | xargs)
PG_CONNECTIONS=$(docker exec geotee_postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs)
echo -e "  Database Size: ${GREEN}$PG_SIZE${NC}"
echo -e "  Active Connections: ${GREEN}$PG_CONNECTIONS${NC}"

# Redis
echo ""
echo -e "${BLUE}Redis:${NC}"
REDIS_MEMORY=$(redis-cli INFO memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r\n')
REDIS_KEYS=$(redis-cli DBSIZE 2>/dev/null | cut -d: -f2 | xargs)
echo -e "  Memory Used: ${GREEN}$REDIS_MEMORY${NC}"
echo -e "  Total Keys: ${GREEN}$REDIS_KEYS${NC}"

# Qdrant
echo ""
echo -e "${BLUE}Qdrant:${NC}"
QDRANT_COLLECTIONS=$(curl -s http://localhost:6333/collections 2>/dev/null | jq -r '.result.collections | length' 2>/dev/null || echo "0")
echo -e "  Collections: ${GREEN}$QDRANT_COLLECTIONS${NC}"
echo -e "  Documents: ${GREEN}$QDRANT_HEALTH${NC}"

# -----------------------------------------------------------------------------
# RESOURCE USAGE
# -----------------------------------------------------------------------------
print_header "📊 RESOURCE USAGE"

# CPU
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
echo -e "${BLUE}CPU Usage:${NC} ${GREEN}${CPU_USAGE}%${NC}"

# Memory
MEMORY_INFO=$(free -h | awk '/^Mem:/ {print $3 " / " $2 " (" $3/$2*100 "%)"}')
echo -e "${BLUE}Memory:${NC} ${GREEN}$MEMORY_INFO${NC}"

# Disk
DISK_USAGE=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
echo -e "${BLUE}Disk (root):${NC} ${GREEN}$DISK_USAGE${NC}"

# Docker disk usage
DOCKER_DISK=$(docker system df --format "table {{.Type}}\t{{.Size}}" | tail -n +2)
echo ""
echo -e "${BLUE}Docker Disk Usage:${NC}"
echo "$DOCKER_DISK" | while read line; do
    echo -e "  ${GREEN}$line${NC}"
done

# -----------------------------------------------------------------------------
# DOCKER STATS
# -----------------------------------------------------------------------------
print_header "🐳 CONTAINER RESOURCE USAGE"

docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | \
    grep -E "geotee_|CONTAINER" | \
    while IFS= read -r line; do
        if echo "$line" | grep -q "CONTAINER"; then
            echo -e "${BLUE}$line${NC}"
        else
            echo -e "${GREEN}$line${NC}"
        fi
    done

# -----------------------------------------------------------------------------
# ANALYTICS SUMMARY
# -----------------------------------------------------------------------------
print_header "📈 ANALYTICS SUMMARY (TODAY)"

if [ -f "${PROJECT_ROOT}/.env" ]; then
    TODAY=$(date +%Y-%m-%d)
    
    # Total queries today
    TOTAL_QUERIES=$(redis-cli HGET "analytics:daily:$TODAY" total_queries 2>/dev/null || echo "0")
    echo -e "${BLUE}Total Queries:${NC} ${GREEN}$TOTAL_QUERIES${NC}"
    
    # Unique users today
    UNIQUE_USERS=$(redis-cli SCARD "analytics:users:$TODAY" 2>/dev/null || echo "0")
    echo -e "${BLUE}Unique Users:${NC} ${GREEN}$UNIQUE_USERS${NC}"
    
    # Success rate
    SUCCESS_COUNT=$(redis-cli HGET "analytics:daily:$TODAY" successful_responses 2>/dev/null || echo "0")
    if [ "$TOTAL_QUERIES" -gt 0 ]; then
        SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($SUCCESS_COUNT/$TOTAL_QUERIES)*100}")
        echo -e "${BLUE}Success Rate:${NC} ${GREEN}${SUCCESS_RATE}%${NC}"
    else
        echo -e "${BLUE}Success Rate:${NC} ${GREEN}N/A${NC}"
    fi
    
    # Average response time
    AVG_RESPONSE=$(redis-cli HGET "analytics:daily:$TODAY" avg_response_time 2>/dev/null || echo "0")
    echo -e "${BLUE}Avg Response Time:${NC} ${GREEN}${AVG_RESPONSE}ms${NC}"
fi

# -----------------------------------------------------------------------------
# RECENT LOGS
# -----------------------------------------------------------------------------
print_header "📝 RECENT ERRORS (LAST 10)"

echo -e "${BLUE}Rasa Errors:${NC}"
docker logs geotee_rasa 2>&1 | grep -i error | tail -5 | while read line; do
    echo -e "  ${YELLOW}$line${NC}"
done

echo ""
echo -e "${BLUE}Analytics Errors:${NC}"
docker logs geotee_analytics 2>&1 | grep -i error | tail -5 | while read line; do
    echo -e "  ${YELLOW}$line${NC}"
done

# -----------------------------------------------------------------------------
# BACKUP STATUS
# -----------------------------------------------------------------------------
print_header "💾 BACKUP STATUS"

if [ -d "${PROJECT_ROOT}/backups" ]; then
    LAST_BACKUP=$(ls -t ${PROJECT_ROOT}/backups/db_*.sql 2>/dev/null | head -1)
    if [ ! -z "$LAST_BACKUP" ]; then
        BACKUP_AGE=$(stat -c %y "$LAST_BACKUP" | cut -d' ' -f1)
        BACKUP_SIZE=$(du -h "$LAST_BACKUP" | cut -f1)
        echo -e "${BLUE}Last Backup:${NC} ${GREEN}$BACKUP_AGE${NC} (Size: ${GREEN}$BACKUP_SIZE${NC})"
    else
        echo -e "${YELLOW}${WARN} No backups found${NC}"
    fi
    
    BACKUP_COUNT=$(ls ${PROJECT_ROOT}/backups/db_*.sql 2>/dev/null | wc -l)
    echo -e "${BLUE}Total Backups:${NC} ${GREEN}$BACKUP_COUNT${NC}"
else
    echo -e "${RED}${ERROR} Backup directory not found${NC}"
fi

# -----------------------------------------------------------------------------
# SSL CERTIFICATE
# -----------------------------------------------------------------------------
if [ ! -z "${DOMAIN:-}" ]; then
    print_header "🔐 SSL CERTIFICATE"
    
    if [ -f "/etc/letsencrypt/live/${DOMAIN}/cert.pem" ]; then
        CERT_EXPIRY=$(openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/cert.pem -noout -enddate | cut -d= -f2)
        DAYS_LEFT=$(( ($(date -d "$CERT_EXPIRY" +%s) - $(date +%s)) / 86400 ))
        
        if [ $DAYS_LEFT -lt 30 ]; then
            echo -e "${YELLOW}${WARN} Certificate expires in ${DAYS_LEFT} days${NC}"
            echo -e "${YELLOW}Run: certbot renew${NC}"
        else
            echo -e "${GREEN}${SUCCESS} Certificate valid for ${DAYS_LEFT} days${NC}"
        fi
    else
        echo -e "${YELLOW}${WARN} No SSL certificate found${NC}"
    fi
fi

# -----------------------------------------------------------------------------
# SYSTEM UPTIME
# -----------------------------------------------------------------------------
print_header "⏱️ SYSTEM UPTIME"

echo -e "${BLUE}System:${NC} ${GREEN}$(uptime -p)${NC}"
echo -e "${BLUE}Load Average:${NC} ${GREEN}$(uptime | awk -F'load average:' '{print $2}')${NC}"

# Docker uptime
DOCKER_UPTIME=$(systemctl show --property=ActiveEnterTimestamp docker | cut -d= -f2)
if [ ! -z "$DOCKER_UPTIME" ]; then
    DOCKER_AGE=$(( ($(date +%s) - $(date -d "$DOCKER_UPTIME" +%s)) / 3600 ))
    echo -e "${BLUE}Docker:${NC} ${GREEN}${DOCKER_AGE} hours${NC}"
fi

# -----------------------------------------------------------------------------
# QUICK ACTIONS
# -----------------------------------------------------------------------------
print_header "⚡ QUICK ACTIONS"

echo -e "${BLUE}View live logs:${NC}"
echo -e "  docker-compose -f ${PROJECT_ROOT}/deployment/docker/docker-compose.yml logs -f"
echo ""
echo -e "${BLUE}Restart all services:${NC}"
echo -e "  cd ${PROJECT_ROOT}/deployment/docker && docker-compose restart"
echo ""
echo -e "${BLUE}Run tests:${NC}"
echo -e "  bash ${PROJECT_ROOT}/05-test-chatbot.sh"
echo ""
echo -e "${BLUE}Manual backup:${NC}"
echo -e "  bash ${PROJECT_ROOT}/backup.sh"
echo ""

# -----------------------------------------------------------------------------
# OVERALL STATUS
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"

TOTAL_SERVICES=7
HEALTHY_SERVICES=$RUNNING

if [ $HEALTHY_SERVICES -eq $TOTAL_SERVICES ]; then
    echo -e "${CYAN}║${NC}  ${GREEN}${SUCCESS} SYSTEM STATUS: ALL SYSTEMS OPERATIONAL ${SUCCESS}${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}$HEALTHY_SERVICES/$TOTAL_SERVICES services running${NC}"
elif [ $HEALTHY_SERVICES -gt $((TOTAL_SERVICES / 2)) ]; then
    echo -e "${CYAN}║${NC}  ${YELLOW}${WARN} SYSTEM STATUS: PARTIAL OPERATION ${WARN}${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}$HEALTHY_SERVICES/$TOTAL_SERVICES services running${NC}"
else
    echo -e "${CYAN}║${NC}  ${RED}${ERROR} SYSTEM STATUS: CRITICAL ${ERROR}${NC}"
    echo -e "${CYAN}║${NC}  ${RED}$HEALTHY_SERVICES/$TOTAL_SERVICES services running${NC}"
fi

echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Exit with appropriate code
if [ $HEALTHY_SERVICES -eq $TOTAL_SERVICES ]; then
    exit 0
else
    exit 1
fi
