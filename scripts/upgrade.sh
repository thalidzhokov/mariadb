#!/bin/bash

# Скрипт для обновления системных таблиц MariaDB после смены версии сервера.
# Запускается в контейнере mariadb.
# При MARIADB_AUTO_UPGRADE=1 энтрипоинт делает это сам, скрипт нужен для ручного запуска.
# Запуск в контейнере командой: bash scripts/upgrade.sh
# Запуск на хосте командой: docker exec -t mariadb bash scripts/upgrade.sh

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

echo "# Системные таблицы успешно обновлены. ОК!"
echo "# Обновление завершено успешно!"
