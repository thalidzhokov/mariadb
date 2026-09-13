#!/bin/bash

# Скрипт пересоздания базы данных.
# Запускается в контейнере mariadb.
# Пересоздает базу данных в контейнере.
# 
# Использование: bash scripts/recreate.sh [ОПЦИИ]
# 
# ОПЦИИ:
#   --no-export, -ne  Пропустить создание экспорта перед пересозданием
#   --help, -h        Показать справку
# 
# Примеры запуска:
#   В контейнере: bash scripts/recreate.sh
#   В контейнере без экспорта: bash scripts/recreate.sh --no-export
#   На хосте, напр., для локального окружения: docker exec -t loc_es_mariadb bash scripts/recreate.sh
#   На хосте без экспорта, напр., для локального окружения: docker exec -t loc_es_mariadb bash scripts/recreate.sh --no-export

set -euo pipefail

# Функция помощи
show_help() {
    echo "

Использование: $(basename "$0") [ОПЦИИ]

Скрипт пересоздания базы данных MariaDB.

ОПЦИИ:
  --no-export, -ne  Пропустить создание экспорта перед пересозданием
  --help, -h        Показать эту справку и выйти

ПРИМЕРЫ:
  $(basename "$0")              # Пересоздать БД с созданием экспорта
  $(basename "$0") --no-export  # Пересоздать БД без экспорта
  $(basename "$0") -ne          # То же самое, короткий флаг

ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ:
  MARIADB_DATABASE      - Имя базы данных
  MARIADB_ROOT_PASSWORD - Пароль root пользователя
  MARIADB_USER          - Имя пользователя БД
  MARIADB_PASSWORD      - Пароль пользователя БД
  
"
}

# Обработка аргументов командной строки
NO_EXPORT=false

for arg in "$@"; do
    case $arg in
        --help|-h)
            show_help
            exit 0
            ;;
        --no-export|-ne)
            NO_EXPORT=true
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

# 0. Создаем экспорт базы данных, если не указан флаг --no-export или -ne
if [ "$NO_EXPORT" = false ]; then
    echo "# 0."
    bash "$SCRIPT_DIR/export.sh"

    # Если создание экспорта завершилось с ошибкой, то выходим
    if [ $? -ne 0 ]; then
        echo "# ОШИБКА: При создании экспорта базы данных!"
        exit 1
    fi
fi

# 1. Удаляем базу данных
echo "# 1."
bash "$SCRIPT_DIR/drop.sh"

# Если удаление базы данных завершилось с ошибкой, то выходим
if [ $? -ne 0 ]; then
    echo "# ОШИБКА: При удалении базы данных!"
    exit 1
fi

# 2. Создаем базу данных
echo "# 2."
bash "$SCRIPT_DIR/create.sh"

# Если создание базы данных завершилось с ошибкой, то выходим
if [ $? -ne 0 ]; then
    echo "# ОШИБКА: При создании базы данных!"
    exit 1
fi

# 3. Импортируем базу данных
echo "# 3."
bash "$SCRIPT_DIR/import.sh"

# Если импорт базы данных завершилось с ошибкой, то выходим
if [ $? -ne 0 ]; then
    echo "# ОШИБКА: При импорте базы данных!"
    exit 1
fi

# 4. Создаем пользователя debezium
echo "# 4."
bash "$SCRIPT_DIR/create-debezium-user.sh"

# Если создание пользователя debezium завершилось с ошибкой, то выходим
if [ $? -ne 0 ]; then
    echo "# ОШИБКА: При создании пользователя debezium!"
    exit 1
fi

echo "# Пересоздание базы данных завершено!"
