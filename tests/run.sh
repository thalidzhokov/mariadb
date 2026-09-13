#!/bin/bash

# Проверка образа на живом контейнере: HEALTHCHECK, autotune, пользователи,
# скрипты обслуживания. Нужен docker на хосте, образ должен быть собран.
# Запуск: bash tests/run.sh [образ]
#
# Пароли нарочно содержат кавычку и обратный слеш, имя базы - подчеркивание,
# root и debezium задаются через *_FILE: это те места, где ломались скрипты.

set -euo pipefail

IMAGE="${1:-thalidzhokov/mariadb:11.8}"
NAME="mariadb-test-$$"
WORK_DIR="$(mktemp -d)"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROOT_PASSWORD="root-p@ss'word\\1"
APP_PASSWORD="app-p@ss'word\\2"
NEW_APP_PASSWORD="new-p@ss'word\\3"
DEBEZIUM_PASSWORD="dbz-p@ss'word\\4"
DATABASE="test_db"
USER="test_user"

FAILED=0

cleanup() {
    docker rm -f -v "$NAME" > /dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

check() {
    local name="$1"
    shift
    if "$@" > "$WORK_DIR/check.log" 2>&1; then
        echo "[ok] $name"
    else
        echo "[fail] $name"
        sed 's/^/       /' "$WORK_DIR/check.log"
        FAILED=$((FAILED + 1))
    fi
}

# -r: в пакетном режиме клиент иначе удваивает обратный слеш в выводе
sql_root() {
    docker exec "$NAME" mariadb -uroot -p"$ROOT_PASSWORD" -N -s -r -e "$1"
}

sql_as() {
    local user="$1" password="$2" query="$3"
    docker exec "$NAME" mariadb -u"$user" -p"$password" -N -s -e "$query"
}

# Файлы для *_FILE кладутся через docker cp, чтобы не зависеть от bind mount
mkdir -p "$WORK_DIR/secrets"
printf '%s' "$ROOT_PASSWORD" > "$WORK_DIR/secrets/root"
printf '%s' "$DEBEZIUM_PASSWORD" > "$WORK_DIR/secrets/debezium"

echo "# Контейнер $NAME из $IMAGE"
docker create --name "$NAME" \
    --memory 2g \
    -e MARIADB_ROOT_PASSWORD_FILE=/run/secrets/root \
    -e MARIADB_DATABASE="$DATABASE" \
    -e MARIADB_USER="$USER" \
    -e MARIADB_PASSWORD="$APP_PASSWORD" \
    -e MARIADB_DEBEZIUM_PASSWORD_FILE=/run/secrets/debezium \
    -e MARIADB_HEALTHCHECK_TABLE=test_table \
    -e MARIADB_HEALTHCHECK_INDEX=idx_test_table_name \
    -e MARIADB_AUTOTUNE_FIO_SIZE=64M \
    -e MARIADB_AUTOTUNE_FIO_RUNTIME=5 \
    "$IMAGE" > /dev/null
docker cp "$WORK_DIR/secrets" "$NAME:/run/"
docker cp "$REPO_DIR/init/test_init.sql" "$NAME:/docker-entrypoint-initdb.d/"
docker start "$NAME" > /dev/null

wait_healthy() {
    local deadline=$((SECONDS + 300)) status
    while [ "$SECONDS" -lt "$deadline" ]; do
        status="$(docker inspect -f '{{.State.Health.Status}}' "$NAME")"
        case "$status" in
            healthy) return 0 ;;
            unhealthy) docker logs "$NAME" | tail -n 30; return 1 ;;
        esac
        sleep 3
    done
    docker logs "$NAME" | tail -n 30
    return 1
}

echo "# Ждем HEALTHCHECK"
check "HEALTHCHECK образа: healthy" wait_healthy

# autotune
echo "# autotune"
check "autotune записал 95-autotune.cnf" \
    docker exec "$NAME" grep -E '^innodb_buffer_pool_size=' /etc/mysql/conf.d/95-autotune.cnf

max_connections_applied() {
    local cnf live
    cnf="$(docker exec "$NAME" sed -n 's/^max_connections=//p' /etc/mysql/conf.d/95-autotune.cnf)"
    live="$(sql_root "SELECT @@max_connections")"
    echo "cnf=$cnf live=$live"
    [ -n "$cnf" ] && [ "$cnf" = "$live" ]
}
check "max_connections из autotune применен сервером" max_connections_applied

buffer_pool_from_limit() {
    local live
    live="$(sql_root "SELECT @@innodb_buffer_pool_size")"
    echo "innodb_buffer_pool_size=$live"
    [ "$live" -gt $((128 * 1024 * 1024)) ]
}
check "innodb_buffer_pool_size больше дефолта" buffer_pool_from_limit

