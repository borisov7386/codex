-- TimescaleDB 2.18+ Columnstore Policy Cheatsheet

-- 1. Просмотр всех активных политик (Jobs) колоночного хранения
-- proc_name = 'policy_columnstore' — надёжный фильтр для 2.18+
SELECT * FROM timescaledb_information.jobs
WHERE proc_name = 'policy_columnstore';

-- 2. Настройки колоночного хранения для гипертаблиц
-- Показывает segmentby, orderby и прочие настройки
SELECT * FROM timescaledb_information.hypertable_columnstore_settings;

-- 3. Статистика колоночного хранения (размер до/после сжатия, коэффициент)
SELECT * FROM chunk_columnstore_stats('your_hypertable_name');

-- 4. Статус чанков (какие сконвертированы, а какие нет)
SELECT chunk_name, range_start::date, range_end::date,
       (range_end - range_start) AS interval,
       is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'your_hypertable_name'
ORDER BY range_end DESC;

-- 5. Chunk Skipping (sparse индекс по min/max значениям)
-- Позволяет полностью пропускать чанки по WHERE col = $1 без декомпрессии.
-- Важно: вызывать ДО convert_to_columnstore!
SELECT enable_chunk_skipping('your_hypertable_name', 'col_name');
-- Работает: WHERE col = $1 | WHERE col > $1 | WHERE col BETWEEN $1 AND $2
-- НЕ работает: WHERE col IN (...) | WHERE col IS NULL
