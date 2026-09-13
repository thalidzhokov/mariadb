#!/bin/bash

# Скрипт для импорта базы данных из файла latest_<day_of_week>.sql.gz. 
# Запускается в контейнере mariadb.
# Импортирует базу данных MARIADB_DATABASE из файла /var/www/dump/latest_<day_of_week>.sql.gz под правами пользователя MARIADB_USER.
# На хосте файл ./docker_images/mariadb/dump/latest_<day_of_week>.sql.gz
# Запуск в контейнере командой: bash scripts/import.sh
# Запуск на хосте, напр., для локального окружения, командой: docker exec -t loc_es_mariadb bash scripts/import.sh

set -euo pipefail

# Запускаем импорт базы данных
echo "# Запускаем импорт базы данных..."

# Проверяем наличие переменных окружения MARIADB_DATABASE, MARIADB_USER и MARIADB_PASSWORD
if [ -z "$MARIADB_DATABASE" ]; then
    echo "ОШИБКА: Переменная MARIADB_DATABASE не установлена!"
    exit 1
fi

if [ -z "$MARIADB_USER" ]; then
    echo "ОШИБКА: Переменная MARIADB_USER не установлена!"
    exit 1
fi

if [ -z "$MARIADB_PASSWORD" ]; then
    echo "ОШИБКА: Переменная MARIADB_PASSWORD не установлена!"
    exit 1
fi

# Импортируем базу данных
echo "# Импортируем базу данных..."

# Проверяем существование файла дампа и берем самый свежий.
# ls при отсутствии файлов завершается с ошибкой и из-за set -e обрывает
# скрипт, не доходя до запасного варианта, поэтому ищем через find
DUMP_DIR="${MARIADB_DUMP_DIR:-/var/www/dump}"
DUMP_FILE=""

if [ -d "$DUMP_DIR" ]; then
    DUMP_FILE=$(find "$DUMP_DIR" -maxdepth 1 -name 'latest_*.sql.gz' -printf '%T@ %p\n' \
        | sort -rn | sed -n '1s/^[^ ]* //p')
fi

# Проверяем существование файла дампа
if [ -f "$DUMP_FILE" ]; then
    echo "# Файл дампа $DUMP_FILE найден!"
else
    # Файл дампа не найден, пробуем импортировать из файла /docker-entrypoint-initdb.d/latest.sql.gz
    echo "# Файл дампа не найден, пробуем импортировать из файла /docker-entrypoint-initdb.d/latest.sql.gz"
    DUMP_FILE="/docker-entrypoint-initdb.d/latest.sql.gz"

    if [ -f "$DUMP_FILE" ]; then
        echo "# Используем дамп из файла $DUMP_FILE ..."
    else
        echo "ОШИБКА: Файл дампа $DUMP_FILE не найден!"
        exit 1
    fi
fi

# Импортируем дамп
echo "# Импортируем дамп из файла $DUMP_FILE..."
zcat "$DUMP_FILE" | mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"

echo "# База данных $MARIADB_DATABASE успешно импортирована из $DUMP_FILE"
