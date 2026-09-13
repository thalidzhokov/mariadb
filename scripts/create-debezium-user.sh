#!/bin/bash

# Создание пользователя debezium.
# Вызывается из entrypoint.sh при первой инициализации тома и вручную
# на уже существующей базе: bash scripts/create-debezium-user.sh
# На хосте: docker exec -t mariadb bash scripts/create-debezium-user.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

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

# При первой инициализации временный сервер слушает unix socket (SOCKET
# выставляет штатный docker_setup_env). В обычном docker exec SOCKET нет.
if [ -n "${SOCKET:-}" ]; then
    CLIENT+=(--protocol=socket -hlocalhost --socket="$SOCKET")
fi

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
SQL="${SQL//'${MARIADB_DATABASE_GRANT}'/${MARIADB_DATABASE//_/\\_}}"
SQL="${SQL//'${MARIADB_DATABASE}'/$MARIADB_DATABASE}"
SQL="${SQL//'${MARIADB_DEBEZIUM_PASSWORD_HASH}'/$PASSWORD_HASH}"

# Применяем шаблон
"${CLIENT[@]}" <<< "$SQL"

# Проверяем права пользователя debezium
"${CLIENT[@]}" -e "SHOW GRANTS FOR 'debezium'@'%';"

echo "# Пользователь debezium успешно создан!"
