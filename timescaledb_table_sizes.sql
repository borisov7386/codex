-- =============================================================================
-- TimescaleDB: размеры таблиц и гипертаблиц
-- Версия: TimescaleDB 2.18+
-- Сортировка: сначала обычные таблицы, затем гипертаблицы (по убыванию размера)
--
-- Столбцы:
--   total_size              — полный размер таблицы (индексы + все чанки)
--   data_size               — heap-данные (без индексов)
--   index_size              — индексы
--   columnstore             — включено ли сжатие (только для гипертаблиц)
--   chunk_interval          — интервал партиционирования
--   uncompressed_chunks     — физический размер несжатых чанков на диске
--   compressed_chunks       — физический размер сжатых чанков на диске
--   before_compression_size — каким был бы размер сжатых чанков без сжатия
--   after_compression_size  — сколько сжатые чанки занимают сейчас
--   compression_ratio       — before / after
-- =============================================================================


-- =============================================================================
-- ВАРИАНТ 1: Все схемы — БЕЗ подсчёта строк (быстро)
-- =============================================================================
WITH
hyper_chunk_sizes AS (
    SELECT
        hypertable_schema,
        hypertable_name,
        SUM(CASE WHEN compressed_total_size = 0 THEN total_bytes        ELSE 0 END) AS uncompressed_chunks_bytes,
        SUM(CASE WHEN compressed_total_size > 0 THEN compressed_total_size ELSE 0 END) AS compressed_chunks_bytes
    FROM _timescaledb_internal.hypertable_chunk_local_size
    GROUP BY hypertable_schema, hypertable_name
),
table_stats AS (
    -- Обычные таблицы
    SELECT
        n.nspname  AS schema_name,
        c.relname  AS table_name,
        'table'    AS table_type,
        1          AS type_order,
        pg_total_relation_size(c.oid) AS total_bytes,
        pg_relation_size(c.oid)       AS data_bytes,
        pg_indexes_size(c.oid)        AS index_bytes,
        NULL::boolean  AS compression_enabled,
        NULL::interval AS chunk_interval,
        NULL::bigint   AS uncompressed_chunks_bytes,
        NULL::bigint   AS compressed_chunks_bytes,
        NULL::bigint   AS before_compression_bytes,
        NULL::bigint   AS after_compression_bytes
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN (
          'pg_catalog', 'information_schema',
          '_timescaledb_internal', '_timescaledb_config',
          '_timescaledb_catalog',  '_timescaledb_cache'
      )
      AND NOT EXISTS (
          SELECT 1 FROM timescaledb_information.hypertables h
          WHERE h.hypertable_schema = n.nspname AND h.hypertable_name = c.relname
      )
      AND NOT EXISTS (
          SELECT 1 FROM timescaledb_information.chunks ch
          WHERE ch.chunk_schema = n.nspname AND ch.chunk_name = c.relname
      )

    UNION ALL

    -- Гипертаблицы
    SELECT
        h.hypertable_schema AS schema_name,
        h.hypertable_name   AS table_name,
        'hypertable'        AS table_type,
        2                   AS type_order,
        COALESCE(s.total_bytes, 0)  AS total_bytes,
        COALESCE(s.table_bytes, 0)  AS data_bytes,
        COALESCE(s.index_bytes, 0)  AS index_bytes,
        h.compression_enabled       AS compression_enabled,
        d.time_interval             AS chunk_interval,
        COALESCE(ch.uncompressed_chunks_bytes, 0) AS uncompressed_chunks_bytes,
        COALESCE(ch.compressed_chunks_bytes,   0) AS compressed_chunks_bytes,
        cs.before_compression_total_bytes         AS before_compression_bytes,
        cs.after_compression_total_bytes          AS after_compression_bytes
    FROM timescaledb_information.hypertables h
    CROSS JOIN LATERAL hypertable_detailed_size(
        format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
    ) s
    LEFT JOIN LATERAL (
        SELECT time_interval
        FROM timescaledb_information.dimensions d
        WHERE d.hypertable_schema = h.hypertable_schema
          AND d.hypertable_name   = h.hypertable_name
          AND d.dimension_number  = 1
        LIMIT 1
    ) d ON true
    LEFT JOIN hyper_chunk_sizes ch
        ON ch.hypertable_schema = h.hypertable_schema
       AND ch.hypertable_name   = h.hypertable_name
    LEFT JOIN LATERAL (
        SELECT
            before_compression_total_bytes,
            after_compression_total_bytes
        FROM hypertable_compression_stats(
            format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
        )
        LIMIT 1
    ) cs ON true
    WHERE h.hypertable_schema NOT IN (
        '_timescaledb_internal', '_timescaledb_catalog',
        '_timescaledb_config',   '_timescaledb_cache'
    )
)
SELECT
    schema_name,
    table_name,
    table_type,
    pg_size_pretty(total_bytes)             AS total_size,
    pg_size_pretty(data_bytes)              AS data_size,
    pg_size_pretty(index_bytes)             AS index_size,
    CASE
        WHEN table_type = 'table'        THEN '—'
        WHEN compression_enabled = true  THEN '✓ включено'
        WHEN compression_enabled = false THEN '✗ выключено'
    END                                     AS columnstore,
    COALESCE(chunk_interval::text, '—')     AS chunk_interval,
    CASE WHEN table_type = 'hypertable'
        THEN pg_size_pretty(uncompressed_chunks_bytes)
        ELSE '—' END                        AS uncompressed_chunks,
    CASE WHEN table_type = 'hypertable'
        THEN pg_size_pretty(compressed_chunks_bytes)
        ELSE '—' END                        AS compressed_chunks,
    COALESCE(pg_size_pretty(before_compression_bytes), '—') AS before_compression_size,
    COALESCE(pg_size_pretty(after_compression_bytes),  '—') AS after_compression_size,
    CASE
        WHEN after_compression_bytes > 0
        THEN round(before_compression_bytes::numeric / after_compression_bytes::numeric, 2)::text || 'x'
        ELSE '—'
    END                                     AS compression_ratio
