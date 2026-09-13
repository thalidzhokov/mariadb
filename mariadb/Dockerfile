FROM mariadb:11.8

LABEL maintainer="Albert Thalidzhokov <thalidzhokov@gmail.com>"

# Аргументы для билда контейнера
ARG TERM=linux
ARG DEBIAN_FRONTEND=noninteractive
# Аргументы для создания пользователя debezium
ARG MARIADB_DATABASE
ARG MARIADB_DEBEZIUM_PASSWORD

# Обновляем список пакетов
RUN apt update -y

# Устанавливаем wget
RUN apt install wget -y 

# Устанавливаем curl
RUN apt install curl -y

# Устанавливаем fio
RUN apt install fio -y

# Устанавливаем percona-toolkit
RUN apt install percona-toolkit -y

# Проверяем пользователя
RUN whoami

# Скачиваем тюнер mysqltuner.pl
# RUN wget http://mysqltuner.pl/ -O mysqltuner.pl
RUN wget https://raw.githubusercontent.com/major/MySQLTuner-perl/master/mysqltuner.pl -O mysqltuner.pl

# Скачиваем basic_passwords.txt
RUN wget https://raw.githubusercontent.com/major/MySQLTuner-perl/master/basic_passwords.txt -O basic_passwords.txt

# Скачиваем vulnerabilities.csv
RUN wget https://raw.githubusercontent.com/major/MySQLTuner-perl/master/vulnerabilities.csv -O vulnerabilities.csv

# Запускаем тюнер в контейнере
# docker exec -i loc_es_mariadb bash -c 'perl ./mysqltuner.pl --user root --pass "$MARIADB_ROOT_PASSWORD" --noask'

# Копируем шаблон override.cnf в tmp
COPY override.cnf.template /tmp/override.cnf

# Копируем скрипты расчета параметров innodb_buffer_pool_size, innodb_log_file_size, key_buffer_size
COPY ./innodb_buffer_pool_size.sh ./innodb_buffer_pool_size.sh
RUN chmod +x ./innodb_buffer_pool_size.sh
# Вставляем рассчитанные параметры в конфиг
RUN bash ./innodb_buffer_pool_size.sh >> /tmp/override.cnf

# Копируем скрипты расчета параметров innodb_io_capacity, innodb_io_capacity_max
COPY ./innodb_io_capacity.sh ./innodb_io_capacity.sh
RUN chmod +x ./innodb_io_capacity.sh
# Этот конфиг не применяем

# Копируем скрипты расчета параметров innodb_io_capacity, innodb_io_capacity_max на основе FIO теста
COPY ./innodb_io_capacity_by_fio.sh ./innodb_io_capacity_by_fio.sh
RUN chmod +x ./innodb_io_capacity_by_fio.sh
# Вставляем рассчитанные параметры в конфиг
RUN bash ./innodb_io_capacity_by_fio.sh >> /tmp/override.cnf

# Копируем финальный override.cnf в /etc/mysql/mariadb.conf.d/09-override.cnf
RUN cp /tmp/override.cnf /etc/mysql/mariadb.conf.d/09-override.cnf

# Проверяем наличие переменных окружения
RUN if [ -z "$MARIADB_DEBEZIUM_PASSWORD" ]; then \
        echo "ОШИБКА! Пароль для пользователя debezium не установлен."; \
        exit 1; \
    fi

# Копируем скрипт healthcheck.sh
COPY ./scripts/healthcheck.sh ./scripts/healthcheck.sh
RUN chmod +x ./scripts/healthcheck.sh

# Копируем скрипт create.sh
COPY ./scripts/create.sh ./scripts/create.sh
RUN chmod +x ./scripts/create.sh

# Копируем скрипт export.sh
COPY ./scripts/export.sh ./scripts/export.sh
RUN chmod +x ./scripts/export.sh

# Копируем скрипт drop.sh
COPY ./scripts/drop.sh ./scripts/drop.sh
RUN chmod +x ./scripts/drop.sh

# Копируем скрипт import.sh
COPY ./scripts/import.sh ./scripts/import.sh
RUN chmod +x ./scripts/import.sh

# Копируем скрипт recreate.sh
COPY ./scripts/recreate.sh ./scripts/recreate.sh
RUN chmod +x ./scripts/recreate.sh

# Копируем скрипт create-debezium-user.sh
COPY ./scripts/create-debezium-user.sh ./scripts/create-debezium-user.sh
RUN chmod +x ./scripts/create-debezium-user.sh

# Копируем скрипт upgrade.sh для обновления системных таблиц
COPY ./scripts/upgrade.sh ./scripts/upgrade.sh
RUN chmod +x ./scripts/upgrade.sh

# Копируем скрипт optimize.sh для оптимизации таблиц
COPY ./scripts/optimize.sh ./scripts/optimize.sh
RUN chmod +x ./scripts/optimize.sh

# Копируем скрипт benchmark.sh для бенчмарков базы данных
COPY ./scripts/benchmark.sh ./scripts/benchmark.sh
RUN chmod +x ./scripts/benchmark.sh

# Копируем скрипт diagnose-load.sh для диагностики деградации под нагрузкой
COPY ./scripts/diagnose-load.sh ./scripts/diagnose-load.sh
RUN chmod +x ./scripts/diagnose-load.sh

# Копируем шаблон создания пользователя debezium и подставляем переменные
COPY ./init-templates/z0-debezium-user.sql.template /tmp/z0-debezium-user.sql.template

# Подставляем переменные в шаблон и создаем финальный initdb скрипт
RUN sed \
    -e "s/\${MARIADB_DATABASE}/${MARIADB_DATABASE}/g" \
    -e "s/\${MARIADB_DEBEZIUM_PASSWORD}/${MARIADB_DEBEZIUM_PASSWORD}/g" \
    /tmp/z0-debezium-user.sql.template > /docker-entrypoint-initdb.d/z0-debezium-user.sql
