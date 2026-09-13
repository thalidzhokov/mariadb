#!/bin/bash

# Скрипт диагностики деградации под нагрузкой для MariaDB.
# Запуск в контейнере: bash scripts/diagnose-load.sh
# Запуск с хоста: docker exec -i mariadb bash scripts/diagnose-load.sh
#
# Скрипт собирает:
# - глобальные переменные и статус MariaDB
# - серию срезов PROCESSLIST
# - состояние InnoDB, блокировки и активные транзакции
# - топ SQL запросов из performance_schema (digest)
# - хвост slow query log

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

show_help() {
    echo "
Использование: $(basename "$0") [ОПЦИИ]

ОПЦИИ:
  --db <name>           Целевая БД (по умолчанию: MARIADB_DATABASE)
  --samples <n>         Количество срезов PROCESSLIST (по умолчанию: 12)
  --interval <sec>      Интервал между срезами в секундах (по умолчанию: 5)
  --out-dir <path>      Директория отчета (по умолчанию: /tmp/db-diagnose/<timestamp>)
  --help, -h            Показать справку

ПРИМЕР:
  $(basename "$0") --db app_db --samples 24 --interval 2
"
}

TARGET_DB="${MARIADB_DATABASE:-}"
SAMPLES="12"
INTERVAL="5"
TIMESTAMP="$(date +%F_%H-%M-%S)"
OUT_DIR="/tmp/db-diagnose/${TIMESTAMP}"

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --db)
            TARGET_DB="$2"
            shift 2
            ;;
        --samples)
            SAMPLES="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "ОШИБКА: Неизвестный аргумент: $1"
            echo "Используйте --help для получения справки"
            exit 1
            ;;
    esac
done

if [ -z "${MARIADB_ROOT_PASSWORD:-}" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена"
    exit 1
fi

DB_CLIENT_BIN="$(command -v mysql || true)"
if [ -z "$DB_CLIENT_BIN" ]; then
    DB_CLIENT_BIN="$(command -v mariadb || true)"
fi

if [ -z "$DB_CLIENT_BIN" ]; then
    echo "ОШИБКА: В контейнере не найден mysql/mariadb клиент"
    exit 1
fi

if [ -z "$TARGET_DB" ]; then
    echo "ОШИБКА: Не задана целевая БД. Передайте --db или переменную MARIADB_DATABASE"
    exit 1
fi

if ! [[ "$SAMPLES" =~ ^[0-9]+$ ]] || [ "$SAMPLES" -le 0 ]; then
    echo "ОШИБКА: --samples должен быть положительным целым числом"
    exit 1
fi

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -le 0 ]; then
    echo "ОШИБКА: --interval должен быть положительным целым числом"
    exit 1
fi

if ! "$DB_CLIENT_BIN" -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
    echo "ОШИБКА: Не удается подключиться к MariaDB под root"
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "# Диагностика нагрузки MariaDB"
echo "# Целевая БД: $TARGET_DB"
echo "# Срезов processlist: $SAMPLES"
echo "# Интервал: ${INTERVAL} сек"
echo "# Отчеты: $OUT_DIR"

# Запросы выполняем через функцию, а не через eval со вшитым в строку паролем:
# eval ломается на паролях со спецсимволами
run_sql() {
    "$DB_CLIENT_BIN" -uroot -p"$MARIADB_ROOT_PASSWORD" -e "$1"
}

echo "# [1/7] Снимаем переменные и глобальный статус..."
run_sql "
SELECT NOW() AS ts, VERSION() AS version;
SHOW VARIABLES WHERE Variable_name IN (
'max_connections','thread_cache_size','table_open_cache','table_definition_cache',
'innodb_buffer_pool_size','innodb_log_file_size','innodb_flush_log_at_trx_commit',
'innodb_io_capacity','innodb_io_capacity_max','slow_query_log','slow_query_log_file',
'long_query_time','performance_schema'
);
SHOW GLOBAL STATUS WHERE Variable_name IN (
'Uptime','Threads_connected','Threads_running','Max_used_connections',
'Connections','Aborted_connects','Aborted_clients',
'Questions','Queries','Com_select','Com_insert','Com_update','Com_delete',
'Slow_queries','Created_tmp_tables','Created_tmp_disk_tables',
'Innodb_row_lock_waits','Innodb_row_lock_time','Innodb_row_lock_time_avg',
'Innodb_buffer_pool_read_requests','Innodb_buffer_pool_reads'
);
" > "${OUT_DIR}/01-global-status.txt"

echo "# [2/7] Снимаем серию PROCESSLIST..."
PROCESSLIST_FILE="${OUT_DIR}/02-processlist-samples.txt"
{
    echo "# PROCESSLIST samples"
    echo "# samples=${SAMPLES}, interval=${INTERVAL}"
} > "$PROCESSLIST_FILE"

for i in $(seq 1 "$SAMPLES"); do
    {
        echo
        echo "===== SAMPLE ${i}/${SAMPLES} @ $(date +%F' '%T) ====="
    } >> "$PROCESSLIST_FILE"

    run_sql "
