#!/bin/bash

# Автоматический расчет innodb_io_capacity на основе FIO

set -euo pipefail

# Шаг 1: Запуск FIO теста для измерения случайного чтения 4KB блоков
# Этот тест имитирует типичную нагрузку InnoDB и извлекаем среднее значение IOPS
READ_IOPS=$(fio --name=random-read-4k \
    --ioengine=libaio \
    --iodepth=32 \
    --rw=randread \
    --bs=4k \
    --direct=1 \
    --size=1G \
    --numjobs=1 \
    --runtime=30 \
    --group_reporting \
    --filename=/tmp/iops_test_by_fio 2>/dev/null | grep 'iops.*avg' | sed 's/.*avg=\([0-9.]*\).*/\1/')

# Конвертируем в целое число
READ_IOPS=$(printf "%.0f" "$READ_IOPS")


# Проверяем что получили валидное значение IOPS
if [ -z "$READ_IOPS" ] || [ "$READ_IOPS" -eq 0 ]; then
    echo "# ОШИБКА! Не удалось измерить IOPS"
    exit 1
fi

# Расчет innodb_io_capacity
# Логика расчета:
# 1. Используем 33% от измеренных IOPS
# 2. Оставляем запас производительности для пиковых нагрузок
INNODB_IO_CAPACITY=$((READ_IOPS / 3))

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
echo "# Полный результат тестирования см. в файле /tmp/iops_test_by_fio"
echo "# Измеренные IOPS (случайное чтение 4KB): $READ_IOPS"

# Диагностика типа диска на основе IOPS
if [ $READ_IOPS -lt 1000 ]; then
    echo "# ВНИМАНИЕ! Производительность диска низкая"
elif [ $READ_IOPS -lt 10000 ]; then
    echo "# НОРМАЛЬНО! Производительность диска средняя"
elif [ $READ_IOPS -lt 50000 ]; then
    echo "# ХОРОШО! Производительность диска высокая"
else
    echo "# СУПЕР! Производительность диска очень высокая"
fi

echo ""
echo "# Значения для конфигурации MariaDB my.cnf"
echo "innodb_io_capacity=${INNODB_IO_CAPACITY}"
echo "innodb_io_capacity_max=${INNODB_IO_CAPACITY_MAX}"
