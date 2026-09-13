#!/bin/bash

# Скрипт для удаления базы данных.
# Запускается в контейнере mariadb.
# Удаляет базу данных MARIADB_DATABASE в контейнере под правами root пользователя.
# Запуск в контейнере командой: bash scripts/drop.sh
# Запуск на хосте, напр., для локального окружения, командой: docker exec -t loc_es_mariadb bash scripts/drop.sh

set -euo pipefail

# Запускаем удаление базы данных
echo "# Запускаем удаление базы данных..."

# Проверяем наличие переменных окружения MARIADB_DATABASE и MARIADB_ROOT_PASSWORD
if [ -z "$MARIADB_DATABASE" ]; then
    echo "ОШИБКА: Переменная MARIADB_DATABASE не установлена!"
    exit 1
fi

if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена!"
    exit 1
fi

# Удаляем базу данных
echo "# Удаляем базу данных..."
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`$MARIADB_DATABASE\`;"

echo "# База данных $MARIADB_DATABASE успешно удалена!"
