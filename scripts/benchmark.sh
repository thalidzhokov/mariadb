#!/bin/bash

# Скрипт бенчмарка MariaDB внутри контейнера.
# Запуск в контейнере: bash scripts/benchmark.sh
# Запуск с хоста: docker exec -ti mariadb bash scripts/benchmark.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

show_help() {
    echo "
Использование: $(basename "$0") [ОПЦИИ]

Скрипт снимает baseline метрики и прогоняет mariadb-slap (read/write/mixed).

ОПЦИИ:
  --db <name>              Целевая БД: проверка существования и метки в отчете
                           (по умолчанию: MARIADB_DATABASE)
  --bench-db <name>        БД для mariadb-slap (по умолчанию: bench_slap)
  --out-dir <path>         Директория для отчетов (по умолчанию: /tmp/db-bench/<timestamp>)
  --concurrency <list>     Конкурентность, напр. 10,50,100
  --iterations <n>         Количество итераций mariadb-slap
  --read-queries <n>       Количество запросов для read-теста
  --write-queries <n>      Количество запросов для write-теста
  --mixed-queries <n>      Количество запросов для mixed-теста
  --skip-tuner             Пропустить запуск mysqltuner
  --help, -h               Показать справку

ПРИМЕР:
  $(basename "$0") --db app_db --bench-db bench_slap --concurrency 10,50,100
"
}

if [ -z "${MARIADB_ROOT_PASSWORD:-}" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена"
    exit 1
fi

TARGET_DB="${MARIADB_DATABASE:-}"
BENCH_DB="bench_slap"
CONCURRENCY="10,50,100"
ITERATIONS="3"
READ_QUERIES="12000"
WRITE_QUERIES="6000"
MIXED_QUERIES="9000"
RUN_TUNER="1"
TIMESTAMP="$(date +%F_%H-%M-%S)"
OUT_DIR="/tmp/db-bench/${TIMESTAMP}"

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
        --bench-db)
            BENCH_DB="$2"
            shift 2
            ;;
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        --concurrency)
            CONCURRENCY="$2"
            shift 2
            ;;
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --read-queries)
            READ_QUERIES="$2"
            shift 2
            ;;
        --write-queries)
            WRITE_QUERIES="$2"
            shift 2
            ;;
        --mixed-queries)
            MIXED_QUERIES="$2"
            shift 2
            ;;
        --skip-tuner)
            RUN_TUNER="0"
            shift
            ;;
        *)
            echo "ОШИБКА: Неизвестный аргумент: $1"
            echo "Используйте --help для получения справки"
            exit 1
            ;;
    esac
done

if [ -z "$TARGET_DB" ]; then
    echo "ОШИБКА: Не задана целевая БД. Передайте --db или переменную MARIADB_DATABASE"
    exit 1
fi

# Пароль не в argv: иначе виден в списке процессов
CLIENT_CNF="$(mktemp)"
chmod 600 "$CLIENT_CNF"
printf "[client]\nuser=root\npassword=%s\n" "$MARIADB_ROOT_PASSWORD" > "$CLIENT_CNF"
trap 'rm -f "$CLIENT_CNF"' EXIT

mariadb_root() {
    mariadb --defaults-extra-file="$CLIENT_CNF" "$@"
}

if ! mariadb_root -N -s -e \
    "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TARGET_DB'" \
    | grep -qx '1'; then
    echo "ОШИБКА: База данных $TARGET_DB не существует"
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "# Бенчмарк MariaDB"
echo "# Целевая БД: $TARGET_DB"
echo "# БД для mariadb-slap: $BENCH_DB"
echo "# Конкурентность: $CONCURRENCY"
echo "# Итераций: $ITERATIONS"
echo "# Отчеты: $OUT_DIR"

