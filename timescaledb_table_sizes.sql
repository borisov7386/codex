-- =============================================================================
-- TimescaleDB: размеры таблиц и гипертаблиц
-- Версия: TimescaleDB 2.18+
-- Сортировка: сначала обычные таблицы, затем гипертаблицы (по убыванию размера)
-- Столбец columnstore: для гипертаблиц показывает статус сжатия (Columnstore)
--   Источник: timescaledb_information.hypertables.compression_enabled
-- =============================================================================


-- =============================================================================
-- ВАРИАНТ 1: Конкретная схема (замените 'public' на нужную)
-- =============================================================================
WITH table_stats AS (
    -- Обычные таблицы
    SELECT
        n.nspname AS schema_name,
        c.relname AS table_name,
        'table'   AS table_type,
        1         AS type_order,
        pg_total_relation_size(c.oid) AS total_bytes,
        pg_relation_size(c.oid)       AS data_bytes,
        pg_indexes_size(c.oid)        AS index_bytes,
        NULL::boolean                 AS compression_enabled
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND NOT EXISTS (
          SELECT 1
          FROM timescaledb_information.hypertables h
          WHERE h.hypertable_schema = n.nspname
            AND h.hypertable_name   = c.relname
      )
      AND NOT EXISTS (
          SELECT 1
          FROM timescaledb_information.chunks ch
          WHERE ch.chunk_schema = n.nspname
            AND ch.chunk_name   = c.relname
      )

    UNION ALL

    -- Гипертаблицы
    SELECT
        h.hypertable_schema AS schema_name,
        h.hypertable_name   AS table_name,
        'hypertable'        AS table_type,
        2                   AS type_order,
        COALESCE(s.total_bytes, 0) AS total_bytes,
        COALESCE(s.table_bytes, 0) AS data_bytes,
        COALESCE(s.index_bytes, 0) AS index_bytes,
        h.compression_enabled      AS compression_enabled
    FROM timescaledb_information.hypertables h
    CROSS JOIN LATERAL hypertable_detailed_size(
        format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
    ) s
    WHERE h.hypertable_schema = 'public'
)
SELECT
    schema_name,
    table_name,
    table_type,
    pg_size_pretty(total_bytes) AS total_size,
    pg_size_pretty(data_bytes)  AS data_size,
    pg_size_pretty(index_bytes) AS index_size,
    CASE
        WHEN table_type = 'table'        THEN '—'
        WHEN compression_enabled = true  THEN '✓ включено'
        WHEN compression_enabled = false THEN '✗ выключено'
    END AS columnstore
FROM table_stats
ORDER BY
    type_order  ASC,
    total_bytes DESC;


-- =============================================================================
-- ВАРИАНТ 2: Все пользовательские схемы (системные схемы исключены)
-- =============================================================================
WITH table_stats AS (
    -- Обычные таблицы (все схемы, кроме системных)
    SELECT
        n.nspname AS schema_name,
        c.relname AS table_name,
        'table'   AS table_type,
        1         AS type_order,
        pg_total_relation_size(c.oid) AS total_bytes,
        pg_relation_size(c.oid)       AS data_bytes,
        pg_indexes_size(c.oid)        AS index_bytes,
        NULL::boolean                 AS compression_enabled
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN (
          'pg_catalog', 'information_schema',
          '_timescaledb_internal', '_timescaledb_config',
          '_timescaledb_catalog',  '_timescaledb_cache'
      )
      AND NOT EXISTS (
          SELECT 1
          FROM timescaledb_information.hypertables h
          WHERE h.hypertable_schema = n.nspname
            AND h.hypertable_name   = c.relname
      )
      AND NOT EXISTS (
          SELECT 1
          FROM timescaledb_information.chunks ch
          WHERE ch.chunk_schema = n.nspname
            AND ch.chunk_name   = c.relname
      )

    UNION ALL

    -- Гипертаблицы (все схемы, кроме системных)
    SELECT
        h.hypertable_schema AS schema_name,
        h.hypertable_name   AS table_name,
        'hypertable'        AS table_type,
        2                   AS type_order,
        COALESCE(s.total_bytes, 0) AS total_bytes,
        COALESCE(s.table_bytes, 0) AS data_bytes,
        COALESCE(s.index_bytes, 0) AS index_bytes,
        h.compression_enabled      AS compression_enabled
    FROM timescaledb_information.hypertables h
    CROSS JOIN LATERAL hypertable_detailed_size(
        format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
    ) s
    WHERE h.hypertable_schema NOT IN (
        '_timescaledb_internal', '_timescaledb_catalog',
        '_timescaledb_config',   '_timescaledb_cache'
    )
)
SELECT
    schema_name,
    table_name,
    table_type,
    pg_size_pretty(total_bytes) AS total_size,
    pg_size_pretty(data_bytes)  AS data_size,
    pg_size_pretty(index_bytes) AS index_size,
    CASE
        WHEN table_type = 'table'        THEN '—'
        WHEN compression_enabled = true  THEN '✓ включено'
        WHEN compression_enabled = false THEN '✗ выключено'
    END AS columnstore
FROM table_stats
ORDER BY
    type_order  ASC,
    total_bytes DESC;
