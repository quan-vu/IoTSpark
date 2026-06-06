#!/bin/sh
# setup.sh — Automated WordPress setup via WP-CLI
# Runs inside the wpcli container (profile: setup)

set -e

# Load env vars from .env if not already set (fallback)
WP_SITE_URL="${WP_SITE_URL:-http://localhost:8080}"
WP_SITE_TITLE="${WP_SITE_TITLE:-IoTSpark}"
WP_ADMIN_USER="${WP_ADMIN_USER:-admin}"
WP_ADMIN_PASSWORD="${WP_ADMIN_PASSWORD:-admin@IoTSpark2025}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:-admin@iotspark.local}"
WP_API_USER="${WP_API_USER:-api-contributor}"
WP_API_PASSWORD="${WP_API_PASSWORD:-Contributor@2025}"
WP_API_EMAIL="${WP_API_EMAIL:-contributor@iotspark.local}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo "${GREEN}[INFO]${NC}  $*"; }
section() { echo "${CYAN}══ $* ══${NC}"; }

# ── 1. Wait for WordPress files to be ready ───────────────────────────────────
section "Waiting for WordPress"
for i in $(seq 1 30); do
  [ -f /var/www/html/wp-config.php ] && break
  echo "  Waiting for wp-config.php... ($i/30)"
  sleep 3
done
[ -f /var/www/html/wp-config.php ] || { echo "wp-config.php not found"; exit 1; }

# ── 2. Install WordPress core ─────────────────────────────────────────────────
section "WordPress Core"
if wp core is-installed --path=/var/www/html 2>/dev/null; then
  info "Already installed — skipping core install"
else
  wp core install \
    --path=/var/www/html \
    --url="$WP_SITE_URL" \
    --title="$WP_SITE_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASSWORD" \
    --admin_email="$WP_ADMIN_EMAIL" \
    --skip-email
  info "WordPress installed: $WP_SITE_URL"
fi

# ── 3. Install & activate Yoast SEO ──────────────────────────────────────────
section "Yoast SEO Plugin"
if wp plugin is-active wordpress-seo --path=/var/www/html 2>/dev/null; then
  info "Yoast SEO already active"
else
  wp plugin install wordpress-seo --activate --path=/var/www/html
  info "Yoast SEO installed and activated"
fi

# ── 4. Verify REST API is enabled ────────────────────────────────────────────
section "REST API"
# REST API is enabled by default in WordPress 4.7+.
# Ensure pretty permalinks are set (required for clean REST API URLs).
CURRENT_PERMALINKS=$(wp option get permalink_structure --path=/var/www/html 2>/dev/null || echo "")
if [ -z "$CURRENT_PERMALINKS" ]; then
  wp rewrite structure '/%postname%/' --path=/var/www/html
  wp rewrite flush --path=/var/www/html
  info "Permalink structure set to /%postname%/"
else
  info "Permalink structure: $CURRENT_PERMALINKS"
fi

# Ensure REST API is not disabled
wp option update blog_public 1 --path=/var/www/html >/dev/null 2>&1 || true
info "REST API enabled at: $WP_SITE_URL/wp-json/wp/v2/"

# ── 5. Create contributor user ────────────────────────────────────────────────
section "Contributor User"
if wp user get "$WP_API_USER" --path=/var/www/html >/dev/null 2>&1; then
  info "User '$WP_API_USER' already exists"
else
  wp user create "$WP_API_USER" "$WP_API_EMAIL" \
    --role=contributor \
    --user_pass="$WP_API_PASSWORD" \
    --path=/var/www/html
  info "Created user: $WP_API_USER (role: contributor)"
fi

# ── 6. Create Application Password for REST API ──────────────────────────────
section "Application Password (REST API)"
# Application passwords require WordPress 5.6+ (included in latest)
# Generate a new application password for the API user
APP_PASS=$(wp user application-password create "$WP_API_USER" "IoTSpark REST API" \
  --path=/var/www/html \
  --porcelain 2>/dev/null || echo "")

if [ -n "$APP_PASS" ]; then
  info "Application password created for '$WP_API_USER'"
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────┐"
  echo "  │  REST API Credentials                                   │"
  echo "  │  User:     $WP_API_USER                                 │"
  echo "  │  App Pass: $APP_PASS                                    │"
  echo "  │                                                         │"
  echo "  │  Save this password — it won't be shown again!         │"
  echo "  └─────────────────────────────────────────────────────────┘"
  echo ""
  # Save to a file for verify.sh to use
  echo "$WP_API_USER:$APP_PASS" > /scripts/.api-credentials
else
  info "Application password already exists or creation skipped"
fi

# ── 7. Summary ────────────────────────────────────────────────────────────────
section "Setup Complete"
echo ""
echo "  WordPress:  $WP_SITE_URL"
echo "  Admin:      $WP_SITE_URL/wp-admin  ($WP_ADMIN_USER / $WP_ADMIN_PASSWORD)"
echo "  REST API:   $WP_SITE_URL/wp-json/wp/v2/"
echo "  API User:   $WP_API_USER (contributor)"
echo ""
echo "  Run verify: docker compose run --rm -T wpcli sh /scripts/verify.sh"
echo ""
