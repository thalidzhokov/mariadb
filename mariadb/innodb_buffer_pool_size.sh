#!/bin/bash
# Расчет: 40% RAM для buffer_pool + 25% от buffer_pool для log_file

set -euo pipefail

# Получить память контейнера в MB
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))

# 40% от общей памяти для buffer pool
INNODB_BUFFER_POOL_SIZE=$((TOTAL_RAM_MB * 4 / 10))

# 25% от buffer pool для log file (правило MariaDB)
INNODB_LOG_FILE_SIZE=$((INNODB_BUFFER_POOL_SIZE * 25 / 100))

# 10% от RAM для key_buffer_size (MyISAM таблицы)
KEY_BUFFER_SIZE=$((TOTAL_RAM_MB * 1 / 10))

# Минимальные ограничения (в MB)
if [ $INNODB_BUFFER_POOL_SIZE -lt 1024 ]; then
    INNODB_BUFFER_POOL_SIZE=1024
fi

if [ $INNODB_LOG_FILE_SIZE -lt 512 ]; then
    INNODB_LOG_FILE_SIZE=512
fi

if [ $KEY_BUFFER_SIZE -lt 128 ]; then
    KEY_BUFFER_SIZE=128
fi

echo ""
echo "# Оптимальные значения на основе доступной памяти контейнера"
echo "innodb_buffer_pool_size=${INNODB_BUFFER_POOL_SIZE}M"
echo "innodb_log_file_size=${INNODB_LOG_FILE_SIZE}M"
echo "key_buffer_size=${KEY_BUFFER_SIZE}M"
echo ""
