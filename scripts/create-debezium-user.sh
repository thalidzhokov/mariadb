#!/bin/bash

# Скрипт для создания пользователя debezium.
# Запускается в контейнере mariadb.
# Подставляет переменные окружения в шаблон и применяет его под правами root пользователя.
# Запуск в контейнере командой: bash scripts/create-debezium-user.sh
# Запуск на хосте, напр., для локального окружения, командой: docker exec -t loc_es_mariadb bash scripts/create-debezium-user.sh

set -euo pipefail

echo "# Запускаем создание пользователя debezium..."

TEMPLATE="/init-templates/z0-debezium-user.sql.template"

# Проверяем существование шаблона
if [ ! -f "$TEMPLATE" ]; then
    echo "ОШИБКА: Шаблон $TEMPLATE не найден!"
    exit 1
fi

# Проверяем наличие необходимых переменных окружения
if [ -z "${MARIADB_DATABASE:-}" ]; then
    echo "ОШИБКА: Переменная MARIADB_DATABASE не установлена!"
    exit 1
fi

if [ -z "${MARIADB_DEBEZIUM_PASSWORD:-}" ]; then
    echo "ОШИБКА: Переменная MARIADB_DEBEZIUM_PASSWORD не установлена!"
    exit 1
fi

CLIENT=(mariadb -u root)

if [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then
    CLIENT+=(-p"$MARIADB_ROOT_PASSWORD")
elif [ -z "${MARIADB_ALLOW_EMPTY_ROOT_PASSWORD:-}" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена!"
    exit 1
fi

# Пароль уходит на сервер шестнадцатеричным литералом, а в шаблон подставляется
# уже готовый хеш. Иначе кавычки и слеши в пароле пришлось бы экранировать
# дважды: для SQL и для подстановки в bash, которая сама съедает слеши.
PASSWORD_HEX="$(printf '%s' "$MARIADB_DEBEZIUM_PASSWORD" | od -An -tx1 | tr -d ' \n')"
PASSWORD_HASH="$("${CLIENT[@]}" -N -s -e "SELECT PASSWORD(UNHEX('$PASSWORD_HEX'))")"

if [ -z "$PASSWORD_HASH" ]; then
    echo "ОШИБКА: Не удалось получить хеш пароля от сервера!"
    exit 1
fi

SQL="$(cat "$TEMPLATE")"
SQL="${SQL//'${MARIADB_DATABASE}'/$MARIADB_DATABASE}"
SQL="${SQL//'${MARIADB_DEBEZIUM_PASSWORD_HASH}'/$PASSWORD_HASH}"

# Применяем шаблон
"${CLIENT[@]}" <<< "$SQL"

# Проверяем права пользователя debezium
"${CLIENT[@]}" -e "SHOW GRANTS FOR 'debezium'@'%';"

echo "# Пользователь debezium успешно создан!"
