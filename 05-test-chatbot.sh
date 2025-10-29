#!/bin/bash
# =============================================================================
# ΓΕΩΤΕΕ CHATBOT - AUTOMATED TESTING
# =============================================================================
# Description: Comprehensive test suite for chatbot functionality
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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SUCCESS="✅"
ERROR="❌"
INFO="ℹ️"
WARN="⚠️"
TEST="🧪"

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
PROJECT_ROOT="/opt/geotee-chatbot"
RASA_URL="http://localhost:5005"
ANALYTICS_URL="http://localhost:8000"

# Load environment if exists
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
fi

# Test results counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

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

test_start() {
    echo -ne "${BLUE}${TEST} Testing: $1...${NC} "
    ((TESTS_TOTAL++))
}

test_pass() {
    echo -e "${GREEN}${SUCCESS} PASSED${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}${ERROR} FAILED${NC}"
    if [ ! -z "$1" ]; then
        echo -e "   ${RED}Reason: $1${NC}"
    fi
    ((TESTS_FAILED++))
}

send_message() {
    local message=$1
    local sender=${2:-"test_user"}
    
    curl -s -X POST "$RASA_URL/webhooks/rest/webhook" \
        -H "Content-Type: application/json" \
        -d "{\"sender\": \"$sender\", \"message\": \"$message\"}"
}

