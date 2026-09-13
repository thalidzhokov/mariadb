# mariadb

Образ MariaDB поверх официального `mariadb` с расчетом параметров под ресурсы
контейнера, скриптами обслуживания и диагностикой.

Что добавлено к базовому образу:

- расчет `innodb_buffer_pool_size`, `innodb_log_file_size`, `key_buffer_size` и
  `innodb_io_capacity` при запуске контейнера, а не при сборке образа;
- конфиг с настройками бинлогов, slow log и performance_schema;
- опциональный пользователь `debezium` с правами для CDC;
- скрипты экспорта, импорта, пересоздания, оптимизации, бенчмарка и диагностики
  нагрузки;
- fio, percona-toolkit и MySQLTuner внутри образа.

## Запуск

```bash
docker run -d --name mariadb \
  -e MARIADB_ROOT_PASSWORD=secret \
  -e MARIADB_DATABASE=app_db \
  -e MARIADB_USER=app \
  -e MARIADB_PASSWORD=apppass \
  -v mariadb-data:/var/lib/mysql \
  thalidzhokov/mariadb:11.8
```

Через compose: скопировать `docker-compose.yml` и `.env`, заменить пароли,
запустить `docker compose up -d`.

На томе, созданном образом без пользователей healthcheck, нужен
`MARIADB_AUTO_UPGRADE=1`: именно он их создает. Без него `HEALTHCHECK`
контейнера остается в состоянии `health: starting`, хотя сервер работает.

Теги: `11.8` и `latest`. Архитектуры: `linux/amd64`, `linux/arm64`.

## Переменные окружения

Базовый образ поддерживает все свои переменные (`MARIADB_ROOT_PASSWORD`,
`MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD`, `MARIADB_AUTO_UPGRADE`
и остальные), включая варианты с суффиксом `_FILE` для docker secrets.
Дополнительно:

| Переменная | По умолчанию | Назначение |
| --- | --- | --- |
| `MARIADB_DEBEZIUM_PASSWORD` | не задана | Пароль пользователя `debezium`. Пока не задана, пользователь не создается |
| `MARIADB_AUTOTUNE` | `1` | `0` отключает расчет параметров целиком |
| `MARIADB_AUTOTUNE_IO` | `1` | `0` отключает замер IOPS через fio |
| `MARIADB_BUFFER_POOL_PERCENT` | `60` | Доля доступной памяти под buffer pool |
| `MARIADB_KEY_BUFFER_SIZE_MB` | `32` | `key_buffer_size` в мегабайтах |
| `MARIADB_AUTOTUNE_FIO_RUNTIME` | `30` | Длительность замера IOPS в секундах |
| `MARIADB_AUTOTUNE_FIO_FORCE` | не задана | Повторить замер IOPS, игнорируя кеш |
| `MARIADB_DUMP_DIR` | `/var/www/dump` | Каталог для дампов |
| `MARIADB_HEALTHCHECK_TABLE` | не задана | Таблица, наличие которой проверяет `scripts/healthcheck.sh` |
| `MARIADB_HEALTHCHECK_PRIMARY_KEY` | не задана | PRIMARY KEY, наличие которого проверяется в этой таблице |

Свои переменные используют тот же префикс `MARIADB_`, что и базовый образ,
поэтому при обновлении базы возможны пересечения имен.

## Расчет параметров

Параметры считаются при каждом запуске и складываются в
`/etc/mysql/conf.d/95-autotune.cnf`.

Память берется из лимита cgroup контейнера, а не из `/proc/meminfo`: внутри
контейнера `MemTotal` показывает память хоста, поэтому расчет от него дает
завышенные значения. Под buffer pool отводится 60% лимита, под redo log
четверть buffer pool, нижние границы равны серверным дефолтам.

IOPS замеряются fio при первом запуске на томе данных: случайная запись блоком
16K, поскольку `innodb_io_capacity` ограничивает именно фоновую запись
страниц. Результат кешируется в `/var/lib/mysql/.autotune-io-capacity`, так что
повторные запуски проходят без замера. `innodb_io_capacity` берется как треть
измеренных IOPS, `innodb_io_capacity_max` не опускается ниже серверного
дефолта 2000.

Порядок чтения конфигов: `/etc/mysql/conf.d/` подключается после
`/etc/mysql/mariadb.conf.d/`, поэтому `95-autotune.cnf` и `99-override.cnf`
переопределяют пакетный `50-server.cnf`. Любой смонтированный в `conf.d` файл
с именем на букву читается последним и переопределяет оба.

## Скрипты

Запускаются из корня контейнера, напр. `docker exec -t mariadb bash scripts/export.sh`.

| Скрипт | Назначение |
| --- | --- |
| `create.sh` | Создать базу и пользователя |
| `drop.sh` | Удалить базу |
| `export.sh` | Дамп в `latest_<день недели>.sql.gz` |
| `import.sh` | Импорт самого свежего дампа |
| `recreate.sh` | Экспорт, удаление, создание, импорт, пользователь debezium |
| `create-debezium-user.sh` | Создать или обновить пользователя `debezium` |
| `upgrade.sh` | `mariadb-upgrade` системных таблиц |
| `optimize.sh` | `OPTIMIZE TABLE` по всем таблицам базы |
| `healthcheck.sh` | Полная проверка пользователей, прав, бинлогов и запуск MySQLTuner |
| `benchmark.sh` | Замеры через `mariadb-slap` с отчетами |
| `diagnose-load.sh` | Срезы processlist, блокировки, топ запросов, хвост slow log |

`HEALTHCHECK` самого образа использует штатный `healthcheck.sh` базового образа
с проверками `--connect --innodb_initialized`. Скрипт `scripts/healthcheck.sh`
выполняет полную проверку и рассчитан на запуск по требованию: MySQLTuner в нем
занимает около 15 секунд.

## Дампы и права

Пользователь сервера внутри контейнера имеет uid и gid 999. Каталог
`/var/www/dump` создан в образе с этим владельцем, поэтому свежий named volume
наследует права и на хосте настраивать ничего не нужно.

Для bind mount каталог нужно создать заранее и вне дерева проекта, иначе
`docker exec` от root оставит на хосте файлы, недоступные приложению:

```bash
install -d -o 999 -g 999 -m 750 /var/backups/myproject/mariadb
```

## Пользователь debezium

Создается при первой инициализации тома данных, если задан
`MARIADB_DEBEZIUM_PASSWORD`, так же как базовый образ создает `MARIADB_USER`.
Права: `SELECT`, `RELOAD`, `SHOW DATABASES`, `REPLICATION SLAVE`,
`BINLOG MONITOR`, `SLAVE MONITOR` глобально плюс `SELECT` и `LOCK TABLES` на
`MARIADB_DATABASE`.

На уже инициализированном томе initdb-скрипты не выполняются, поэтому для
существующей базы или после смены пароля нужно запустить скрипт вручную:

```bash
docker exec -t mariadb bash scripts/create-debezium-user.sh
```

## Сборка

```bash
docker build -t thalidzhokov/mariadb:11.8 .
docker build --build-arg MARIADB_VERSION=11.4 -t thalidzhokov/mariadb:11.4 .
```
