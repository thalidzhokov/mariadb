# mariadb

Образ MariaDB поверх официального `mariadb` с расчетом параметров под ресурсы
контейнера, скриптами обслуживания и диагностикой.

Что добавлено к базовому образу:

- расчет `innodb_buffer_pool_size`, `innodb_log_file_size`, `key_buffer_size`,
  `max_connections`, `innodb_io_capacity` и `innodb_flush_neighbors` при запуске
  контейнера, а не при сборке образа;
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
запустить `docker compose up -d`. В compose подключен `init/test_init.sql`:
таблица `test_table` с данными и индексом `idx_test_table_name`, на нее же в
`.env` настроены `MARIADB_HEALTHCHECK_TABLE` и `MARIADB_HEALTHCHECK_INDEX`.
Файлы из `/docker-entrypoint-initdb.d` выполняются один раз, при первой
инициализации тома, в базе `MARIADB_DATABASE`.

На томе, созданном образом без пользователей healthcheck, нужен
`MARIADB_AUTO_UPGRADE=1`: именно он их создает. Без него `HEALTHCHECK`
контейнера остается в состоянии `health: starting`, хотя сервер работает.

Теги: `11.8` и `latest`. Архитектуры: `linux/amd64`, `linux/arm64`.

## Переменные окружения

Базовый образ поддерживает все свои переменные (`MARIADB_ROOT_PASSWORD`,
`MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD`, `MARIADB_AUTO_UPGRADE`
и остальные), включая варианты с суффиксом `_FILE` для docker secrets.
Энтрипоинт разворачивает `_FILE` только в своем процессе, поэтому скрипты
обслуживания читают файлы сами через `scripts/env.sh`: для
`MARIADB_ROOT_PASSWORD`, `MARIADB_DATABASE`, `MARIADB_USER`, `MARIADB_PASSWORD`
и `MARIADB_DEBEZIUM_PASSWORD`. Дополнительно:

| Переменная | По умолчанию | Назначение |
| --- | --- | --- |
| `MARIADB_DEBEZIUM_PASSWORD` | не задана | Пароль пользователя `debezium`, есть вариант `_FILE`. Пока не задана, пользователь не создается |
| `MARIADB_AUTOTUNE` | `1` | `0` отключает расчет параметров целиком |
| `MARIADB_AUTOTUNE_MIN_MB` | `512` | Ниже этого лимита cgroup (МБ) расчет не выполняется, остается конфиг сервера. Рекомендуемый минимум для образа |
| `MARIADB_AUTOTUNE_IO` | `1` | `0` отключает замер IOPS через fio |
| `MARIADB_BUFFER_POOL_PERCENT` | `60` | Доля доступной памяти под buffer pool |
| `MARIADB_KEY_BUFFER_SIZE_MB` | `32` | `key_buffer_size` в мегабайтах |
| `MARIADB_AUTOTUNE_FIO_RUNTIME` | `30` | Длительность замера IOPS в секундах |
| `MARIADB_AUTOTUNE_FIO_FORCE` | не задана | Повторить замер IOPS, игнорируя кеш |
| `MARIADB_INNODB_FLUSH_NEIGHBORS` | авто | `0` / `1` / `2` — ручной `innodb_flush_neighbors`. Без переменной: SSD/NVMe/`Msft Virtual Disk`/tmpfs → `0`, HDD → `1` |
| `MARIADB_DUMP_DIR` | `/mariadb-dump` | Каталог для дампов |
| `MARIADB_HEALTHCHECK_TABLE` | не задана | Таблица, наличие которой проверяет `scripts/healthcheck.sh` |
| `MARIADB_HEALTHCHECK_INDEX` | не задана | Имя индекса в этой таблице, у первичного ключа это всегда `PRIMARY` |

Свои переменные используют тот же префикс `MARIADB_`, что и базовый образ,
поэтому при обновлении базы возможны пересечения имен.

## Расчет параметров

Параметры считаются при каждом запуске и складываются в
`/etc/mysql/conf.d/95-autotune.cnf`.

Память берется из лимита cgroup контейнера, а не из `/proc/meminfo`: внутри
контейнера `MemTotal` показывает память хоста, поэтому расчет от него дает
завышенные значения. Если лимит меньше `MARIADB_AUTOTUNE_MIN_MB` (по
умолчанию 512M), расчет не выполняется: удаляется прежний
`95-autotune.cnf`, сервер идет на своих дефолтах. У образа включены
performance_schema, бинлоги и slow log — для продакшена лучше не ставить
`mem_limit` ниже 512M, комфортнее от 1G.

