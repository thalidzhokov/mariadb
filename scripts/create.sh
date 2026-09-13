#!/bin/bash

# Скрипт для создания базы данных.
# Запускается в контейнере mariadb.
# Создает базу данных MARIADB_DATABASE в контейнере под правами root пользователя.
# Запуск в контейнере командой: bash scripts/create.sh
# Запуск на хосте командой: docker exec -t mariadb bash scripts/create.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

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

# Пароль уходит на сервер шестнадцатеричным литералом, в SQL подставляется
# готовый хеш: кавычки и слеши в пароле тогда экранировать не нужно.
# Тот же прием, что в create-debezium-user.sh
PASSWORD_HEX="$(printf '%s' "$MARIADB_PASSWORD" | od -An -tx1 | tr -d ' \n')"
PASSWORD_HASH="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -N -s -e "SELECT PASSWORD(UNHEX('$PASSWORD_HEX'))")"

if [ -z "$PASSWORD_HASH" ]; then
    echo "ОШИБКА: Не удалось получить хеш пароля от сервера!"
    exit 1
fi

# IF NOT EXISTS не меняет пароль существующему пользователю, поэтому после
# смены MARIADB_PASSWORD его отдельно обновляет ALTER USER
echo "# Создаем пользователя $MARIADB_USER и обновляем его пароль"
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$MARIADB_USER'@'%' IDENTIFIED BY PASSWORD '$PASSWORD_HASH';"
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "ALTER USER '$MARIADB_USER'@'%' IDENTIFIED BY PASSWORD '$PASSWORD_HASH';"

# В GRANT имя базы - шаблон, где _ значит любой символ. Экранируем, как
# делает штатный энтрипоинт, иначе права сядут и на default?db
echo "# Добавляем права на базу данных $MARIADB_DATABASE для пользователя $MARIADB_USER"
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`${MARIADB_DATABASE//_/\\_}\`.* TO '$MARIADB_USER'@'%';"

# Применяем изменения
echo "# Применяем изменения"
mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

echo "# База данных $MARIADB_DATABASE успешно создана!"

