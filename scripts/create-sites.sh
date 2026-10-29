#!/bin/bash
# Creates each site in $SITES with Frappe CRM and the WhatsApp app installed.
# Safe to re-run: existing sites are skipped (and get any missing app installed).
set -euo pipefail

wait-for-it -t 120 db:3306
wait-for-it -t 120 redis-cache:6379
wait-for-it -t 120 redis-queue:6379

cd /home/frappe/frappe-bench

for site in $SITES; do
  if [ -d "sites/$site" ]; then
    echo "Site $site already exists"
  else
    echo "Creating site $site"
    bench new-site "$site" \
      --mariadb-user-host-login-scope='%' \
      --db-root-username=root \
      --db-root-password="$DB_ROOT_PASSWORD" \
      --admin-password="$ADMIN_PASSWORD" \
      --install-app crm \
      --install-app frappe_whatsapp
  fi
  installed=$(bench --site "$site" list-apps 2>/dev/null || true)
  for app in crm frappe_whatsapp; do
    grep -q "^$app" <<<"$installed" || bench --site "$site" install-app "$app"
  done
done

echo "Sites ready: $SITES"
