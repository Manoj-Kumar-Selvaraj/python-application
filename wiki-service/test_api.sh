#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Base URL (override with BASE_URL env var)
BASE_URL="${BASE_URL:-http://localhost:8080}"

fail() {
  echo -e "${RED}✗ $*${NC}" >&2
  exit 1
}

require_http() {
  local method="$1"; shift
  local url="$1"; shift
  local expected_code="$1"; shift

  local body_file
  body_file="$(mktemp)"
  local code
  code="$(curl -sS -o "$body_file" -w "%{http_code}" -X "$method" "$url" "$@" || true)"

  if [[ "$code" != "$expected_code" ]]; then
    echo -e "${RED}HTTP $method $url expected $expected_code got $code${NC}" >&2
    echo -e "${RED}Body:${NC}" >&2
    sed -n '1,200p' "$body_file" >&2
    rm -f "$body_file"
    exit 1
  fi

  cat "$body_file"
  rm -f "$body_file"
}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing User and Post API${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${YELLOW}Waiting for API ingress route to be ready...${NC}"
ready=0
for _ in $(seq 1 30); do
  code=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/users" || true)
  if [[ "$code" == "405" || "$code" == "200" ]]; then
    ready=1
    break
  fi
  sleep 2
done

if [[ "$ready" != "1" ]]; then
  fail "API route $BASE_URL/users did not become ready in time"
fi
echo -e "${GREEN}✓ Route ready${NC}\n"

## Test 1: Create first user
echo -e "${YELLOW}Test 1: Creating first user (Alice)...${NC}"
RESPONSE=$(require_http POST "$BASE_URL/users" 200 \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

ALICE_ID=$(echo "$RESPONSE" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)
[[ -n "${ALICE_ID:-}" ]] || fail "Could not parse user id from response"

## Test 2: Create second user
echo -e "${YELLOW}Test 2: Creating second user (Bob)...${NC}"
RESPONSE=$(require_http POST "$BASE_URL/users" 200 \
  -H "Content-Type: application/json" \
  -d '{"name": "Bob"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

BOB_ID=$(echo "$RESPONSE" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)
[[ -n "${BOB_ID:-}" ]] || fail "Could not parse user id from response"

## Test 3: Create third user
echo -e "${YELLOW}Test 3: Creating third user (Charlie)...${NC}"
RESPONSE=$(require_http POST "$BASE_URL/users" 200 \
  -H "Content-Type: application/json" \
  -d '{"name": "Charlie"}')
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

## Test 4: Get user by ID (routed through /users/* ingress)
echo -e "${YELLOW}Test 4: Getting user with ID ${ALICE_ID}...${NC}"
RESPONSE=$(require_http GET "$BASE_URL/users/$ALICE_ID" 200)
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

## Test 5: Get non-existent user (should return 404)
echo -e "${YELLOW}Test 5: Getting non-existent user (ID 999999)...${NC}"
require_http GET "$BASE_URL/users/999999" 404 >/dev/null
echo -e "${GREEN}✓ Got 404 as expected${NC}\n"

## Test 6: Create a post
echo -e "${YELLOW}Test 6: Creating a post (by user ${ALICE_ID})...${NC}"
RESPONSE=$(require_http POST "$BASE_URL/posts" 200 \
  -H "Content-Type: application/json" \
  --data-raw "{\"user_id\": ${ALICE_ID}, \"content\": \"Hello World!\"}")
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

POST_ID=$(echo "$RESPONSE" | sed -n 's/.*"post_id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)
[[ -n "${POST_ID:-}" ]] || fail "Could not parse post_id from response"

## Test 7: Create post with non-existent user (should fail with 404)
echo -e "${YELLOW}Test 7: Creating post with non-existent user (expect 404)...${NC}"
require_http POST "$BASE_URL/posts" 404 \
  -H "Content-Type: application/json" \
  --data-raw '{"user_id": 999999, "content": "This should fail"}' >/dev/null
echo -e "${GREEN}✓ Got 404 as expected${NC}\n"

## Test 8: Get post by ID
echo -e "${YELLOW}Test 8: Getting post with ID ${POST_ID}...${NC}"
RESPONSE=$(require_http GET "$BASE_URL/posts/$POST_ID" 200)
echo -e "${GREEN}Response:${NC} $RESPONSE\n"

## Test 9: Metrics must expose counters
echo -e "${YELLOW}Test 9: Getting Prometheus metrics...${NC}"
METRICS=$(require_http GET "$BASE_URL/metrics" 200)
echo -e "${GREEN}✓ /metrics reachable${NC}"
echo "$METRICS" | grep -q '^users_created_total' || fail "users_created_total missing from /metrics"
echo "$METRICS" | grep -q '^posts_created_total' || fail "posts_created_total missing from /metrics"
echo -e "${GREEN}✓ Metrics counters present${NC}\n"

## Test 10: Grafana is reachable behind /grafana
echo -e "${YELLOW}Test 10: Checking Grafana route...${NC}"
GRAFANA_CODE=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE_URL/grafana/" || true)
if [[ "$GRAFANA_CODE" != "200" && "$GRAFANA_CODE" != "302" ]]; then
  fail "Grafana route expected 200/302, got $GRAFANA_CODE"
fi
echo -e "${GREEN}✓ Grafana route reachable (HTTP $GRAFANA_CODE)${NC}\n"

# Summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ API ingress route OK${NC}"
echo -e "${GREEN}✓ Created users and fetched by /users/{id}${NC}"
echo -e "${GREEN}✓ Created posts and fetched by /posts/{id}${NC}"
echo -e "${GREEN}✓ Verified 404 handling${NC}"
echo -e "${GREEN}✓ Verified /metrics counters present${NC}"
echo -e "${GREEN}✓ Verified /grafana route reachable${NC}"
echo -e "\n${BLUE}All checks passed.${NC}\n"
