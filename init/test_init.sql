-- Тестовая таблица с данными и вторичным индексом.
-- Файлы из /docker-entrypoint-initdb.d выполняются один раз, при первой
-- инициализации тома, в базе MARIADB_DATABASE. На нее же смотрит
-- scripts/healthcheck.sh через MARIADB_HEALTHCHECK_TABLE и MARIADB_HEALTHCHECK_INDEX.

CREATE TABLE IF NOT EXISTS test_table (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(64) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_test_table_name (name)
) ENGINE = InnoDB;

INSERT INTO test_table (name, amount) VALUES
    ('alpha', 10.00),
    ('beta', 20.50),
    ('gamma', 30.25),
    ('delta', 40.00),
    ('epsilon', 50.75);
