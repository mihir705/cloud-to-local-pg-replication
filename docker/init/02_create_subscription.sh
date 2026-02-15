#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for local postgres..."
until pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; do
  sleep 2
done

: "${CLOUD_HOST?Need CLOUD_HOST}"
: "${CLOUD_PORT?Need CLOUD_PORT}"
: "${CLOUD_DB?Need CLOUD_DB}"
: "${CLOUD_USER?Need CLOUD_USER}"
: "${CLOUD_PASSWORD?Need CLOUD_PASSWORD}"
: "${CLOUD_PUBLICATION?Need CLOUD_PUBLICATION}"

# Stable subscriber identity persisted outside pgdata
ID_FILE="/meta/subscriber_id"
if [[ ! -f "$ID_FILE" ]]; then
  date +%s%N | sha256sum | awk '{print substr($1,1,10)}' > "$ID_FILE"
fi
SUB_ID="$(cat "$ID_FILE")"

SUB_NAME="sub_${SUB_ID}"
SLOT_NAME="slot_${SUB_ID}"

echo "Subscriber ID: ${SUB_ID}"
echo "Subscription : ${SUB_NAME}"
echo "Slot         : ${SLOT_NAME}"

# Skip if subscription already exists locally
EXISTS_LOCAL=$(psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -tAc \
  "SELECT 1 FROM pg_subscription WHERE subname='${SUB_NAME}'" || true)

if [[ "${EXISTS_LOCAL}" == "1" ]]; then
  echo "Subscription already exists locally. Skipping create."
  exit 0
fi

# Check if slot exists on the publisher (cloud)
export PGPASSWORD="${CLOUD_PASSWORD}"
SLOT_EXISTS=$(psql "host=${CLOUD_HOST} port=${CLOUD_PORT} dbname=${CLOUD_DB} user=${CLOUD_USER} sslmode=require connect_timeout=10" \
  -tAc "SELECT 1 FROM pg_replication_slots WHERE slot_name='${SLOT_NAME}'" || true)

if [[ "${SLOT_EXISTS}" == "1" ]]; then
  echo "Publisher slot exists. Reusing it (create_slot=false)."
  CREATE_SLOT="false"
else
  echo "Publisher slot does not exist. Creating it (create_slot=true)."
  CREATE_SLOT="true"
fi

echo "Creating subscription..."
psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -v ON_ERROR_STOP=1 <<SQL
CREATE SUBSCRIPTION ${SUB_NAME}
CONNECTION 'host=${CLOUD_HOST} port=${CLOUD_PORT} dbname=${CLOUD_DB} user=${CLOUD_USER} password=${CLOUD_PASSWORD} sslmode=require'
PUBLICATION ${CLOUD_PUBLICATION}
WITH (copy_data=true, create_slot=${CREATE_SLOT}, enabled=true, slot_name='${SLOT_NAME}');
SQL

echo "Subscription created."
