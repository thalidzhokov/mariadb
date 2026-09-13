#!/bin/bash

# Выбор innodb_flush_neighbors по типу диска тома данных.
# На HDD (= rotational) соседние dirty-страницы сбрасывать выгодно,
# на SSD/NVMe — лишняя работа. Ручной оверрайд: MARIADB_INNODB_FLUSH_NEIGHBORS.
#
# queue/rotational у виртуальных дисков часто врёт (Docker Desktop на Windows:
# Msft/Virtual Disk с rotational=1 поверх NVMe хоста). Это не tmpfs/ramfs,
# а VHDX на блочном устройстве — rotational перепроверяем по vendor/model.

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

fstype_for_path() {
    local path="$1"

    if ! command -v findmnt > /dev/null; then
        return 1
    fi
    findmnt -n -o FSTYPE -T "$path" 2>/dev/null || true
}

# Блок-устройство тома DATADIR: maj:min → /sys, с подъёмом к родителю у разделов.
sysfs_block_dir_for_path() {
    local path="$1"
    local maj_min sysdev dir

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
        if [ -d "${dir}/queue" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

rotational_for_path() {
    local path="$1"
    local dir rotational

    dir="$(sysfs_block_dir_for_path "$path" || true)"
    if [ -z "$dir" ] || [ ! -r "${dir}/queue/rotational" ]; then
        return 1
    fi

    rotational="$(tr -d '[:space:]' < "${dir}/queue/rotational")"
    case "$rotational" in
        0|1)
            echo "$rotational"
            return 0
            ;;
    esac
    return 1
}

# vendor|model блочного устройства; пусто, если sysfs недоступен.
disk_identity_for_path() {
    local path="$1"
    local dir vendor model

    dir="$(sysfs_block_dir_for_path "$path" || true)"
    if [ -z "$dir" ]; then
        return 1
    fi

    vendor=""
    model=""
    if [ -r "${dir}/device/vendor" ]; then
        vendor="$(tr -d '[:space:]' < "${dir}/device/vendor")"
    fi
    if [ -r "${dir}/device/model" ]; then
        model="$(tr -s '[:space:]' ' ' < "${dir}/device/model")"
        model="${model# }"
        model="${model% }"
    fi

    if [ -z "$vendor" ] && [ -z "$model" ]; then
        return 1
    fi
    echo "${vendor}|${model}"
}

# Docker Desktop / Hyper-V: Msft "Virtual Disk" почти всегда врёт rotational=1.
# QEMU/virtio не трогаем: за ними бывает настоящий HDD.
is_untrusted_virtual_disk() {
    local identity="$1"
    local vendor model
    local vendor_lc model_lc

    vendor="${identity%%|*}"
    model="${identity#*|}"
    vendor_lc="$(printf '%s' "$vendor" | tr '[:upper:]' '[:lower:]')"
    model_lc="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"

    case "$vendor_lc" in
        msft|microsoft)
            case "$model_lc" in
                *virtual*disk*)
                    return 0
                    ;;
            esac
            ;;
    esac
    return 1
}

FSTYPE="$(fstype_for_path "$DATADIR" || true)"
ROTATIONAL="$(rotational_for_path "$DATADIR" || true)"
IDENTITY="$(disk_identity_for_path "$DATADIR" || true)"

case "$FSTYPE" in
    tmpfs|ramfs|ramdisk)
        VALUE=0
        REASON="файловая система ${FSTYPE} (память) для ${DATADIR}, считаем SSD"
        ;;
    *)
        if [ "$ROTATIONAL" = "0" ]; then
            VALUE=0
            REASON="SSD/NVMe (rotational=0) для ${DATADIR}"
        elif [ "$ROTATIONAL" = "1" ]; then
            if [ -n "$IDENTITY" ] && is_untrusted_virtual_disk "$IDENTITY"; then
                VALUE=0
                REASON="rotational=1, но виртуальный диск (${IDENTITY}), rotational ненадёжен, считаем SSD для ${DATADIR}"
            else
                VALUE=1
                REASON="HDD (rotational=1) для ${DATADIR}"
                if [ -n "$IDENTITY" ]; then
                    REASON="${REASON} [${IDENTITY}]"
                fi
            fi
        else
            # Не определили тип (overlay, нет /sys) — как SSD
            VALUE=0
            REASON="тип диска для ${DATADIR} не определен, считаем SSD"
        fi
        ;;
esac

echo ""
echo "# ${REASON}"
echo "innodb_flush_neighbors=${VALUE}"
