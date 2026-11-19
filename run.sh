#!/bin/bash
# shellcheck source=lib/calcardbackup-options.bashlib

DATA_DIR="${DATA_DIR:-/opt/calcardbackup}"
CONFIG_DIR="${CONFIG_DIR:-$DATA_DIR/config}"
LOG_DIR="${LOG_DIR:-$DATA_DIR/log}"
NC_DIR="${NC_DIR:-$DATA_DIR/nextcloud}"
BACKUP_DIR="${BACKUP_DIR:-$DATA_DIR/backup}"

BACKUP_LOG="${BACKUP_LOG:-$LOG_DIR/backup.log}"
CRONTAB_FILE="${CRONTAB_FILE:-$CONFIG_DIR/crontab.conf}"

OPTIONS_LIB="/opt/calcardbackup/lib/calcardbackup-options.bashlib"
if [[ ! -r "$OPTIONS_LIB" ]]; then
	OPTIONS_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/calcardbackup-options.bashlib"
fi
if [[ ! -r "$OPTIONS_LIB" ]]; then
	echo "Cannot read calcardbackup options library: $OPTIONS_LIB" >&2
	exit 1
fi
source "$OPTIONS_LIB"

if [ "${MARIADB_SSL_SKIP:=false}" == "true" ]; then
	MARIADB_CLIENT_CNF="${MARIADB_CLIENT_CNF:-$CONFIG_DIR/mariadb-client.cnf}"
	mkdir -p "$(dirname "$MARIADB_CLIENT_CNF")"
	cat >"$MARIADB_CLIENT_CNF" <<EOF
[client]
skip-ssl = true
EOF
	calcardbackup_enable_mysql_optionfiles
fi

case "$BACKUP_LOG" in
/*) ;;
*) BACKUP_LOG="$PWD/$BACKUP_LOG" ;;
esac
case "$CRONTAB_FILE" in
/*) ;;
*) CRONTAB_FILE="$PWD/$CRONTAB_FILE" ;;
esac

case "$BACKUP_LOG" in
*'#'*)
	echo "ERROR: BACKUP_LOG must not contain '#'."
	exit 1
	;;
esac

if ! mkdir -p "$(dirname "$BACKUP_LOG")" "$(dirname "$CRONTAB_FILE")" "$BACKUP_DIR"; then
	echo "ERROR: Cannot create log or crontab or backup directory." >&2
	exit 1
fi
if ! : >>"$BACKUP_LOG"; then
	echo "ERROR: Cannot initialize BACKUP_LOG: $BACKUP_LOG" >&2
	exit 1
fi

BACKUP_CMD="/opt/calcardbackup/calcardbackup $NC_DIR --output $BACKUP_DIR ${CALCARD_OPTS:=-i}"
BACKUP_LOG_CRON=$(printf "%s" "$BACKUP_LOG" | sed 's/%/\\%/g')
if ! printf "%s\n" "${CRON_TIME:=5 4 * * *} ${BACKUP_CMD} >> ${BACKUP_LOG_CRON} 2>&1" >"$CRONTAB_FILE"; then
	echo "ERROR: Cannot create CRONTAB_FILE: $CRONTAB_FILE" >&2
	exit 1
fi

tail -F "$BACKUP_LOG" &

if [ -n "${INIT_BACKUP}" ]; then
	echo "=> Create a backup on the startup"
	if [ -n "${NC_HOST}" ]; then
		until nc -z "${NC_HOST}" "${NC_PORT:=443}"; do
			echo "waiting for Nextcloud webinterface ..."
			sleep 1
		done
	fi
	if [ -n "${DB_HOST}" ]; then
		until nc -z "${DB_HOST}" "${DB_PORT:=3306}"; do
			echo "waiting for database container ..."
			sleep 1
		done
	fi
	${BACKUP_CMD} >>"${BACKUP_LOG}" 2>&1
fi

echo "=> Running cron task manager"
exec supercronic "$CRONTAB_FILE"