# -----------------------------------------------------------------------------
# START TESTS
# -----------------------------------------------------------------------------
clear

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}${TEST}  ΓΕΩΤΕΕ CHATBOT - AUTOMATED TESTS  ${TEST}${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Timestamp:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# -----------------------------------------------------------------------------
# CONNECTIVITY TESTS
# -----------------------------------------------------------------------------
print_header "🔌 CONNECTIVITY TESTS"

# Test Rasa connection
test_start "Rasa connectivity"
RASA_HEALTH=$(curl -s "$RASA_URL/health" 2>/dev/null)
if echo "$RASA_HEALTH" | grep -q "ok"; then
    test_pass
else
    test_fail "Cannot connect to Rasa"
fi

# Test Analytics API
test_start "Analytics API connectivity"
ANALYTICS_HEALTH=$(curl -s "$ANALYTICS_URL/health" 2>/dev/null)
if echo "$ANALYTICS_HEALTH" | grep -q "healthy"; then
    test_pass
else
    test_fail "Cannot connect to Analytics API"
fi

# Test Redis
test_start "Redis connectivity"
if redis-cli ping > /dev/null 2>&1; then
    test_pass
else
    test_fail "Redis not responding"
fi

# Test Qdrant
test_start "Qdrant connectivity"
QDRANT_STATUS=$(curl -s http://localhost:6333/collections/geotee_kb 2>/dev/null)
if echo "$QDRANT_STATUS" | grep -q "points_count"; then
    test_pass
else
    test_fail "Qdrant not responding"
fi

# -----------------------------------------------------------------------------
# BASIC INTENT TESTS
# -----------------------------------------------------------------------------
print_header "🎯 INTENT RECOGNITION TESTS"

# Test greet intent (Greek)
test_start "Greet intent (Greek)"
RESPONSE=$(send_message "γεια σου")
if echo "$RESPONSE" | grep -iq "γεια"; then
    test_pass
else
    test_fail "No greeting response"
fi

sleep 1

# Test goodbye intent
test_start "Goodbye intent"
RESPONSE=$(send_message "αντίο")
if echo "$RESPONSE" | grep -iq "αντίο\|χαίρομαι"; then
    test_pass
else
    test_fail "No goodbye response"
fi

sleep 1

# Test thank intent
test_start "Thank you intent"
RESPONSE=$(send_message "ευχαριστώ")
if echo "$RESPONSE" | grep -iq "παρακαλώ\|τίποτα"; then
    test_pass
else
    test_fail "No thank you response"
fi

sleep 1

# -----------------------------------------------------------------------------
# FAQ TESTS
# -----------------------------------------------------------------------------
print_header "❓ FAQ TESTS"

# Test working hours
test_start "Working hours FAQ"
RESPONSE=$(send_message "ποιο είναι το ωράριο λειτουργίας")
if echo "$RESPONSE" | grep -iq "ωράριο\|ώρες\|λειτουργί"; then
    test_pass
else
    test_fail "No working hours info"
fi

sleep 1

# Test contact info
test_start "Contact information FAQ"
RESPONSE=$(send_message "πώς μπορώ να επικοινωνήσω")
if echo "$RESPONSE" | grep -iq "επικοινων\|τηλέφωνο\|email"; then
    test_pass
else
    test_fail "No contact info"
fi

sleep 1

# Test membership info
test_start "Membership FAQ"
RESPONSE=$(send_message "πώς γίνομαι μέλος")
if echo "$RESPONSE" | grep -iq "μέλος\|εγγραφ"; then
    test_pass
else
    test_fail "No membership info"
fi

sleep 1

# -----------------------------------------------------------------------------
# KNOWLEDGE BASE SEARCH TESTS
# -----------------------------------------------------------------------------
print_header "🔍 KNOWLEDGE BASE SEARCH TESTS"

# Test general query
test_start "General knowledge query"
RESPONSE=$(send_message "πληροφορίες για το γεωτεχνικό επιμελητήριο")
if echo "$RESPONSE" | grep -iq "γεωτεε\|γεωτεχνικ\|επιμελητήρι"; then
    test_pass
else
    test_fail "No KB results"
fi

sleep 1

# Test technical query
test_start "Technical information query"
RESPONSE=$(send_message "τι είναι το πιστοποιητικό ενεργειακής απόδοσης")
if [ ! -z "$RESPONSE" ] && [ "$RESPONSE" != "[]" ]; then
    test_pass
else
    test_fail "No response to technical query"
fi

sleep 1

# -----------------------------------------------------------------------------
# LANGUAGE RESTRICTION TESTS
# -----------------------------------------------------------------------------
print_header "🇬🇷 LANGUAGE RESTRICTION TESTS"

# Test English rejection
test_start "English language rejection"
RESPONSE=$(send_message "hello" "english_test")
if echo "$RESPONSE" | grep -iq "ελληνικ\|greek"; then
    test_pass
else
    test_fail "English not rejected properly"
fi

sleep 1

# Test another English phrase
test_start "English question rejection"
RESPONSE=$(send_message "what are your working hours" "english_test2")
if echo "$RESPONSE" | grep -iq "ελληνικ\|greek"; then
    test_pass
else
    test_fail "English question not rejected"
fi

sleep 1

# -----------------------------------------------------------------------------
# RATE LIMITING TESTS
# -----------------------------------------------------------------------------
print_header "⏱️ RATE LIMITING TESTS"

test_start "Rate limiting enforcement"

# Send 12 messages rapidly (limit is 10)
RATE_TEST_USER="rate_limit_test_$(date +%s)"
RATE_LIMITED=false

for i in {1..12}; do
    RESPONSE=$(send_message "test $i" "$RATE_TEST_USER")
    sleep 0.5
    
    if [ $i -gt 10 ]; then
        if echo "$RESPONSE" | grep -iq "όριο\|limit"; then
            RATE_LIMITED=true
            break
        fi
    fi
done

if [ "$RATE_LIMITED" = true ]; then
    test_pass
else
    test_fail "Rate limiting not working"
fi

# Clear the test session from Redis
redis-cli DEL "session:$RATE_TEST_USER" > /dev/null 2>&1

sleep 2

# -----------------------------------------------------------------------------
# RESPONSE FORMAT TESTS
# -----------------------------------------------------------------------------
print_header "📝 RESPONSE FORMAT TESTS"

# Test URL inclusion
test_start "URLs in responses"
RESPONSE=$(send_message "πληροφορίες για υπηρεσίες")
if echo "$RESPONSE" | grep -iq "http\|www\|geotee.gr"; then
    test_pass
else
    test_fail "No URLs in response"
fi

sleep 1

# Test response structure
test_start "Response JSON structure"
RESPONSE=$(send_message "γεια σου" "json_test")
if echo "$RESPONSE" | jq -e '.[0].text' > /dev/null 2>&1; then
    test_pass
else
    test_fail "Invalid JSON structure"
fi

sleep 1

# -----------------------------------------------------------------------------
# FALLBACK TESTS
# -----------------------------------------------------------------------------
print_header "🤷 FALLBACK TESTS"

# Test out of scope query
test_start "Out of scope handling"
RESPONSE=$(send_message "ποια είναι η πρωτεύουσα της Γαλλίας")
if echo "$RESPONSE" | grep -iq "δεν μπορώ\|δεν έχω\|συγγνώμη"; then
    test_pass
else
    test_fail "Fallback not triggered"
fi

sleep 1

# Test nonsense input
test_start "Nonsense input handling"
RESPONSE=$(send_message "asdfghjkl")
if [ ! -z "$RESPONSE" ]; then
    test_pass
else
    test_fail "No response to nonsense"
fi

sleep 1

# -----------------------------------------------------------------------------
# ANALYTICS TESTS
# -----------------------------------------------------------------------------
print_header "📊 ANALYTICS TESTS"

# Test stats endpoint
test_start "Analytics stats endpoint"
STATS=$(curl -s "$ANALYTICS_URL/api/stats/today")
if echo "$STATS" | jq -e '.total_queries' > /dev/null 2>&1; then
    test_pass
else
    test_fail "Stats endpoint not working"
fi

# Test health endpoint
test_start "Analytics health endpoint"
HEALTH=$(curl -s "$ANALYTICS_URL/health")
if echo "$HEALTH" | grep -q "healthy"; then
    test_pass
else
    test_fail "Health endpoint not responding"
fi

# -----------------------------------------------------------------------------
# QDRANT VECTOR SEARCH TESTS
# -----------------------------------------------------------------------------
print_header "🗄️ VECTOR DATABASE TESTS"

# Test collection exists
test_start "Qdrant collection exists"
COLLECTION=$(curl -s http://localhost:6333/collections/geotee_kb)
if echo "$COLLECTION" | grep -q "geotee_kb"; then
    test_pass
else
    test_fail "Collection not found"
fi

# Test collection has documents
test_start "Collection has indexed documents"
DOCS_COUNT=$(echo "$COLLECTION" | jq -r '.result.points_count' 2>/dev/null)
if [ "$DOCS_COUNT" -gt 0 ]; then
    test_pass
    echo -e "   ${GREEN}$DOCS_COUNT documents indexed${NC}"
else
    test_fail "No documents in collection"
fi

# -----------------------------------------------------------------------------
# STRESS TEST (OPTIONAL)
# -----------------------------------------------------------------------------
print_header "💪 LIGHT STRESS TEST"

test_start "Rapid sequential requests"
STRESS_USER="stress_test_$(date +%s)"
SUCCESS_COUNT=0

for i in {1..5}; do
    RESPONSE=$(send_message "test $i" "$STRESS_USER")
    if [ ! -z "$RESPONSE" ]; then
        ((SUCCESS_COUNT++))
    fi
    sleep 0.5
done

if [ $SUCCESS_COUNT -eq 5 ]; then
    test_pass
else
    test_fail "Only $SUCCESS_COUNT/5 requests succeeded"
fi

# Clean up
redis-cli DEL "session:$STRESS_USER" > /dev/null 2>&1

# -----------------------------------------------------------------------------
# DOCKER HEALTH TESTS
# -----------------------------------------------------------------------------
print_header "🐳 DOCKER CONTAINER HEALTH"

CONTAINERS=("geotee_postgres" "geotee_redis" "geotee_qdrant" "geotee_rasa" "geotee_rasa_actions" "geotee_analytics" "geotee_nginx")

for container in "${CONTAINERS[@]}"; do
    test_start "$container status"
    if docker ps | grep -q "$container.*Up"; then
        test_pass
    else
        test_fail "Container not running"
    fi
done

# -----------------------------------------------------------------------------
# SSL/DOMAIN TESTS (IF CONFIGURED)
# -----------------------------------------------------------------------------
if [ ! -z "${DOMAIN:-}" ]; then
    print_header "🌐 PUBLIC ENDPOINT TESTS"
    
    # Test HTTPS
    test_start "HTTPS endpoint"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/health" 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" = "200" ]; then
        test_pass
    else
        test_fail "HTTP status: $HTTP_STATUS"
    fi
    
    # Test SSL certificate
    test_start "SSL certificate validity"
    if openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN} < /dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        test_pass
    else
        test_fail "SSL verification failed"
    fi
fi

# -----------------------------------------------------------------------------
# TEST SUMMARY
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}TEST SUMMARY${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

SUCCESS_RATE=$(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED/$TESTS_TOTAL)*100}")

echo -e "${BLUE}Total Tests:${NC} $TESTS_TOTAL"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo -e "${BLUE}Success Rate:${NC} ${SUCCESS_RATE}%"
echo ""

# Overall result
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${SUCCESS} ${GREEN}ALL TESTS PASSED! SYSTEM IS OPERATIONAL${NC} ${SUCCESS}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
elif [ $TESTS_FAILED -lt 3 ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${WARN} ${YELLOW}SOME TESTS FAILED - MINOR ISSUES DETECTED${NC} ${WARN}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${ERROR} ${RED}MULTIPLE TESTS FAILED - CRITICAL ISSUES${NC} ${ERROR}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting steps:${NC}"
    echo -e "  1. Check logs: docker-compose logs -f"
    echo -e "  2. Restart services: docker-compose restart"
    echo -e "  3. Run monitoring: bash 04-monitoring.sh"
    echo -e "  4. Check Docker status: docker ps"
    echo ""
    exit 2
fi
