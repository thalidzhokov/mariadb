#!/bin/bash

set -euo pipefail

# Скрипт для создания пользователя debezium в базе данных
echo "# Запускаем создание пользователя debezium..."

set -e

# Путь к SQL-файлу
SQL_FILE="/docker-entrypoint-initdb.d/z0-debezium-user.sql"

# Проверяем существование SQL-файла
if [ ! -f "$SQL_FILE" ]; then
    echo "ОШИБКА: Файл $SQL_FILE не найден!"
    exit 1
fi

# Проверяем наличие необходимых переменных окружения
if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена!"
    exit 1
fi

if [ -z "$MARIADB_DATABASE" ]; then
    echo "ОШИБКА: Переменная MARIADB_DATABASE не установлена!"
    exit 1
fi

# Выполняем SQL-файл через mariadb клиент
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" < "$SQL_FILE"

# Проверяем права пользователя debezium
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SHOW GRANTS FOR 'debezium'@'%';"
