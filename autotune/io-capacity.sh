#!/bin/bash

# Автоматический расчет innodb_io_capacity на основе dd теста

set -euo pipefail

# Шаг 1: Запуск dd теста, извлекаем скорость записи на диск
DD_OUTPUT=$(dd if=/dev/zero of=/tmp/iops_test bs=4K count=10000 oflag=direct 2>&1)

# Шаг 2: Извлекаем строку со скоростью в цифрах и единицах измерения (пропускная способность диска)
SPEED_LINE=$(echo "$DD_OUTPUT" | grep -o '[0-9.]\+ [TGMK]B/s')

# Шаг 3: Извлекаем число из строки скорости
THROUGHPUT=$(echo "$SPEED_LINE" | awk '{print $1}')

# Шаг 4: Извлекаем единицы измерения из строки скорости
UNITS=$(echo "$SPEED_LINE" | awk '{print $2}')

# Шаг 5: Конвертируем в MB/s
if [ "$UNITS" = "TB/s" ]; then
    # TB/s -> MB/s
    THROUGHPUT_MB=$(echo "$THROUGHPUT * 1024 * 1024" | bc -l)
elif [ "$UNITS" = "GB/s" ]; then
    # GB/s -> MB/s
    THROUGHPUT_MB=$(echo "$THROUGHPUT * 1024" | bc -l)
elif [ "$UNITS" = "MB/s" ]; then
    # MB/s -> MB/s
    THROUGHPUT_MB=$THROUGHPUT
elif [ "$UNITS" = "KB/s" ]; then
    # KB/s -> MB/s
    THROUGHPUT_MB=$(echo "$THROUGHPUT / 1024" | bc -l)
else
    # B/s -> MB/s
    THROUGHPUT_MB=$(echo "$THROUGHPUT / 1024 / 1024" | bc -l)
fi

# Шаг 6: Конвертируем в целое число для bash арифметики
THROUGHPUT_INT=${THROUGHPUT_MB%.*}

# Расчет innodb_io_capacity
# Логика расчета:
# 1. IOPS = THROUGHPUT_MB/s * 256 блоков/MB (т.к. 1MB = 256 блоков по 4KB)
# 2. innodb_io_capacity = IOPS * 25% = IOPS / 4 (консервативный подход)
# 3. Объединяем: innodb_io_capacity = (THROUGHPUT * 256) / 4 = THROUGHPUT * 64
# 
# Коэффициент 64 означает: "возьми 64 блока 4KB из каждого MB/s пропускной способности
# Это эквивалентно 25% от максимальных IOPS диска
INNODB_IO_CAPACITY=$((THROUGHPUT_INT * 64))

# Максимальное значение (2x от базового)
INNODB_IO_CAPACITY_MAX=$((INNODB_IO_CAPACITY * 2))

# Минимальные значения для безопасности
if [ $INNODB_IO_CAPACITY -lt 200 ]; then
    INNODB_IO_CAPACITY=200
fi

if [ $INNODB_IO_CAPACITY_MAX -lt 400 ]; then
    INNODB_IO_CAPACITY_MAX=400
fi

echo ""
echo "# Оптимальные значения на основе производительности диска"
echo "innodb_io_capacity=${INNODB_IO_CAPACITY}"
echo "innodb_io_capacity_max=${INNODB_IO_CAPACITY_MAX}"
echo ""