echo "# [1/7] Снимаем baseline переменные и статус..."
{
    echo "-- target_db=$TARGET_DB"
    mariadb_root -e "
SELECT NOW() as ts, VERSION() as version;
SELECT SCHEMA_NAME, DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME
FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TARGET_DB';
SELECT COUNT(*) AS table_count
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = '$TARGET_DB' AND TABLE_TYPE = 'BASE TABLE';
SHOW VARIABLES WHERE Variable_name IN (
'max_connections','sort_buffer_size','read_buffer_size','read_rnd_buffer_size',
'join_buffer_size','binlog_cache_size','tmp_table_size','max_heap_table_size',
'query_cache_type','query_cache_size','innodb_buffer_pool_size','innodb_log_file_size',
'innodb_flush_log_at_trx_commit','innodb_io_capacity','innodb_io_capacity_max',
'thread_cache_size','table_open_cache','table_definition_cache','slow_query_log','long_query_time'
);
SHOW GLOBAL STATUS WHERE Variable_name IN (
'Uptime','Threads_connected','Threads_running','Max_used_connections',
'Questions','Queries','Com_select','Com_insert','Com_update','Com_delete',
'Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests',
'Innodb_row_lock_waits','Innodb_row_lock_time','Created_tmp_disk_tables',
'Slow_queries','Aborted_connects','Aborted_clients'
);"
} > "${OUT_DIR}/01-vars-status-before.txt"

if [ "$RUN_TUNER" = "1" ]; then
    if [ -f "/mysqltuner.pl" ]; then
        echo "# [2/7] Запускаем mysqltuner..."
        perl /mysqltuner.pl --defaults-file="$CLIENT_CNF" --noask --nocolor > "${OUT_DIR}/02-mysqltuner-before.txt"
    else
        echo "# [2/7] mysqltuner.pl не найден, шаг пропущен"
    fi
else
    echo "# [2/7] Запуск mysqltuner отключен"
fi

echo "# [3/7] Сбрасываем status counters..."
mariadb_root -e "FLUSH STATUS;"

echo "# [4/7] READ benchmark..."
mariadb-slap \
  --defaults-extra-file="$CLIENT_CNF" --host=127.0.0.1 --port=3306 \
  --create-schema="$BENCH_DB" \
  --concurrency="$CONCURRENCY" --iterations="$ITERATIONS" --number-of-queries="$READ_QUERIES" \
  --auto-generate-sql --auto-generate-sql-load-type=read --auto-generate-sql-add-autoincrement \
  > "${OUT_DIR}/03-read.txt"

echo "# [5/7] WRITE benchmark..."
mariadb-slap \
  --defaults-extra-file="$CLIENT_CNF" --host=127.0.0.1 --port=3306 \
  --create-schema="$BENCH_DB" \
  --concurrency="$CONCURRENCY" --iterations="$ITERATIONS" --number-of-queries="$WRITE_QUERIES" \
  --auto-generate-sql --auto-generate-sql-load-type=write --auto-generate-sql-add-autoincrement \
  > "${OUT_DIR}/04-write.txt"

echo "# [6/7] MIXED benchmark..."
mariadb-slap \
  --defaults-extra-file="$CLIENT_CNF" --host=127.0.0.1 --port=3306 \
  --create-schema="$BENCH_DB" \
  --concurrency="$CONCURRENCY" --iterations="$ITERATIONS" --number-of-queries="$MIXED_QUERIES" \
  --auto-generate-sql --auto-generate-sql-load-type=mixed --auto-generate-sql-add-autoincrement \
  > "${OUT_DIR}/05-mixed.txt"

echo "# [7/7] Снимаем статус после бенчмарков..."
mariadb_root -e "
SHOW GLOBAL STATUS WHERE Variable_name IN (
'Threads_connected','Threads_running','Max_used_connections',
'Questions','Queries','Com_select','Com_insert','Com_update','Com_delete',
'Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests',
'Innodb_row_lock_waits','Innodb_row_lock_time','Created_tmp_disk_tables',
'Slow_queries','Aborted_connects','Aborted_clients'
);" > "${OUT_DIR}/06-status-after-bench.txt"

echo "# Готово. Отчеты сохранены в: ${OUT_DIR}"
echo "# Для копирования на хост:"
echo "# docker cp mariadb:${OUT_DIR}/. ./db-bench-${TIMESTAMP}/"
