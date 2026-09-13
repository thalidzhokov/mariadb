#!/bin/bash

# Подключается из скриптов обслуживания: source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
#
# Базовый энтрипоинт разворачивает MARIADB_*_FILE в MARIADB_* только внутри
# своего процесса, docker exec видит исходное окружение контейнера. Поэтому
# файлы читаем здесь сами, тем же способом, что file_env энтрипоинта.
# Незаданные переменные получают пустое значение: иначе set -u обрывает
# скрипт на первой из них, не давая напечатать понятную причину.

for var in MARIADB_ROOT_PASSWORD MARIADB_DATABASE MARIADB_USER MARIADB_PASSWORD MARIADB_DEBEZIUM_PASSWORD; do
    file_var="${var}_FILE"
    if [ -z "${!var:-}" ] && [ -n "${!file_var:-}" ]; then
        export "$var"="$(< "${!file_var}")"
    fi
    if [ -z "${!var+x}" ]; then
        printf -v "$var" ''
    fi
done
unset var file_var
