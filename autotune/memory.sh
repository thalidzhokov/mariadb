#!/bin/bash

# Расчет буферов по лимиту памяти контейнера.
# Рекомендация MariaDB для нагрузки преимущественно на InnoDB: 60-70% RAM
# под buffer pool и key_buffer_size в пределах 16-64M, когда MyISAM не
# используется. Системные таблицы MariaDB работают на Aria, не на MyISAM,
# поэтому большой key_buffer_size здесь просто отнимает память.

set -euo pipefail

BUFFER_POOL_PERCENT="${MARIADB_BUFFER_POOL_PERCENT:-60}"
KEY_BUFFER_SIZE_MB="${MARIADB_KEY_BUFFER_SIZE_MB:-32}"

# /proc/meminfo внутри контейнера показывает память хоста, а не лимит контейнера,
# поэтому лимит читаем из cgroup и падаем на MemTotal только когда лимита нет
memory_limit_mb() {
    local value=""

    if [ -r /sys/fs/cgroup/memory.max ]; then
        value="$(cat /sys/fs/cgroup/memory.max)"
    elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        value="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
    fi

    # "max" в cgroup v2 и заведомо огромное число в v1 означают отсутствие лимита
    if [ -n "$value" ] && [ "$value" != "max" ] && [ "$value" -lt 9007199254740992 ]; then
        echo $((value / 1048576))
        return
    fi

    awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo
}

TOTAL_MB="$(memory_limit_mb)"
BUFFER_POOL_MB=$((TOTAL_MB * BUFFER_POOL_PERCENT / 100))

# Нижние границы равны серверным дефолтам 11.8. Полы выше них ломают запуск
# на хостах с малой памятью: контейнеру на 512M нельзя выдать гигабайтный пул
if [ "$BUFFER_POOL_MB" -lt 128 ]; then
    BUFFER_POOL_MB=128
fi

# Чем больше redo log, тем реже чекпойнты, но дольше восстановление после краха
LOG_FILE_MB=$((BUFFER_POOL_MB / 4))
if [ "$LOG_FILE_MB" -lt 96 ]; then
    LOG_FILE_MB=96
fi

# Соединения делят с сервером и ОС то, что осталось после buffer pool:
# половина остатка на соединения, половина на словарь, performance_schema
# и файловый кеш. На одно соединение по 99-override.cnf уходит до 8M:
# sort_buffer 4M + read_buffer 1M + binlog_cache 1M + join/read_rnd
# буферы, стек потока и сетевые буферы. Потолок 250 - прежнее статическое
# значение, чтобы на больших хостах поведение не менялось
PER_CONNECTION_MB=8
MAX_CONNECTIONS=$(((TOTAL_MB - BUFFER_POOL_MB) / 2 / PER_CONNECTION_MB))
if [ "$MAX_CONNECTIONS" -gt 250 ]; then
    MAX_CONNECTIONS=250
elif [ "$MAX_CONNECTIONS" -lt 50 ]; then
    MAX_CONNECTIONS=50
fi

echo ""
echo "# Доступно памяти: ${TOTAL_MB}M, доля под buffer pool: ${BUFFER_POOL_PERCENT}%"
echo "innodb_buffer_pool_size=${BUFFER_POOL_MB}M"
echo "innodb_log_file_size=${LOG_FILE_MB}M"
echo "key_buffer_size=${KEY_BUFFER_SIZE_MB}M"
echo "max_connections=${MAX_CONNECTIONS}"
