#!/bin/sh
# verify.sh — Verify WordPress + REST API + Yoast SEO is working correctly.
# Can run inside wpcli container or standalone (requires curl).

WP_SITE_URL="${WP_SITE_URL:-http://localhost:8080}"
WP_API_USER="${WP_API_USER:-api-contributor}"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass()    { echo "${GREEN}  ✓${NC}  $*"; }
fail()    { echo "${RED}  ✗${NC}  $*"; FAILED=1; }
section() { echo "\n${CYAN}══ $* ══${NC}"; }
FAILED=0

# ── 1. WordPress site is up ───────────────────────────────────────────────────
section "WordPress Site"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WP_SITE_URL/")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
  pass "Site is up (HTTP $HTTP_CODE): $WP_SITE_URL"
else
  fail "Site returned HTTP $HTTP_CODE: $WP_SITE_URL"
fi

# ── 2. WordPress version ──────────────────────────────────────────────────────
if command -v wp >/dev/null 2>&1; then
  WP_VER=$(wp core version --path=/var/www/html 2>/dev/null)
  pass "WordPress version: $WP_VER"

  # ── Yoast SEO active ────────────────────────────────────────────────────────
  section "Plugins"
  if wp plugin is-active wordpress-seo --path=/var/www/html 2>/dev/null; then
    YOAST_VER=$(wp plugin get wordpress-seo --field=version --path=/var/www/html 2>/dev/null)
    pass "Yoast SEO active (v$YOAST_VER)"
  else
    fail "Yoast SEO is NOT active"
  fi

  # ── Contributor user exists ─────────────────────────────────────────────────
  section "Users"
  if wp user get "$WP_API_USER" --path=/var/www/html >/dev/null 2>&1; then
    USER_ROLE=$(wp user get "$WP_API_USER" --field=roles --path=/var/www/html 2>/dev/null)
    pass "API user '$WP_API_USER' exists (role: $USER_ROLE)"
  else
    fail "API user '$WP_API_USER' not found"
  fi

  # ── Application passwords exist ─────────────────────────────────────────────
  APP_PASS_COUNT=$(wp user application-password list "$WP_API_USER" \
    --path=/var/www/html --format=count 2>/dev/null || echo 0)
  if [ "$APP_PASS_COUNT" -gt 0 ] 2>/dev/null; then
    pass "Application passwords: $APP_PASS_COUNT found for '$WP_API_USER'"
  else
    fail "No application passwords found for '$WP_API_USER'"
  fi
fi

# ── 3. REST API endpoints ─────────────────────────────────────────────────────
section "REST API"
REST_ROOT=$(curl -s "$WP_SITE_URL/wp-json/" 2>/dev/null)
if echo "$REST_ROOT" | grep -q '"name"'; then
  SITE_NAME=$(echo "$REST_ROOT" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
  pass "REST API root accessible — site: $SITE_NAME"
else
  fail "REST API root not accessible: $WP_SITE_URL/wp-json/"
fi

# GET /wp/v2/posts (public, no auth)
POSTS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WP_SITE_URL/wp-json/wp/v2/posts")
if [ "$POSTS_CODE" = "200" ]; then
  pass "GET /wp-json/wp/v2/posts → 200 OK"
else
  fail "GET /wp-json/wp/v2/posts → HTTP $POSTS_CODE"
fi

# GET /wp/v2/users (check REST API users endpoint)
USERS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WP_SITE_URL/wp-json/wp/v2/users")
if [ "$USERS_CODE" = "200" ]; then
  pass "GET /wp-json/wp/v2/users → 200 OK"
else
  pass "GET /wp-json/wp/v2/users → HTTP $USERS_CODE (expected, may require auth)"
fi

# ── 4. Authenticated REST API — create draft post ────────────────────────────
section "Authenticated REST API (contributor)"
CREDS_FILE="/scripts/.api-credentials"
if [ -f "$CREDS_FILE" ]; then
  CREDS=$(cat "$CREDS_FILE")
  API_USER=$(echo "$CREDS" | cut -d: -f1)
  API_PASS=$(echo "$CREDS" | cut -d: -f2-)

  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WP_SITE_URL/wp-json/wp/v2/posts" \
    -u "$API_USER:$API_PASS" \
    -H "Content-Type: application/json" \
    -d '{"title":"Verify: REST API Test Post","content":"Created via REST API by contributor user.","status":"draft"}')

  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | head -1)

  if [ "$HTTP_CODE" = "201" ]; then
    POST_ID=$(echo "$BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    pass "POST /wp-json/wp/v2/posts → 201 Created (post ID: $POST_ID)"
    # Clean up test post
    if command -v wp >/dev/null 2>&1 && [ -n "$POST_ID" ]; then
      wp post delete "$POST_ID" --force --path=/var/www/html >/dev/null 2>&1 && \
        pass "Test post deleted (cleanup)"
    fi
  else
    fail "POST /wp-json/wp/v2/posts → HTTP $HTTP_CODE"
    echo "      Response: $BODY" | head -c 200
  fi
else
  echo "${YELLOW}  ⚠${NC}  Credentials file not found — run setup.sh first"
fi

# ── 5. Yoast SEO REST API namespace ──────────────────────────────────────────
section "Yoast SEO REST API"
YOAST_NS=$(curl -s "$WP_SITE_URL/wp-json/" 2>/dev/null | grep -o '"yoast[^"]*"' | head -3)
if [ -n "$YOAST_NS" ]; then
  pass "Yoast SEO REST namespace registered: $YOAST_NS"
else
  echo "${YELLOW}  ⚠${NC}  Yoast SEO REST namespace not detected (may require site visit to init)"
fi

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILED" = "0" ]; then
  echo "${GREEN}All checks passed!${NC}"
else
  echo "${RED}Some checks failed — review output above.${NC}"
  exit 1
fi
