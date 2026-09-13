#!/bin/bash

# Скрипт пересоздания базы данных.
# Запускается в контейнере mariadb.
# Пересоздает базу данных в контейнере.
# 
# Использование: bash scripts/recreate.sh [ОПЦИИ]
# 
# ОПЦИИ:
#   --export, -e  Сделать экспорт перед пересозданием
#   --help, -h    Показать справку
# 
# Примеры запуска:
#   В контейнере: bash scripts/recreate.sh
#   В контейнере с экспортом: bash scripts/recreate.sh --export
#   На хосте: docker exec -t mariadb bash scripts/recreate.sh
#   На хосте с экспортом: docker exec -t mariadb bash scripts/recreate.sh --export

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# Функция помощи
show_help() {
    echo "

Использование: $(basename "$0") [ОПЦИИ]

Скрипт пересоздания базы данных MariaDB.

ОПЦИИ:
  --export, -e  Сделать экспорт перед пересозданием
  --help, -h    Показать эту справку и выйти

ПРИМЕРЫ:
  $(basename "$0")           # Пересоздать БД из последнего дампа
  $(basename "$0") --export  # Сначала сделать свежий дамп
  $(basename "$0") -e        # То же самое, короткий флаг

ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ:
  MARIADB_DATABASE           - Имя базы данных
  MARIADB_ROOT_PASSWORD      - Пароль root пользователя
  MARIADB_USER               - Имя пользователя БД
  MARIADB_PASSWORD           - Пароль пользователя БД
  MARIADB_DUMP_DIR           - Каталог для дампов (по умолчанию: /mariadb-dump)
  MARIADB_DEBEZIUM_PASSWORD  - Пароль debezium, без него шаг 4 пропускается
  
"
}

# Обработка аргументов командной строки
EXPORT=false

for arg in "$@"; do
    case $arg in
        --help|-h)
            show_help
            exit 0
            ;;
        --export|-e)
            EXPORT=true
            ;;
        *)
            echo "ОШИБКА: Неизвестный аргумент: $arg"
            echo "Используйте --help для получения справки"
            exit 1
            ;;
    esac
done

echo "# Пересоздаем базу данных..."

# Получаем директорию текущего скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 0. Создаем экспорт базы данных, если указан флаг --export или -e.
# По умолчанию экспорта нет: после смены MARIADB_PASSWORD дамп под новым
# паролем не снять, а импорт идет из последнего имеющегося latest_*.sql.gz
if [ "$EXPORT" = true ]; then
    echo "# 0."

    # Если создание экспорта завершилось с ошибкой, то выходим
    bash "$SCRIPT_DIR/export.sh" || {
        echo "# ОШИБКА: При создании экспорта базы данных!"
        exit 1
    }
fi

# 1. Удаляем базу данных
echo "# 1."

# Если удаление базы данных завершилось с ошибкой, то выходим
bash "$SCRIPT_DIR/drop.sh" || {
    echo "# ОШИБКА: При удалении базы данных!"
    exit 1
}

# 2. Создаем базу данных
echo "# 2."

# Если создание базы данных завершилось с ошибкой, то выходим
bash "$SCRIPT_DIR/create.sh" || {
    echo "# ОШИБКА: При создании базы данных!"
    exit 1
}

# 3. Импортируем базу данных
echo "# 3."

# Если импорт базы данных завершилось с ошибкой, то выходим
bash "$SCRIPT_DIR/import.sh" || {
    echo "# ОШИБКА: При импорте базы данных!"
    exit 1
}

# 4. Создаем пользователя debezium, если задан его пароль
if [ -n "${MARIADB_DEBEZIUM_PASSWORD:-}" ]; then
    echo "# 4."

    # Если создание пользователя debezium завершилось с ошибкой, то выходим
    bash "$SCRIPT_DIR/create-debezium-user.sh" || {
        echo "# ОШИБКА: При создании пользователя debezium!"
        exit 1
    }
fi

echo "# Пересоздание базы данных завершено!"
