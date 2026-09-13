#!/bin/bash

# Подключается из скриптов обслуживания: source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
#
# Базовый энтрипоинт разворачивает MARIADB_*_FILE в MARIADB_* только внутри
# своего процесса, docker exec видит исходное окружение контейнера. Поэтому
# файлы читаем здесь сами, тем же способом, что file_env энтрипоинта:
# VAR и VAR_FILE взаимоисключающие, файл должен быть читаемым, после чтения
# VAR_FILE снимается (иначе дочерний bash scripts/*.sh видит оба).
# Незаданные переменные получают пустое значение: иначе set -u обрывает
# скрипт на первой из них, не давая напечатать понятную причину.

for var in MARIADB_ROOT_PASSWORD MARIADB_DATABASE MARIADB_USER MARIADB_PASSWORD MARIADB_DEBEZIUM_PASSWORD; do
    file_var="${var}_FILE"
    if [ -n "${!var:-}" ] && [ -n "${!file_var:-}" ]; then
        echo "ОШИБКА: заданы и $var, и $file_var (взаимоисключающие)" >&2
        return 1 2>/dev/null || exit 1
    fi
    if [ -z "${!var:-}" ] && [ -n "${!file_var:-}" ]; then
        if [ ! -r "${!file_var}" ]; then
            echo "ОШИБКА: $file_var указывает на нечитаемый файл: ${!file_var}" >&2
            return 1 2>/dev/null || exit 1
        fi
        export "$var"="$(< "${!file_var}")"
        # Как file_env энтрипоинта: иначе дочерний bash scripts/*.sh
        # видит и VAR (export), и VAR_FILE (из env контейнера)
        unset "$file_var"
    fi
    if [ -z "${!var+x}" ]; then
        printf -v "$var" ''
    fi
done
unset var file_var