SHOW FULL PROCESSLIST;
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL STATUS LIKE 'Threads_connected';
" >> "$PROCESSLIST_FILE"

    if [ "$i" -lt "$SAMPLES" ]; then
        sleep "$INTERVAL"
    fi
done

echo "# [3/7] Снимаем состояние InnoDB..."
run_sql "SHOW ENGINE INNODB STATUS\G" > "${OUT_DIR}/03-innodb-status.txt"

echo "# [4/7] Снимаем блокировки и активные транзакции..."
LOCKS_FILE="${OUT_DIR}/04-locks-and-transactions.txt"
{
    echo "# InnoDB transactions and locks snapshot"
    echo "# ts: $(date +%F' '%T)"
} > "$LOCKS_FILE"

run_sql "
SELECT NOW() AS ts;
SELECT trx_id, trx_state, trx_started, trx_wait_started, trx_rows_locked, trx_rows_modified, trx_query
FROM information_schema.innodb_trx
ORDER BY trx_started ASC;
" >> "$LOCKS_FILE"

run_sql "
SELECT
  r.trx_id AS waiting_trx_id,
  r.trx_started AS waiting_started,
  b.trx_id AS blocking_trx_id,
  b.trx_started AS blocking_started,
  lw.lock_table AS waiting_lock_table,
  lw.lock_index AS waiting_lock_index,
  lw.lock_mode AS waiting_lock_mode,
  lb.lock_mode AS blocking_lock_mode,
  r.trx_query AS waiting_query,
  b.trx_query AS blocking_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_locks lw ON w.requested_lock_id = lw.lock_id
JOIN information_schema.innodb_locks lb ON w.blocking_lock_id = lb.lock_id
JOIN information_schema.innodb_trx r ON w.requesting_trx_id = r.trx_id
JOIN information_schema.innodb_trx b ON w.blocking_trx_id = b.trx_id;
" >> "$LOCKS_FILE" || true

echo "# [5/7] Собираем топ SQL по digest (performance_schema)..."
run_sql "
SELECT
  SCHEMA_NAME,
  COUNT_STAR AS exec_count,
  ROUND(SUM_TIMER_WAIT/1000000000000, 3) AS total_sec,
  ROUND(AVG_TIMER_WAIT/1000000000000, 6) AS avg_sec,
  SUM_ROWS_SENT AS rows_sent,
  SUM_ROWS_EXAMINED AS rows_examined,
  SUM_CREATED_TMP_TABLES AS tmp_tables,
  SUM_CREATED_TMP_DISK_TABLES AS tmp_disk_tables,
  LEFT(DIGEST_TEXT, 500) AS digest_text
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = '${TARGET_DB}'
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 50;
" > "${OUT_DIR}/05-top-digests-by-time.txt"

run_sql "
SELECT
  SCHEMA_NAME,
  COUNT_STAR AS exec_count,
  ROUND(AVG_TIMER_WAIT/1000000000000, 6) AS avg_sec,
  ROUND(MAX_TIMER_WAIT/1000000000000, 6) AS max_sec,
  SUM_ROWS_EXAMINED AS rows_examined,
  LEFT(DIGEST_TEXT, 500) AS digest_text
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = '${TARGET_DB}'
ORDER BY AVG_TIMER_WAIT DESC
LIMIT 50;
" > "${OUT_DIR}/05-top-digests-by-avg.txt"

echo "# [6/7] Собираем горячие таблицы..."
run_sql "
SELECT
  OBJECT_SCHEMA,
  OBJECT_NAME,
  COUNT_READ,
  COUNT_WRITE,
  ROUND(SUM_TIMER_READ/1000000000000, 3) AS read_sec,
  ROUND(SUM_TIMER_WRITE/1000000000000, 3) AS write_sec
FROM performance_schema.table_io_waits_summary_by_table
WHERE OBJECT_SCHEMA = '${TARGET_DB}'
ORDER BY (SUM_TIMER_READ + SUM_TIMER_WRITE) DESC
LIMIT 50;
" > "${OUT_DIR}/06-hot-tables.txt"

echo "# [7/7] Забираем хвост slow query log..."
SLOW_LOG_FILE=$("$DB_CLIENT_BIN" -uroot -p"$MARIADB_ROOT_PASSWORD" -Nse "SHOW VARIABLES LIKE 'slow_query_log_file';" | awk '{print $2}')

{
    echo "# slow_query_log_file=${SLOW_LOG_FILE}"
    echo "# ts: $(date +%F' '%T)"
} > "${OUT_DIR}/07-slow-log-tail.txt"

if [ -n "$SLOW_LOG_FILE" ] && [ -f "$SLOW_LOG_FILE" ]; then
    tail -n 1000 "$SLOW_LOG_FILE" >> "${OUT_DIR}/07-slow-log-tail.txt"
else
    echo "slow query log файл не найден в контейнере" >> "${OUT_DIR}/07-slow-log-tail.txt"
fi

echo "# Готово. Отчеты сохранены в: ${OUT_DIR}"
echo "# Копирование на хост:"
echo "# docker cp mariadb:${OUT_DIR}/. ./db-diagnose-${TIMESTAMP}/"
