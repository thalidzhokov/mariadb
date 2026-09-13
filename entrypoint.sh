#!/bin/bash

# Обертка поверх штатного энтрипоинта MariaDB.
# Параметры, зависящие от ресурсов хоста, считаются при запуске контейнера
# и складываются в отдельный конфиг, а не вшиваются в образ при сборке.

set -eo pipefail

AUTOTUNE_CNF="/etc/mysql/conf.d/95-autotune.cnf"

autotune() {
    if [ "${MARIADB_AUTOTUNE:-1}" = "0" ]; then
        echo "[autotune] расчет отключен через MARIADB_AUTOTUNE=0"
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
        if [ "${MARIADB_AUTOTUNE_IO:-1}" != "0" ]; then
            bash /autotune/io-capacity-fio.sh
        fi
    } > "$tmp"; then
        echo "[autotune] расчет не удался, применяются значения по умолчанию"
        rm -f "$tmp"
        return 0
    fi

    install -m 0644 "$tmp" "$AUTOTUNE_CNF"
    rm -f "$tmp"

    echo "[autotune] параметры записаны в $AUTOTUNE_CNF"
    grep -E '^[a-z_]+=' "$AUTOTUNE_CNF" || true
}

if [ "${1:0:1}" = "-" ]; then
    set -- mariadbd "$@"
fi

if [ "$1" = "mariadbd" ] || [ "$1" = "mysqld" ]; then
    autotune
fi

exec docker-entrypoint.sh "$@"
