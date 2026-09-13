#!/bin/bash

# Создание пользователя debezium при первой инициализации тома данных,
# так же как штатный энтрипоинт создает MARIADB_USER и MARIADB_DATABASE.
# На уже инициализированном томе initdb-скрипты не запускаются, поэтому
# для существующей базы используйте scripts/create-debezium-user.sh.

set -euo pipefail

if [ -z "${MARIADB_DEBEZIUM_PASSWORD:-}" ]; then
    echo "# MARIADB_DEBEZIUM_PASSWORD не задан, создание пользователя debezium пропущено"
    exit 0
fi

exec bash /scripts/create-debezium-user.sh
