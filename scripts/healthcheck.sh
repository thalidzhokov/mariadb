#!/bin/bash

# Healthcheck для MariaDB - проверка пользователей и состояния базы данных

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

: "${MARIADB_HEALTHCHECK_TABLE:=}"
: "${MARIADB_HEALTHCHECK_INDEX:=}"

# root
# Все проверки связанные с пользователем делаются под пользователем
# Проверяем наличие переменной окружения MARIADB_ROOT_PASSWORD
if [ -z "$MARIADB_ROOT_PASSWORD" ]; then
    echo "[error] Переменная окружения MARIADB_ROOT_PASSWORD не установлена"
    exit 1
else
    echo "[ok] Переменная окружения MARIADB_ROOT_PASSWORD установлена"
fi

# Проверка подключения под root пользователем
if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
    echo "[error] Неправильный пароль root пользователя"
    exit 1
else
    echo "[ok] Пользователь root доступен"
fi

# MARIADB_USER
# Проверяем наличие переменной окружения MARIADB_USER
if [ -z "$MARIADB_USER" ]; then
    echo "[error] Переменная окружения MARIADB_USER не установлена"
    exit 1
else
    echo "[ok] Переменная окружения MARIADB_USER установлена"
fi

# Проверяем наличие переменной окружения MARIADB_PASSWORD
if [ -z "$MARIADB_PASSWORD" ]; then
    echo "[error] Переменная окружения MARIADB_PASSWORD не установлена"
    exit 1
else
    echo "[ok] Переменная окружения MARIADB_PASSWORD установлена"
fi

# Проверка подключения под MARIADB_USER пользователем
if ! mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
    echo "[error] Неправильный пароль $MARIADB_USER пользователя"
    exit 1
else
    echo "[ok] Пользователь $MARIADB_USER доступен"
fi

# Проверка прав MARIADB_USER пользователя на доступ к базе данных
if ! mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" -e "USE $MARIADB_DATABASE; SELECT 1" >/dev/null 2>&1; then
    echo "[error] Пользователь $MARIADB_USER не имеет доступа к базе данных $MARIADB_DATABASE"
    exit 1
else
    echo "[ok] Пользователь $MARIADB_USER имеет доступ к базе данных $MARIADB_DATABASE"
fi




# debezium
# Пользователь debezium необязателен, поэтому проверки выполняются
# только когда задан MARIADB_DEBEZIUM_PASSWORD
if [ -z "$MARIADB_DEBEZIUM_PASSWORD" ]; then
    echo "[skip] Переменная окружения MARIADB_DEBEZIUM_PASSWORD не установлена"
else
    echo "[ok] Переменная окружения MARIADB_DEBEZIUM_PASSWORD установлена"

    # Проверка подключения под debezium пользователем
    if ! mariadb -u debezium -p"$MARIADB_DEBEZIUM_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
        echo "[error] Неправильный пароль debezium пользователя"
        exit 1
    else
        echo "[ok] Пользователь debezium доступен"
    fi

    # Проверяем права debezium пользователя на SELECT
    if ! mariadb -u debezium -p"$MARIADB_DEBEZIUM_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$MARIADB_DATABASE'" >/dev/null 2>&1; then
        echo "[error] Пользователь debezium не имеет прав SELECT на базу данных $MARIADB_DATABASE"
        exit 1
    else
        echo "[ok] Пользователь debezium имеет права SELECT"
    fi

    # Проверяем права debezium пользователя на RELOAD.
    # FLUSH PRIVILEGES требует того же права, но не ротирует бинлоги, как FLUSH LOGS
    if ! mariadb -u debezium -p"$MARIADB_DEBEZIUM_PASSWORD" -e "FLUSH PRIVILEGES" >/dev/null 2>&1; then
        echo "[error] Пользователь debezium не имеет права RELOAD"
        exit 1
    else
        echo "[ok] Пользователь debezium имеет права RELOAD"
    fi

    # Проверяем права debezium пользователя на REPLICATION SLAVE
    if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SHOW GRANTS FOR 'debezium'@'%'" 2>/dev/null | grep -qi "REPLICATION SLAVE"; then
        echo "[error] Пользователь debezium не имеет права REPLICATION SLAVE"
        exit 1
    else
        echo "[ok] Пользователь debezium имеет права REPLICATION SLAVE"
    fi

    # Проверяем права debezium пользователя на REPLICATION CLIENT (в MariaDB 10.11+ это BINLOG MONITOR)
    if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SHOW GRANTS FOR 'debezium'@'%'" 2>/dev/null | grep -qi "BINLOG MONITOR\|REPLICATION CLIENT"; then
        echo "[error] Пользователь debezium не имеет права REPLICATION CLIENT/BINLOG MONITOR"
        exit 1
    else
        echo "[ok] Пользователь debezium имеет права REPLICATION CLIENT/BINLOG MONITOR"
    fi

    # Проверка binary logging
    if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SHOW VARIABLES LIKE 'log_bin'" 2>/dev/null | grep -qi "ON"; then
        echo "[error] Binary logging не включен"
        exit 1
    else
        echo "[ok] Binary logging включен"
    fi

    # Проверка формата binary log
    if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SHOW VARIABLES LIKE 'binlog_format'" 2>/dev/null | grep -qi "ROW"; then
        echo "[error] Binary log format не установлен в ROW"
        exit 1
    else
        echo "[ok] Binary log format установлен в ROW"
    fi

    # Проверка GTID настроек для MariaDB
    if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e "SHOW VARIABLES LIKE 'gtid_strict_mode'" 2>/dev/null | grep -qi "ON"; then
        echo "[error] GTID strict mode не включен"
        exit 1
    else
        echo "[ok] GTID strict mode включен"
    fi
