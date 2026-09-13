#!/bin/bash

# Скрипт для оптимизации всех таблиц в базе данных MARIADB_DATABASE.
# Запускается в контейнере mariadb.
# Выполняет OPTIMIZE TABLE для всех таблиц в указанной базе данных.
# Запуск в контейнере командой: bash scripts/optimize.sh
# Запуск на хосте, напр., для локального окружения, командой: docker exec -t loc_es_mariadb bash scripts/optimize.sh

set -euo pipefail

echo "# Запускаем оптимизацию таблиц базы данных..."

# Проверяем наличие переменных окружения
if [ -z "$MARIADB_DATABASE" ]; then
    echo "ОШИБКА: Переменная MARIADB_DATABASE не установлена!"
    exit 1
fi

if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "ОШИБКА: Переменная MARIADB_ROOT_PASSWORD не установлена!"
    exit 1
fi

# Проверяем подключение к базе данных
if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "USE $MARIADB_DATABASE; SELECT 1" > /dev/null 2>&1; then
    echo "ОШИБКА: Не удается подключиться к базе данных $MARIADB_DATABASE!"
    exit 1
fi

echo "# Подключение к базе данных $MARIADB_DATABASE успешно. ОК!"

# Получаем список всех таблиц в базе данных
echo "# Получаем список таблиц..."
TABLES=$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -D "$MARIADB_DATABASE" -e "SHOW TABLES" -s --skip-column-names)

if [ -z "$TABLES" ]; then
    echo "# В базе данных $MARIADB_DATABASE нет таблиц для оптимизации"
    exit 0
fi

# Подсчитываем количество таблиц
TABLE_COUNT=$(echo "$TABLES" | wc -l)
echo "# Найдено таблиц для оптимизации: $TABLE_COUNT"

# Оптимизируем каждую таблицу
CURRENT=0
OPTIMIZED=0
FAILED=0

echo "# Начинаем оптимизацию таблиц..."

while IFS= read -r table; do
    CURRENT=$((CURRENT + 1))
    echo "# [$CURRENT/$TABLE_COUNT] Оптимизируем таблицу: $table"
    
    # Выполняем OPTIMIZE TABLE
    RESULT=$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -D "$MARIADB_DATABASE" -e "OPTIMIZE TABLE \`$table\`" 2>&1)
    
    if [ $? -eq 0 ]; then
        # Примеры результата оптимизации
        # 1.
        # Table   Op      Msg_type        Msg_text
        # wp_db.wp_term_taxonomy  optimize        status  Table is already up to date
        # 2.
        # Table   Op      Msg_type        Msg_text
        # wp_db.wp_commentmeta    optimize        note    Table does not support optimize, doing recreate + analyze instead
        # Table   Op      Msg_type        Msg_text
        # wp_db.wp_commentmeta    optimize        status  OK      

        # Проверяем результат оптимизации
        if echo "$RESULT" | grep -q "OK\|Table is already up to date"; then
            echo "# Таблица $table оптимизирована успешно. ОК!"
            OPTIMIZED=$((OPTIMIZED + 1))
        else
            echo "# ВНИМАНИЕ!Таблица $table: $(echo "$RESULT" | grep "$table" | awk '{print $4}')"
        fi
    else
        echo "# ОШИБКА! При оптимизации таблицы $table: $RESULT"
        FAILED=$((FAILED + 1))
    fi
done <<< "$TABLES"

echo "# Оптимизация завершена!"
echo "# Статистика:"
echo "# - Всего таблиц: $TABLE_COUNT"
echo "# - Оптимизировано: $OPTIMIZED"
echo "# - Ошибок: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo "# Все таблицы оптимизированы успешно! ОК!"
else
    echo "# ВНИМАНИЕ! Некоторые таблицы не удалось оптимизировать!"
    exit 1
fi
