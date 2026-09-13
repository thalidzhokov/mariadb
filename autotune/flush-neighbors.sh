#!/bin/bash

# Выбор innodb_flush_neighbors по типу диска тома данных.
# На HDD (= rotational) соседние dirty-страницы сбрасывать выгодно,
# на SSD/NVMe — лишняя работа. Ручной оверрайд: MARIADB_INNODB_FLUSH_NEIGHBORS.

set -euo pipefail

DATADIR="${MARIADB_DATADIR:-/var/lib/mysql}"

# 0 / 1 / 2 — как у серверной переменной
if [ -n "${MARIADB_INNODB_FLUSH_NEIGHBORS:-}" ]; then
    case "${MARIADB_INNODB_FLUSH_NEIGHBORS}" in
        0|1|2)
            echo ""
            echo "# innodb_flush_neighbors задан через MARIADB_INNODB_FLUSH_NEIGHBORS"
            echo "innodb_flush_neighbors=${MARIADB_INNODB_FLUSH_NEIGHBORS}"
            exit 0
            ;;
        *)
            echo "# MARIADB_INNODB_FLUSH_NEIGHBORS=${MARIADB_INNODB_FLUSH_NEIGHBORS}: ожидается 0, 1 или 2, игнорируем" >&2
            ;;
    esac
fi

# queue/rotational у блочного устройства, на котором лежит DATADIR.
# У разделов атрибут лежит на родительском диске — поднимаемся по /sys.
rotational_for_path() {
    local path="$1"
    local maj_min sysdev dir rotational

    if ! command -v findmnt > /dev/null; then
        return 1
    fi

    maj_min="$(findmnt -n -o MAJ:MIN -T "$path" 2>/dev/null || true)"
    maj_min="${maj_min// /}"
    if [ -z "$maj_min" ] || [ "$maj_min" = "0:0" ]; then
        return 1
    fi

    sysdev="/sys/dev/block/${maj_min}"
    if [ ! -e "$sysdev" ]; then
        return 1
    fi

    dir="$(readlink -f "$sysdev")"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -r "${dir}/queue/rotational" ]; then
            rotational="$(tr -d '[:space:]' < "${dir}/queue/rotational")"
            case "$rotational" in
                0|1)
                    echo "$rotational"
                    return 0
                    ;;
            esac
            return 1
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

ROTATIONAL="$(rotational_for_path "$DATADIR" || true)"

if [ "$ROTATIONAL" = "1" ]; then
    VALUE=1
    REASON="HDD (rotational=1) для ${DATADIR}"
elif [ "$ROTATIONAL" = "0" ]; then
    VALUE=0
    REASON="SSD/NVMe (rotational=0) для ${DATADIR}"
else
    # Не определили тип (overlay, нет /sys, virtio без атрибута) — как SSD
    VALUE=0
    REASON="тип диска для ${DATADIR} не определен, считаем SSD"
fi

echo ""
echo "# ${REASON}"
echo "innodb_flush_neighbors=${VALUE}"