FROM table_stats
ORDER BY type_order ASC, total_bytes DESC;


-- =============================================================================
-- ВАРИАНТ 2: Все схемы — С точным подсчётом строк через count_rows()
--
-- Требует функции:
--   CREATE OR REPLACE FUNCTION count_rows(schema_name text, table_name text)
--   RETURNS bigint LANGUAGE plpgsql AS $$
--   DECLARE result bigint;
--   BEGIN
--     EXECUTE format('SELECT COUNT(*) FROM %I.%I', schema_name, table_name)
--     INTO result;
--     RETURN result;
--   END; $$;
--
-- ВНИМАНИЕ: выполняется дольше — COUNT(*) по каждой таблице
-- =============================================================================
WITH
hyper_chunk_sizes AS (
    SELECT
        hypertable_schema,
        hypertable_name,
        SUM(CASE WHEN compressed_total_size = 0 THEN total_bytes        ELSE 0 END) AS uncompressed_chunks_bytes,
        SUM(CASE WHEN compressed_total_size > 0 THEN compressed_total_size ELSE 0 END) AS compressed_chunks_bytes
    FROM _timescaledb_internal.hypertable_chunk_local_size
    GROUP BY hypertable_schema, hypertable_name
),
table_stats AS (
    -- Обычные таблицы
    SELECT
        n.nspname  AS schema_name,
        c.relname  AS table_name,
        'table'    AS table_type,
        1          AS type_order,
        pg_total_relation_size(c.oid) AS total_bytes,
        pg_relation_size(c.oid)       AS data_bytes,
        pg_indexes_size(c.oid)        AS index_bytes,
        NULL::boolean  AS compression_enabled,
        NULL::interval AS chunk_interval,
        count_rows(n.nspname, c.relname) AS row_count,
        NULL::bigint   AS uncompressed_chunks_bytes,
        NULL::bigint   AS compressed_chunks_bytes,
        NULL::bigint   AS before_compression_bytes,
        NULL::bigint   AS after_compression_bytes
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN (
          'pg_catalog', 'information_schema',
          '_timescaledb_internal', '_timescaledb_config',
          '_timescaledb_catalog',  '_timescaledb_cache'
      )
      AND NOT EXISTS (
          SELECT 1 FROM timescaledb_information.hypertables h
          WHERE h.hypertable_schema = n.nspname AND h.hypertable_name = c.relname
      )
      AND NOT EXISTS (
          SELECT 1 FROM timescaledb_information.chunks ch
          WHERE ch.chunk_schema = n.nspname AND ch.chunk_name = c.relname
      )

    UNION ALL

    -- Гипертаблицы
    SELECT
        h.hypertable_schema AS schema_name,
        h.hypertable_name   AS table_name,
        'hypertable'        AS table_type,
        2                   AS type_order,
        COALESCE(s.total_bytes, 0)  AS total_bytes,
        COALESCE(s.table_bytes, 0)  AS data_bytes,
        COALESCE(s.index_bytes, 0)  AS index_bytes,
        h.compression_enabled       AS compression_enabled,
        d.time_interval             AS chunk_interval,
        count_rows(h.hypertable_schema, h.hypertable_name) AS row_count,
        COALESCE(ch.uncompressed_chunks_bytes, 0) AS uncompressed_chunks_bytes,
        COALESCE(ch.compressed_chunks_bytes,   0) AS compressed_chunks_bytes,
        cs.before_compression_total_bytes         AS before_compression_bytes,
        cs.after_compression_total_bytes          AS after_compression_bytes
    FROM timescaledb_information.hypertables h
    CROSS JOIN LATERAL hypertable_detailed_size(
        format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
    ) s
    LEFT JOIN LATERAL (
        SELECT time_interval
        FROM timescaledb_information.dimensions d
        WHERE d.hypertable_schema = h.hypertable_schema
          AND d.hypertable_name   = h.hypertable_name
          AND d.dimension_number  = 1
        LIMIT 1
    ) d ON true
    LEFT JOIN hyper_chunk_sizes ch
        ON ch.hypertable_schema = h.hypertable_schema
       AND ch.hypertable_name   = h.hypertable_name
    LEFT JOIN LATERAL (
        SELECT
            before_compression_total_bytes,
            after_compression_total_bytes
        FROM hypertable_compression_stats(
            format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
        )
        LIMIT 1
    ) cs ON true
    WHERE h.hypertable_schema NOT IN (
        '_timescaledb_internal', '_timescaledb_catalog',
        '_timescaledb_config',   '_timescaledb_cache'
    )
)
SELECT
    schema_name,
    table_name,
    table_type,
    to_char(row_count, 'FM999,999,999,999') AS row_count,
    pg_size_pretty(total_bytes)             AS total_size,
    pg_size_pretty(data_bytes)              AS data_size,
    pg_size_pretty(index_bytes)             AS index_size,
    CASE
        WHEN table_type = 'table'        THEN '—'
        WHEN compression_enabled = true  THEN '✓ включено'
        WHEN compression_enabled = false THEN '✗ выключено'
    END                                     AS columnstore,
    COALESCE(chunk_interval::text, '—')     AS chunk_interval,
    CASE WHEN table_type = 'hypertable'
        THEN pg_size_pretty(uncompressed_chunks_bytes)
        ELSE '—' END                        AS uncompressed_chunks,
    CASE WHEN table_type = 'hypertable'
        THEN pg_size_pretty(compressed_chunks_bytes)
        ELSE '—' END                        AS compressed_chunks,
    COALESCE(pg_size_pretty(before_compression_bytes), '—') AS before_compression_size,
    COALESCE(pg_size_pretty(after_compression_bytes),  '—') AS after_compression_size,
    CASE
        WHEN after_compression_bytes > 0
        THEN round(before_compression_bytes::numeric / after_compression_bytes::numeric, 2)::text || 'x'
        ELSE '—'
    END                                     AS compression_ratio
FROM table_stats
ORDER BY type_order ASC, total_bytes DESC;