Под buffer pool отводится 60% лимита, под redo log четверть buffer pool,
нижние границы равны серверным дефолтам (срабатывают только когда расчет
уже идет при лимите ≥ порога).

`max_connections` считается от остатка после buffer pool: половина остатка
делится на 8M, столько по `99-override.cnf` может занять одно соединение.
Результат ограничен снизу 50 и сверху 250. Без лимита памяти у контейнера
расчет идет от памяти хоста, поэтому на разделяемом хосте стоит задать
`mem_limit` в compose.

IOPS замеряются fio при первом запуске на томе данных: случайная запись блоком
16K, поскольку `innodb_io_capacity` ограничивает именно фоновую запись
страниц. Результат кешируется в `/var/lib/mysql/.autotune-io-capacity`, так что
повторные запуски проходят без замера. `innodb_io_capacity` берется как треть
измеренных IOPS, `innodb_io_capacity_max` не опускается ниже серверного
дефолта 2000.

`innodb_flush_neighbors` выбирается по `queue/rotational` устройства тома
данных: на SSD/NVMe (`0`), tmpfs/ramfs и когда тип не определился — `0`.
При `rotational=1` значение перепроверяется: диск `Msft`/`Virtual Disk`
(Docker Desktop на Windows — VHDX, не RAM, часто врёт `rotational`)
считаем SSD и ставим `0`. Иначе оставляем сброс соседей для HDD. Значение
можно задать явно через `MARIADB_INNODB_FLUSH_NEIGHBORS`:

- `0` — сбрасывать только нужную грязную страницу (SSD/NVMe);
- `1` — ещё непрерывных соседей рядом (обычно достаточно для HDD);
- `2` — всех грязных страниц из того же extent (агрессивно, почти не нужен).

Порядок чтения конфигов: `/etc/mysql/conf.d/` подключается после
`/etc/mysql/mariadb.conf.d/`, поэтому `95-autotune.cnf` и `99-override.cnf`
переопределяют пакетный `50-server.cnf`. Любой смонтированный в `conf.d` файл
с именем на букву читается последним и переопределяет оба.

## Скрипты

Запускаются из корня контейнера, напр. `docker exec -t mariadb bash scripts/export.sh`.

| Скрипт | Назначение |
| --- | --- |
| `create.sh` | Создать базу и пользователя, обновить его пароль |
| `drop.sh` | Удалить базу |
| `export.sh` | Дамп в `latest_<день недели>.sql.gz` |
| `import.sh` | Импорт самого свежего дампа |
| `recreate.sh` | Удаление, создание, импорт последнего дампа, пользователь debezium. С `--export` сначала снимает свежий дамп |
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
`/mariadb-dump` создан в образе с этим владельцем, поэтому свежий named volume
наследует права и на хосте настраивать ничего не нужно.

Скрипты обслуживания запускаются через `docker exec`, то есть от root, поэтому
в bind mount дампы пишутся без подготовки прав, но остаются с владельцем
`root:root` и режимом 644. Если на хосте их забирает или ротирует
непривилегированный процесс, каталог стоит создать заранее с нужным владельцем:

```bash
install -d -o 999 -g 999 -m 750 /var/backups/myproject/mariadb
```

## Пользователь debezium

Создается при первой инициализации тома данных, если задан
`MARIADB_DEBEZIUM_PASSWORD`: энтрипоинт вызывает `scripts/create-debezium-user.sh`
сразу после штатного `docker_setup_db`, в том же проходе, что и `MARIADB_USER`.
Права: `SELECT`, `RELOAD`, `SHOW DATABASES`, `REPLICATION SLAVE`,
`BINLOG MONITOR`, `SLAVE MONITOR` глобально плюс `SELECT` и `LOCK TABLES` на
`MARIADB_DATABASE`.

На уже инициализированном томе создание не повторяется, поэтому для
существующей базы или после смены пароля нужно запустить скрипт вручную:

```bash
docker exec -t mariadb bash scripts/create-debezium-user.sh
```

## Сборка

```bash
docker build -t thalidzhokov/mariadb:11.8 .
docker build --build-arg MARIADB_VERSION=11.4 -t thalidzhokov/mariadb:11.4 .
```

## Проверка

`tests/run.sh` поднимает контейнер из собранного образа и проверяет
`HEALTHCHECK`, применение autotune, вход root и debezium по `*_FILE`, пароли с
кавычкой и слешем, экранирование `_` в `GRANT`, инициализацию из
`init/test_init.sql`, `scripts/healthcheck.sh` с проверкой таблицы и индекса и `recreate.sh` со сменой пароля. Контейнер и том удаляются
по завершении.

```bash
bash tests/run.sh thalidzhokov/mariadb:11.8
```

В CI тесты идут перед публикацией образа.
