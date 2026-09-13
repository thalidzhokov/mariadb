# syntax=docker/dockerfile:1

ARG MARIADB_VERSION=11.8
FROM mariadb:${MARIADB_VERSION}

ARG MARIADB_VERSION
ARG MYSQLTUNER_VERSION=v2.9.2
ARG DEBIAN_FRONTEND=noninteractive

LABEL maintainer="Albert Thalidzhokov <thalidzhokov@gmail.com>"
LABEL org.opencontainers.image.title="mariadb" \
      org.opencontainers.image.description="MariaDB с расчетом параметров под ресурсы контейнера, диагностикой и скриптами обслуживания" \
      org.opencontainers.image.source="https://github.com/thalidzhokov/mariadb" \
      org.opencontainers.image.base.name="docker.io/library/mariadb:${MARIADB_VERSION}"

# fio нужен для замера IOPS, percona-toolkit для pt-query-digest и pt-* диагностики
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        fio \
        percona-toolkit \
        wget \
    && rm -rf /var/lib/apt/lists/*

# MySQLTuner пинится тегом: с master сборка невоспроизводима
ADD --chmod=0644 https://raw.githubusercontent.com/major/MySQLTuner-perl/${MYSQLTUNER_VERSION}/mysqltuner.pl /mysqltuner.pl
ADD --chmod=0644 https://raw.githubusercontent.com/major/MySQLTuner-perl/${MYSQLTUNER_VERSION}/basic_passwords.txt /basic_passwords.txt
ADD --chmod=0644 https://raw.githubusercontent.com/major/MySQLTuner-perl/${MYSQLTUNER_VERSION}/vulnerabilities.csv /vulnerabilities.csv

# conf.d подключается после mariadb.conf.d, поэтому переопределяет пакетный 50-server.cnf
COPY config/99-override.cnf /etc/mysql/conf.d/99-override.cnf

# Расчет параметров выполняется при запуске контейнера: на сборке
# доступны ресурсы билд-машины, а не того хоста, где образ будет работать
COPY --chmod=0755 autotune/ /autotune/
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

COPY --chmod=0755 scripts/ /scripts/
COPY init-templates/ /init-templates/
COPY --chmod=0755 initdb.d/z0-debezium-user.sh /docker-entrypoint-initdb.d/z0-debezium-user.sh

# Владелец mysql, чтобы свежий named volume унаследовал права от образа
RUN mkdir -p /var/www/dump && chown mysql:mysql /var/www/dump

# Штатный healthcheck базового образа. Полная проверка прав и настроек
# вынесена в scripts/healthcheck.sh и запускается по требованию
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD healthcheck.sh --connect --innodb_initialized

ENTRYPOINT ["entrypoint.sh"]
CMD ["mariadbd"]
