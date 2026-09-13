#!/bin/bash

# Скрипт для обновления системных таблиц MariaDB после обновления версии.
# Запускается в контейнере mariadb.
# Обновляет системные таблицы после обновления с MariaDB 10.4 на 10.11
# Запуск в контейнере командой: bash scripts/upgrade.sh
# Запуск на хосте, напр., для локального окружения, командой: docker exec -t loc_es_mariadb bash scripts/upgrade.sh

set -euo pipefail

echo "# Запускаем обновление системных таблиц MariaDB..."

# Проверяем наличие переменных окружения MARIADB_ROOT_PASSWORD
if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена!"
    exit 1
fi

# Проверяем подключение к базе данных
if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
    echo "ОШИБКА: Не удается подключиться к базе данных!"
    exit 1
fi

echo "# Подключение к базе данных успешно. ОК!"

# Запускаем mariadb-upgrade для обновления системных таблиц
echo "# Обновляем системные таблицы..."
mariadb-upgrade -u root -p"$MARIADB_ROOT_PASSWORD"

if [ $? -eq 0 ]; then
    echo "# Системные таблицы успешно обновлены. ОК!"
    echo "# Обновление завершено успешно!"
else
    echo "ОШИБКА: Не удалось обновить системные таблицы!"
    exit 1
fi