fi

# MARIADB_DATABASE
# Проверка переменной MARIADB_DATABASE
if [ -z "$MARIADB_DATABASE" ]; then
    echo "[error] Переменная окружения MARIADB_DATABASE не установлена"
    exit 1
else
    echo "[ok] Переменная окружения MARIADB_DATABASE установлена"
fi

# Проверка существования базы данных MARIADB_DATABASE.
# Не SHOW DATABASES LIKE + grep: у LIKE заголовок колонки — Database (pattern),
# имя попадает в вывод даже при нуле строк.
db_exists="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -N -s -e \
    "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$MARIADB_DATABASE'" 2>/dev/null || true)"
if [ "${db_exists:-0}" -eq 1 ]; then
    echo "[ok] База данных $MARIADB_DATABASE существует"
else
    echo "[error] База данных $MARIADB_DATABASE не существует"
    exit 1
fi

# Проверка существования таблицы если указана MARIADB_HEALTHCHECK_TABLE
if [ -z "$MARIADB_HEALTHCHECK_TABLE" ]; then
    echo "[skip] Переменная окружения MARIADB_HEALTHCHECK_TABLE не установлена"
else
    echo "[ok] Переменная окружения MARIADB_HEALTHCHECK_TABLE установлена"

    # Не SHOW TABLES LIKE + grep: заголовок Tables_in_<db> (pattern) даёт ложный ok
    table_exists="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -N -s -e \
        "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$MARIADB_DATABASE' AND TABLE_NAME = '$MARIADB_HEALTHCHECK_TABLE'" 2>/dev/null || true)"
    if [ "${table_exists:-0}" -eq 1 ]; then
        echo "[ok] Таблица $MARIADB_HEALTHCHECK_TABLE существует"

        # Проверяем что у таблицы MARIADB_HEALTHCHECK_TABLE есть индекс MARIADB_HEALTHCHECK_INDEX.
        # Имя первичного ключа в MariaDB всегда PRIMARY, вторичные индексы называются как заданы
        if [ -z "$MARIADB_HEALTHCHECK_INDEX" ]; then
            echo "[skip] Переменная окружения MARIADB_HEALTHCHECK_INDEX не установлена"
        else
            echo "[ok] Переменная окружения MARIADB_HEALTHCHECK_INDEX установлена"

            index_exists="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -N -s -e \
                "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$MARIADB_DATABASE' AND TABLE_NAME = '$MARIADB_HEALTHCHECK_TABLE' AND INDEX_NAME = '$MARIADB_HEALTHCHECK_INDEX'" 2>/dev/null || true)"
            if [ "${index_exists:-0}" -ge 1 ]; then
                echo "[ok] У таблицы $MARIADB_HEALTHCHECK_TABLE есть индекс $MARIADB_HEALTHCHECK_INDEX"
            else
                echo "[error] У таблицы $MARIADB_HEALTHCHECK_TABLE нет индекса $MARIADB_HEALTHCHECK_INDEX"
                exit 1
            fi
        fi
    else
        echo "[error] Таблица $MARIADB_HEALTHCHECK_TABLE не существует в базе данных $MARIADB_DATABASE"
        exit 1
    fi
fi

# ASCII арт вам в лог!
echo "

