#!/bin/bash
# Builds the CRM image: Frappe v16 + Frappe CRM + frappe_whatsapp (apps.json).
# Re-run to pick up new CRM releases, then: docker compose up -d
set -euo pipefail
cd "$(dirname "$0")"

DOCKER_BUILDKIT=1 docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --build-arg=CACHE_BUST="$(date +%s)" \
  --secret=id=apps_json,src=apps.json \
  --tag="${CUSTOM_IMAGE:-newral-crm}:${CUSTOM_TAG:-16}" \
  --file=images/Containerfile \
  .
