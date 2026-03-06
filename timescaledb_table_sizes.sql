-- Размеры гипертаблиц
SELECT 
    h.hypertable_schema AS schema_name,
    h.hypertable_name AS table_name,
    pg_size_pretty(s.total_bytes) AS total_size,
    pg_size_pretty(s.table_bytes) AS data_size,
    pg_size_pretty(s.index_bytes) AS index_size
FROM timescaledb_information.hypertables h
CROSS JOIN LATERAL hypertable_detailed_size(
    format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
) s
WHERE h.hypertable_schema = 'public' -- Укажите вашу схему
ORDER BY s.total_bytes DESC;

-- Размеры обычных таблиц
SELECT 
    n.nspname AS schema_name,
    c.relname AS table_name,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
    pg_size_pretty(pg_relation_size(c.oid)) AS data_size,
    pg_size_pretty(pg_indexes_size(c.oid)) AS index_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' -- Укажите вашу схему
  AND c.relkind = 'r'      -- Только обычные таблицы (relations)
  AND NOT EXISTS (         -- Исключаем гипертаблицы
      SELECT 1 
      FROM timescaledb_information.hypertables h 
      WHERE h.hypertable_schema = n.nspname 
        AND h.hypertable_name = c.relname
  )
  AND NOT EXISTS (         -- Исключаем внутренние чанки
      SELECT 1 
      FROM timescaledb_information.chunks ch 
      WHERE ch.chunk_schema = n.nspname 
        AND ch.chunk_name = c.relname
  )
ORDER BY pg_total_relation_size(c.oid) DESC;