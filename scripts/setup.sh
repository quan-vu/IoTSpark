#!/bin/sh
# setup.sh — Automated WordPress setup via WP-CLI
# Runs inside the wpcli container (profile: setup)

set -e

WP_SITE_URL="${WP_SITE_URL:-http://localhost:8080}"
WP_SITE_TITLE="${WP_SITE_TITLE:-IoTSpark}"
WP_ADMIN_USER="${WP_ADMIN_USER:-admin}"
WP_ADMIN_PASSWORD="${WP_ADMIN_PASSWORD:-admin@IoTSpark2025}"
WP_ADMIN_EMAIL="${WP_ADMIN_EMAIL:-admin@iotspark.local}"
WP_API_USER="${WP_API_USER:-api-contributor}"
WP_API_PASSWORD="${WP_API_PASSWORD:-Contributor@2025}"
WP_API_EMAIL="${WP_API_EMAIL:-contributor@iotspark.local}"
WP_EDITOR_USER="${WP_EDITOR_USER:-editor}"
WP_EDITOR_PASSWORD="${WP_EDITOR_PASSWORD:-Editor@IoTSpark2025}"
WP_EDITOR_EMAIL="${WP_EDITOR_EMAIL:-editor@iotspark.local}"
WP="/usr/local/bin/wp --path=/var/www/html --allow-root"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
section() { printf "\n${CYAN}══ %s ══${NC}\n" "$*"; }

# ── 1. Wait for WordPress files ───────────────────────────────────────────────
section "Waiting for WordPress"
for i in $(seq 1 30); do
  [ -f /var/www/html/wp-config.php ] && break
  printf "  Waiting for wp-config.php... (%s/30)\n" "$i"
  sleep 3
done
[ -f /var/www/html/wp-config.php ] || { echo "wp-config.php not found after 90s"; exit 1; }
info "WordPress files ready"

# ── 2. Core install ───────────────────────────────────────────────────────────
section "WordPress Core"
if $WP core is-installed 2>/dev/null; then
  info "Already installed — updating siteurl/home to $WP_SITE_URL"
  $WP option update siteurl "$WP_SITE_URL"
  $WP option update home "$WP_SITE_URL"
else
  $WP core install \
    --url="$WP_SITE_URL" \
    --title="$WP_SITE_TITLE" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASSWORD" \
    --admin_email="$WP_ADMIN_EMAIL" \
    --skip-email
  info "WordPress installed: $WP_SITE_URL"
fi

# ── 3. Yoast SEO ──────────────────────────────────────────────────────────────
section "Yoast SEO Plugin"
if $WP plugin is-active wordpress-seo 2>/dev/null; then
  YOAST_VER=$($WP plugin get wordpress-seo --field=version 2>/dev/null)
  info "Yoast SEO already active (v$YOAST_VER)"
else
  $WP plugin install wordpress-seo --activate
  info "Yoast SEO installed and activated"
fi

# ── 4. REST API — set permalinks ──────────────────────────────────────────────
section "REST API / Permalinks"
$WP rewrite structure '/%postname%/'
$WP rewrite flush
info "Permalink: /%postname%/ — REST API at $WP_SITE_URL/wp-json/wp/v2/"

# ── 5. Contributor user ───────────────────────────────────────────────────────
section "Contributor User"
if $WP user get "$WP_API_USER" >/dev/null 2>&1; then
  info "User '$WP_API_USER' already exists"
else
  $WP user create "$WP_API_USER" "$WP_API_EMAIL" \
    --role=contributor \
    --user_pass="$WP_API_PASSWORD"
  info "Created: $WP_API_USER (contributor)"
fi

# ── 6. Editor user ────────────────────────────────────────────────────────────
section "Editor User"
if $WP user get "$WP_EDITOR_USER" >/dev/null 2>&1; then
  info "User '$WP_EDITOR_USER' already exists"
else
  $WP user create "$WP_EDITOR_USER" "$WP_EDITOR_EMAIL" \
    --role=editor \
    --user_pass="$WP_EDITOR_PASSWORD"
  info "Created: $WP_EDITOR_USER (editor)"
fi

# ── 7. Application passwords ──────────────────────────────────────────────────
section "Application Passwords (REST API)"

for USERNAME in "$WP_API_USER" "$WP_EDITOR_USER"; do
  COUNT=$($WP user application-password list "$USERNAME" --format=count 2>/dev/null || echo 0)
  if [ "$COUNT" -gt 0 ] 2>/dev/null; then
    info "App password already exists for '$USERNAME' ($COUNT found)"
  else
    APP_PASS=$($WP user application-password create "$USERNAME" "IoTSpark REST API" --porcelain 2>/dev/null || echo "")
    if [ -n "$APP_PASS" ]; then
      info "Created app password for '$USERNAME': $APP_PASS"
      echo "${USERNAME}:${APP_PASS}" >> /scripts/.api-credentials
    fi
  fi
done

# ── 8. Summary ────────────────────────────────────────────────────────────────
section "Setup Complete"
printf "\n"
printf "  WordPress:    %s\n"  "$WP_SITE_URL"
printf "  Admin panel:  %s/wp-admin\n" "$WP_SITE_URL"
printf "  Admin login:  %s / %s\n" "$WP_ADMIN_USER" "$WP_ADMIN_PASSWORD"
printf "  REST API:     %s/wp-json/wp/v2/\n" "$WP_SITE_URL"
printf "  Editor user:  %s / %s\n" "$WP_EDITOR_USER" "$WP_EDITOR_PASSWORD"
printf "\n"
printf "  Credentials saved to: /scripts/.api-credentials\n"
printf "\n"
