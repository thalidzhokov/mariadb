#!/bin/bash

# Замер IOPS диска и расчет innodb_io_capacity.
# Запускается при первом старте контейнера, результат кешируется в томе данных,
# поэтому последующие запуски проходят без замера.
# Скрипт не должен мешать запуску сервера: при любой неудаче замера параметры
# не выставляются и остаются дефолтными.

set -uo pipefail

DATADIR="${MARIADB_DATADIR:-/var/lib/mysql}"
CACHE_FILE="${DATADIR}/.autotune-io-capacity"
TEST_FILE="${DATADIR}/.autotune-fio-test"
FIO_SIZE="${MARIADB_AUTOTUNE_FIO_SIZE:-1G}"
FIO_RUNTIME="${MARIADB_AUTOTUNE_FIO_RUNTIME:-30}"

trap 'rm -f "$TEST_FILE"' EXIT

if [ -r "$CACHE_FILE" ] && [ -z "${MARIADB_AUTOTUNE_FIO_FORCE:-}" ]; then
    cat "$CACHE_FILE"
    exit 0
fi

if ! command -v fio > /dev/null; then
    echo "# fio не установлен, innodb_io_capacity оставлен по умолчанию"
    exit 0
fi

if [ ! -w "$DATADIR" ]; then
    echo "# $DATADIR недоступен на запись, innodb_io_capacity оставлен по умолчанию"
    exit 0
fi

# innodb_io_capacity ограничивает фоновую запись страниц, поэтому меряем
# случайную запись блоком в размер страницы InnoDB. Случайное чтение,
# особенно на потребительских SSD, завышает оценку записи в разы.
# --time_based: иначе на SSD fio часто заканчивается по --size раньше runtime
FIO_OUT="$(fio --name=autotune-randwrite \
    --ioengine=libaio \
    --iodepth=32 \
    --rw=randwrite \
    --bs=16k \
    --direct=1 \
    --size="$FIO_SIZE" \
    --numjobs=1 \
    --runtime="$FIO_RUNTIME" \
    --time_based \
    --group_reporting \
    --filename="$TEST_FILE" 2>/dev/null || true)"

# Сначала строка "iops ... avg=1234.5"; иначе краткий "IOPS=12.3k"
WRITE_IOPS="$(printf '%s\n' "$FIO_OUT" | grep -m1 -E '[[:space:]]iops[[:space:]].*avg=' \
    | sed -n 's/.*avg=\([0-9.]*\).*/\1/p')"
if [ -z "$WRITE_IOPS" ]; then
    WRITE_IOPS="$(printf '%s\n' "$FIO_OUT" | grep -m1 -oiE 'IOPS=[0-9.]+[kKmM]?' \
        | head -n1 | cut -d= -f2)"
    case "$WRITE_IOPS" in
        *[kK]) WRITE_IOPS="$(printf '%.0f' "$(echo "${WRITE_IOPS%[kK]} * 1000" | bc -l)")" ;;
        *[mM]) WRITE_IOPS="$(printf '%.0f' "$(echo "${WRITE_IOPS%[mM]} * 1000000" | bc -l)")" ;;
    esac
fi

if [ -z "$WRITE_IOPS" ]; then
    echo "# Замер IOPS не удался, innodb_io_capacity оставлен по умолчанию"
    exit 0
fi

WRITE_IOPS="$(printf "%.0f" "$WRITE_IOPS")"

if [ "$WRITE_IOPS" -le 0 ]; then
    echo "# Измерено 0 IOPS, innodb_io_capacity оставлен по умолчанию"
    exit 0
fi

# Документация советует брать значение с запасом вниз: при завышенном
# io_capacity страницы вытесняются из буфера слишком быстро
IO_CAPACITY=$((WRITE_IOPS / 3))
if [ "$IO_CAPACITY" -lt 100 ]; then
    IO_CAPACITY=100
fi

# Серверный дефолт для max равен 2000 или двум io_capacity, что больше.
# Опускать ниже нельзя, иначе теряется запас на аварийное дожатие страниц.
IO_CAPACITY_MAX=$((IO_CAPACITY * 2))
if [ "$IO_CAPACITY_MAX" -lt 2000 ]; then
    IO_CAPACITY_MAX=2000
fi

RESULT="
# Случайная запись блоком 16K, измерено IOPS: ${WRITE_IOPS}
innodb_io_capacity=${IO_CAPACITY}
innodb_io_capacity_max=${IO_CAPACITY_MAX}"

if printf '%s\n' "$RESULT" > "${CACHE_FILE}.tmp"; then
    mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
fi

printf '%s\n' "$RESULT"