# Пользователи после первой инициализации
echo "# Пользователи"
check "root: пароль из MARIADB_ROOT_PASSWORD_FILE" sql_root "SELECT 1"
check "$USER: пароль с кавычкой и слешем" sql_as "$USER" "$APP_PASSWORD" "USE \`$DATABASE\`; SELECT 1"
check "debezium: пароль из MARIADB_DEBEZIUM_PASSWORD_FILE" sql_as debezium "$DEBEZIUM_PASSWORD" "SELECT 1"

grant_escaped() {
    local grants
    grants="$(sql_root "SHOW GRANTS FOR '$1'@'%'")"
    echo "$grants"
    echo "$grants" | grep -qF '`test\_db`'
}
check "debezium: _ в GRANT экранирован" grant_escaped debezium

# Инициализация из /docker-entrypoint-initdb.d
echo "# init/test_init.sql"
test_table_rows() {
    local rows
    rows="$(sql_as "$USER" "$APP_PASSWORD" "SELECT COUNT(*) FROM \`$DATABASE\`.test_table")"
    echo "rows=$rows"
    [ "$rows" = "5" ]
}
check "test_table создана в $DATABASE с данными" test_table_rows

# Полный healthcheck.sh: читает *_FILE через env.sh, проверяет таблицу и индекс
# из init и не должен ротировать бинлог
echo "# scripts/healthcheck.sh"
healthcheck_keeps_binlog() {
    local before after
    before="$(sql_root "SHOW BINLOG STATUS" | cut -f1)"
    docker exec "$NAME" bash scripts/healthcheck.sh > "$WORK_DIR/healthcheck.log" 2>&1 || {
        cat "$WORK_DIR/healthcheck.log"
        return 1
    }
    after="$(sql_root "SHOW BINLOG STATUS" | cut -f1)"
    echo "binlog before=$before after=$after"
    grep -q 'есть индекс idx_test_table_name' "$WORK_DIR/healthcheck.log" \
        && [ "$before" = "$after" ]
}
check "healthcheck.sh проходит, видит индекс и не ротирует бинлог" healthcheck_keeps_binlog

# recreate.sh с новым паролем: экспорт под старым, затем пересоздание из этого дампа
echo "# scripts/recreate.sh"
sql_root "CREATE TABLE \`$DATABASE\`.marker (id INT PRIMARY KEY); INSERT INTO \`$DATABASE\`.marker VALUES (42)"
check "export.sh под текущим паролем" docker exec "$NAME" bash scripts/export.sh
check "recreate.sh с новым MARIADB_PASSWORD" \
    docker exec -e MARIADB_PASSWORD="$NEW_APP_PASSWORD" "$NAME" bash scripts/recreate.sh
check "$USER: вход по новому паролю" sql_as "$USER" "$NEW_APP_PASSWORD" "SELECT 1"
old_password_rejected() {
    ! sql_as "$USER" "$APP_PASSWORD" "SELECT 1"
}
check "$USER: старый пароль не подходит" old_password_rejected
check "$USER: _ в GRANT экранирован после create.sh" grant_escaped "$USER"

other_db_denied() {
    sql_root "CREATE DATABASE IF NOT EXISTS testXdb"
    ! sql_as "$USER" "$NEW_APP_PASSWORD" "USE testXdb"
}
check "$USER: нет доступа к testXdb" other_db_denied
check "recreate.sh --export под новым паролем" \
    docker exec -e MARIADB_PASSWORD="$NEW_APP_PASSWORD" "$NAME" bash scripts/recreate.sh --export

marker_restored() {
    local value
    value="$(sql_as "$USER" "$NEW_APP_PASSWORD" "SELECT id FROM \`$DATABASE\`.marker")"
    echo "marker=$value"
    [ "$value" = "42" ]
}
check "данные восстановлены из дампа" marker_restored
check "debezium после recreate.sh доступен" sql_as debezium "$DEBEZIUM_PASSWORD" "SELECT 1"

# set -u: без переменной скрипт должен напечатать свою ошибку, а не unbound variable
echo "# set -u"
unset_var_message() {
    local out
    out="$(docker exec "$NAME" env -u MARIADB_DATABASE bash scripts/create.sh 2>&1 || true)"
    echo "$out"
    echo "$out" | grep -q 'MARIADB_DATABASE не установлена' && ! echo "$out" | grep -q 'unbound variable'
}
check "create.sh без MARIADB_DATABASE печатает свою ошибку" unset_var_message

echo
if [ "$FAILED" -eq 0 ]; then
    echo "# Все проверки прошли"
else
    echo "# Провалено проверок: $FAILED"
    exit 1
fi
