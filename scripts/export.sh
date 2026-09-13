#!/bin/bash

# Скрипт для экспорта базы данных в формате latest_<day_of_week>.sql.gz. 
# Запускается в контейнере mariadb.
# Делает экспорт базы данных MARIADB_DATABASE в файл /mariadb-dump/latest_<day_of_week>.sql.gz под правами пользователя MARIADB_USER.
# Каталог для дампов переопределяется переменной MARIADB_DUMP_DIR.
# Запуск в контейнере командой: bash scripts/export.sh
# Запуск на хосте командой: docker exec -t mariadb bash scripts/export.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# Запускаем экспорт базы данных
echo "# Запускаем экспорт базы данных..."

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

# Создаем дамп базы данных
echo "# Создаем дамп базы данных..."

# Определяем день недели (1=понедельник, 7=воскресенье)
DAY_OF_WEEK=$(date +%u)
DUMP_DIR="${MARIADB_DUMP_DIR:-/mariadb-dump}"
DUMP_FILE="${DUMP_DIR}/latest_${DAY_OF_WEEK}.sql.gz"

# Проверяем директорию для дампов если её нет
if [ ! -d "$DUMP_DIR" ]; then
    echo "ОШИБКА: Директория $DUMP_DIR не найдена!"
    exit 1
fi

# Пишем во временный файл: gzip > target при ошибке dump оставляет
# валидный пустой .sql.gz, который import/recreate потом принимают как свежий дамп
echo "# Создаем дамп в файл $DUMP_FILE..."
DUMP_TMP="${DUMP_FILE}.tmp.$$"
trap 'rm -f "$DUMP_TMP"' EXIT

mariadb-dump -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" \
    --default-character-set=utf8mb4 \
    --events \
    --routines \
    --single-transaction \
    --triggers \
    "$MARIADB_DATABASE" | gzip > "$DUMP_TMP"

# gzip от пустого stdin — около 20 байт; такой файл не публикуем
DUMP_SIZE="$(wc -c < "$DUMP_TMP" | tr -d ' ')"
if [ "$DUMP_SIZE" -le 20 ]; then
    echo "ОШИБКА: дамп пустой или не создан ($DUMP_SIZE байт)!"
    exit 1
fi

mv -f "$DUMP_TMP" "$DUMP_FILE"
trap - EXIT

echo "# Дамп базы данных $MARIADB_DATABASE успешно создан: $DUMP_FILE"
ls -lh "$DUMP_FILE"