-+++++*++=+++++--=+-=++++*++=+-+*++-#++*=+*++*#++++*+=++=*+++%-=+=%==+*
=++++++*++++++-+=*-*+++*++#-+-=*=+-+#+*==+=++**+=+**#*-=*=#++-#+===#*=+
=++++-*==++++-+=+-*++*+%=#===++===+#=+==+*=*+**===+#***+-+=#+-+#++=***+
++++===-+++=-++==#+++*%#+#==##*+-=*#-=+*#+=*#=*+++++*#**+=-+**=***++#**
++=+=+-=+++=+++=*%++##%%*#=+%=#+=+**-**%#++**-%+++*+*%*+%++=**++*%#*#*#
+=*++===++-+++++%#+*##%##%+##%##+**#**%%#=#**-##+****#*+*%+**+*#**%%%**
+=++++-++-=++*+%%%+*%%%##%#%##*%*%*#%*%%%+*++-*#**###*#*=#%%%**%#+%%%@%
=#++++=+==+++*%%%%%%%%%%%%%%%%####*##+%%%%#+*--##%%*%*#*+*%#%#%%%%%%%%#
=%#%++=+-+++*#%%%%%%%%%*#%###**###%%%**%%*#+*-:**%%%*#**#%%#%#+##*#%%@@
*%%%++===+++#%%%%%%@#==-::=::::-+###**#%%*#+*--=-%%%*%%*+*%#*=-:...+-::
%%%%*+==+++*%#+%%%=+#%---:*=::-*+*%:**+#%+#++-=:-+%%+%++#=:-+-::=*=+#.:
%%%%#+==+*+*%%*%%#:+===*=::-=++==:-::-:+%:=+*-=:--%%+#*++==:=====+=:---
%%%%%*==+#+#%#*%%*::=:::::::::::::::::::#:--:=:-::#%=-=::::::::::::::::
%%%%%%+=+%+#%#*#%#::::::::::::::::::::::--:-:-:-:::%+:=-:::::::::::::::
%%%%%%*=+%*#%#**%%-::::::::::::::::::::::::::+=--:::*::::=+::::::::::::
%%%%%%%+*%##%#+*#%*::::::::::::::::::::::::::*=:+:::=:::::::++:::::::-*
%%%%%%%%*%##%%%#*%#+::::::::::::::::::::::::-#=-+=::::::::::::-*=:::+*+
%%%%%%%%%%%#%%%%%%#++:::::::::::::::::::::::*#=-++-:::::::::::::-*++#++
%%%%%%%%%%%#%%%%%%%%%-::::::::::::::::::::::##+-++-::::::::::::::-++#++
%%%%%%%%%%%%%%%%%%%%%@=::::::::::::::::::::::*+:*:::::::::::::::=**+*#*
#%%%%%%%%%%%%%%%%%%%%%%*.:::::::::::::::::::::-::::::::::::::::+*+++++#
*#%%%%%%%%%%%%%%%%%%%%%%@+:::::::::::::::::::::::::::::::::::=**+++++%%
#-@%%#%%%%%%%%%%%%%%%%%%%%@=:::::::::::::::::::::::::::::::-**+++++#%%%
:=.#%+*%%%%%%%%%%%%%%%%%%%%%%=::::::::::::::::**-:::::::::+#+++++#%%%%%
::::+%:=%%%%%%%%*%%%%%%%%%%%%%#+::::::::::::::::::::::::=#+++++*%%%%%%%
::::::*:-%##%%%%@=*%#%%%%%%%%%#+**.:::::::::::::::::::-#+++++#++%%%%%%%
::::------=*=%%#*#+=%+#%*%%%%%#=*+**::::::::::::::::=*++++*#+++*%%%%%%%
::::--------=-#%+#-==*#=@*%%%%#:-+++*#+.::::::::::+*++++#*+++++#%%%#@%#
::::::--------=-*-=====-:*+=%%#::=++++**#-:::::::=+++##*+++++++#%##%###
============++=--:::::=++****#*:::++++++***#=:::++#***+++++++++########
########=-:::=***++#*::-*++++++::::+++++++**********+++++++++++**++*%+#
=-=*-::=**+++*#%%%+++++*-.+**+::::::++++++++++++++++++++++:+++++#+%++%%
=:-**++***#%%%%%+++++++++*-:=-:::::::+++++++++++++++++++*=:+++++*+=%%%%

"

# Если все проверки прошли успешно, то запускаем тюнер.
# Пароль отдаем файлом, а не через --pass: иначе он виден в списке процессов
echo "# Все проверки прошли успешно! Запускаем тюнер..."
TUNER_CNF="$(mktemp)"
chmod 600 "$TUNER_CNF"
printf "[client]\nuser=root\npassword=%s\n" "$MARIADB_ROOT_PASSWORD" > "$TUNER_CNF"
perl /mysqltuner.pl --defaults-file="$TUNER_CNF" --noask
rm -f "$TUNER_CNF"

