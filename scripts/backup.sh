#!/bin/bash
# Daily CRM backup: database + uploaded files for every site.
#
# Keeps KEEP_DAYS (default 14) days in ./backups on the server and, when
# backup.env has S3 settings, the same in S3 under s3://$S3_BUCKET/crm-backups/.
# backup.env (gitignored, chmod 600) may set:
#   S3_BUCKET, S3_ENDPOINT_URL, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
#   AWS_DEFAULT_REGION, KEEP_DAYS
#
# Cron (root, 21:00 UTC = 02:30 IST):
#   0 21 * * * /home/ubuntu/CRM-SALES/scripts/backup.sh >> /home/ubuntu/CRM-SALES/backups/backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f backup.env ]; then
  set -a
  . ./backup.env
  set +a
fi
KEEP_DAYS=${KEEP_DAYS:-14}
STAMP=$(date -u +%Y%m%d-%H%M%S)
DEST="backups/$STAMP"
TMP="/tmp/crm-backup-$STAMP"

echo "[$(date -u +%FT%TZ)] backup $STAMP starting"
mkdir -p "$DEST"
docker compose exec -T backend bench --site all backup --with-files --compress --backup-path "$TMP"
docker compose cp "backend:$TMP/." "$DEST/"
docker compose exec -T backend rm -rf "$TMP"
du -sh "$DEST"

if [ -n "${S3_BUCKET:-}" ]; then
  aws s3 cp --recursive --only-show-errors "$DEST" "s3://$S3_BUCKET/crm-backups/$STAMP/" \
    ${S3_ENDPOINT_URL:+--endpoint-url "$S3_ENDPOINT_URL"}
  echo "uploaded to s3://$S3_BUCKET/crm-backups/$STAMP/"

  cutoff=$(date -u -d "$KEEP_DAYS days ago" +%Y%m%d)
  aws s3 ls "s3://$S3_BUCKET/crm-backups/" ${S3_ENDPOINT_URL:+--endpoint-url "$S3_ENDPOINT_URL"} \
    | awk '/PRE/ {print $2}' | tr -d / | while read -r old; do
      if [[ "${old%%-*}" < "$cutoff" ]]; then
        aws s3 rm --recursive --only-show-errors "s3://$S3_BUCKET/crm-backups/$old/" \
          ${S3_ENDPOINT_URL:+--endpoint-url "$S3_ENDPOINT_URL"}
        echo "removed s3 backup $old"
      fi
    done
fi

find backups -mindepth 1 -maxdepth 1 -type d -mtime "+$KEEP_DAYS" -print -exec rm -rf {} +
echo "[$(date -u +%FT%TZ)] backup $STAMP done"
