#!/bin/bash

# Обертка поверх штатного энтрипоинта MariaDB.
# Параметры, зависящие от ресурсов хоста, считаются при запуске контейнера
# и складываются в отдельный конфиг, а не вшиваются в образ при сборке.
# Пользователь debezium создается в том же проходе, что и MARIADB_USER:
# после docker_setup_db, пока поднят временный сервер первой инициализации.

set -eo pipefail

AUTOTUNE_CNF="/etc/mysql/conf.d/95-autotune.cnf"
# Ниже порога floors раздували pool/redo выше лимита cgroup — не тюним
AUTOTUNE_MIN_MB="${MARIADB_AUTOTUNE_MIN_MB:-512}"

# Иначе прошлый 95-autotune.cnf остаётся и продолжает задавать параметры
clear_autotune_cnf() {
    local reason="$1"
    if [ -e "$AUTOTUNE_CNF" ]; then
        if rm -f "$AUTOTUNE_CNF"; then
            echo "[autotune] ${reason}, удален $AUTOTUNE_CNF"
        else
            echo "[autotune] ${reason}, но $AUTOTUNE_CNF не удален (нет прав)"
        fi
    else
        echo "[autotune] ${reason}"
    fi
}

autotune() {
    if [ "${MARIADB_AUTOTUNE:-1}" = "0" ]; then
        clear_autotune_cnf "расчет отключен через MARIADB_AUTOTUNE=0"
        return 0
    fi

    local total_mb
    total_mb="$(bash /autotune/memory.sh --limit-only)"
    if [ "$total_mb" -lt "$AUTOTUNE_MIN_MB" ]; then
        clear_autotune_cnf "доступно ${total_mb}M < ${AUTOTUNE_MIN_MB}M, расчет пропущен (серверные дефолты)"
        return 0
    fi

    if [ ! -w "$(dirname "$AUTOTUNE_CNF")" ]; then
        echo "[autotune] $(dirname "$AUTOTUNE_CNF") недоступен на запись, расчет пропущен"
        return 0
    fi

    local tmp
    tmp="$(mktemp)"

    # Файл с именем 95- читается раньше 99-override.cnf, а любой
    # пользовательский файл с буквенным именем в conf.d переопределяет оба
    if ! {
        echo "# Файл создается при каждом запуске контейнера, правки не сохраняются"
        echo "[mysqld]"
        bash /autotune/memory.sh
        bash /autotune/flush-neighbors.sh
        if [ "${MARIADB_AUTOTUNE_IO:-1}" != "0" ]; then
            bash /autotune/io-capacity-fio.sh
        fi
    } > "$tmp"; then
        rm -f "$tmp"
        clear_autotune_cnf "расчет не удался, применяются значения по умолчанию"
        return 0
    fi

    install -m 0644 "$tmp" "$AUTOTUNE_CNF"
    rm -f "$tmp"

    echo "[autotune] параметры записаны в $AUTOTUNE_CNF"
    grep -E '^[a-z_]+=' "$AUTOTUNE_CNF" || true
}

create_debezium_user_on_init() {
    # file_env штатного энтрипоинта: разворачивает MARIADB_DEBEZIUM_PASSWORD_FILE
    file_env 'MARIADB_DEBEZIUM_PASSWORD'
    if [ -z "${MARIADB_DEBEZIUM_PASSWORD:-}" ]; then
        echo "# MARIADB_DEBEZIUM_PASSWORD не задан, создание пользователя debezium пропущено"
        return 0
    fi
    bash /scripts/create-debezium-user.sh
}

if [ "${1:0:1}" = "-" ]; then
    set -- mariadbd "$@"
fi

if [ "$1" = "mariadbd" ] || [ "$1" = "mysqld" ]; then
    autotune
fi

# shellcheck source=/dev/null
source /usr/local/bin/docker-entrypoint.sh

# Штатный _main после gosu делает exec "${BASH_SOURCE[0]}", а это путь к
# файлу, где определена функция, то есть к оригинальному docker-entrypoint.sh.
# Подменяем на $0, иначе повторный запуск от mysql идет без наших обёрток.
eval "$(declare -f _main | sed 's/\${BASH_SOURCE\[0\]}/\$0/')"

# Переименовываем штатную функцию и вызываем debezium сразу после нее,
# пока временный сервер первой инициализации еще работает
eval "$(declare -f docker_setup_db | sed '1s/^docker_setup_db/docker_setup_db_original/')"

docker_setup_db() {
    docker_setup_db_original "$@"
    create_debezium_user_on_init
}

_main "$@"
