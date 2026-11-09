#!/bin/bash

set -euo pipefail

CONFIG=/tmp/ocelot/ocelot.conf
TEMPLATE=/srv/ocelot.conf.template

MYSQL_HOST=${MYSQL_HOST:-mysql}
MYSQL_DATABASE=${MYSQL_DATABASE:?MYSQL_DATABASE must be set}
MYSQL_USER=${OCELOT_MYSQL_USER:?OCELOT_MYSQL_USER must be set}
MYSQL_PASSWORD=${OCELOT_MYSQL_PASSWORD:?OCELOT_MYSQL_PASSWORD must be set}
SITE_PASSWORD=${TRACKER_SECRET:?TRACKER_SECRET must be set}
REPORT_PASSWORD=${TRACKER_REPORTKEY:?TRACKER_REPORTKEY must be set}

if [ "${#SITE_PASSWORD}" -ne 32 ] || [ "${#REPORT_PASSWORD}" -ne 32 ]; then
    echo "Ocelot site_password and report_password must each be 32 characters." >&2
    exit 1
fi

escape_replacement()
{
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

MYSQL_HOST_ESC=$(escape_replacement "$MYSQL_HOST")
MYSQL_DATABASE_ESC=$(escape_replacement "$MYSQL_DATABASE")
MYSQL_USER_ESC=$(escape_replacement "$MYSQL_USER")
MYSQL_PASSWORD_ESC=$(escape_replacement "$MYSQL_PASSWORD")
SITE_PASSWORD_ESC=$(escape_replacement "$SITE_PASSWORD")
REPORT_PASSWORD_ESC=$(escape_replacement "$REPORT_PASSWORD")

mkdir -p /tmp/ocelot
chmod 700 /tmp/ocelot

sed \
    -e "s|@MYSQL_HOST@|${MYSQL_HOST_ESC}|g" \
    -e "s|@MYSQL_USER@|${MYSQL_USER_ESC}|g" \
    -e "s|@MYSQL_PASSWORD@|${MYSQL_PASSWORD_ESC}|g" \
    -e "s|@MYSQL_DATABASE@|${MYSQL_DATABASE_ESC}|g" \
    -e "s|@SITE_PASSWORD@|${SITE_PASSWORD_ESC}|g" \
    -e "s|@REPORT_PASSWORD@|${REPORT_PASSWORD_ESC}|g" \
    "$TEMPLATE" > "$CONFIG"
chmod 0600 "$CONFIG"

until nc -z "$MYSQL_HOST" 3306; do
    echo "Waiting for MySQL..." >&2
    sleep 2
done

# Ocelot trusts X-Forwarded-For unless told otherwise. Set OCELOT_IGNORE_XFF=1
# when the tracker port is published directly instead of behind a proxy.
args=(-c "$CONFIG")
if [ "${OCELOT_IGNORE_XFF:-0}" = "1" ]; then
    args+=(--ignore-xff)
fi

exec /srv/ocelot "${args[@]}"
