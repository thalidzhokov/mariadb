#!/bin/bash

# Скрипт для создания базы данных.
# Запускается в контейнере mariadb.
# Создает базу данных MARIADB_DATABASE в контейнере под правами root пользователя.
# Запуск в контейнере командой: bash scripts/create.sh
# Запуск на хосте командой: docker exec -t mariadb bash scripts/create.sh

set -euo pipefail

echo "# Запускаем создание базы данных..."

# Проверяем наличие переменных окружения MARIADB_DATABASE и MARIADB_ROOT_PASSWORD
if [ -z "$MARIADB_DATABASE" ]; then
    echo "ОШИБКА: Переменная MARIADB_DATABASE не установлена!"
    exit 1
fi

if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена!"
    exit 1
fi

# Создаем базу данных
echo "# Создаем базу данных..."
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$MARIADB_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Проверяем наличие переменных окружения MARIADB_USER и MARIADB_PASSWORD
if [ -z "$MARIADB_USER" ]; then
    echo "ОШИБКА: Переменная MARIADB_USER не установлена!"
    exit 1
fi

if [ -z "$MARIADB_PASSWORD" ]; then
    echo "ОШИБКА: Переменная MARIADB_PASSWORD не установлена!"
    exit 1
fi

# Создаем пользователя MARIADB_USER с паролем MARIADB_PASSWORD (если он не существует)
echo "# Создаем пользователя $MARIADB_USER c паролем (если он не существует)"
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$MARIADB_USER'@'%' IDENTIFIED BY '$MARIADB_PASSWORD';"

# Добавляем права на базу данных MARIADB_DATABASE для пользователя MARIADB_USER
echo "# Добавляем права на базу данных $MARIADB_DATABASE для пользователя $MARIADB_USER"
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`$MARIADB_DATABASE\`.* TO '$MARIADB_USER'@'%';"

# Применяем изменения
echo "# Применяем изменения"
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

echo "# База данных $MARIADB_DATABASE успешно создана!"

