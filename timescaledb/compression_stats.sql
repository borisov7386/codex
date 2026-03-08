-- =============================================================================
-- TimescaleDB 2.18+ | Статистика компрессии (Hypercore / Columnstore API)
-- Схема: замените 'your_schema' на нужную схему
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Агрегированная статистика по таблицам
--    Показывает объём ДО/ПОСЛЕ сжатия, экономию (МБ и %) и коэффициент сжатия
-- -----------------------------------------------------------------------------
SELECT
    h.hypertable_schema                                                         AS schema_name,
    h.hypertable_name                                                           AS table_name,
    COUNT(*)                                                                    AS compressed_chunks,
    -- Объём ДО компрессии
    ROUND(SUM(cs.before_compression_total_bytes) / 1024.0 / 1024.0, 2)        AS before_mb,
    -- Объём ПОСЛЕ компрессии
    ROUND(SUM(cs.after_compression_total_bytes)  / 1024.0 / 1024.0, 2)        AS after_mb,
    -- Сколько места сэкономлено (МБ)
    ROUND(
        (SUM(cs.before_compression_total_bytes)
         - SUM(cs.after_compression_total_bytes)) / 1024.0 / 1024.0, 2
    )                                                                           AS saved_mb,
    -- Эффективность: % сжатых данных
    ROUND(
        100.0 * (
            1 - SUM(cs.after_compression_total_bytes)::numeric
              / NULLIF(SUM(cs.before_compression_total_bytes), 0)
        ), 2
    )                                                                           AS saved_pct,
    -- Коэффициент сжатия (во сколько раз уменьшился объём)
    ROUND(
        SUM(cs.before_compression_total_bytes)::numeric
      / NULLIF(SUM(cs.after_compression_total_bytes), 0), 2
    )                                                                           AS compression_ratio
FROM timescaledb_information.hypertables h
CROSS JOIN LATERAL
    chunk_columnstore_stats(
        format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
    ) cs
WHERE h.hypertable_schema = 'your_schema'   -- ← укажите схему
  AND cs.compression_status = 'Compressed'
GROUP BY 1, 2
ORDER BY before_mb DESC NULLS LAST;


-- -----------------------------------------------------------------------------
-- 2. Детализация по каждому чанку
--    Показывает объём и % экономии для каждого сжатого чанка отдельно
-- -----------------------------------------------------------------------------
SELECT
    h.hypertable_schema,
    h.hypertable_name,
    cs.chunk_name,
    ROUND(cs.before_compression_total_bytes / 1024.0 / 1024.0, 2) AS before_mb,
    ROUND(cs.after_compression_total_bytes  / 1024.0 / 1024.0, 2) AS after_mb,
    ROUND(
        100.0 * (1 - cs.after_compression_total_bytes::numeric
                   / NULLIF(cs.before_compression_total_bytes, 0)), 2
    )                                                               AS saved_pct
FROM timescaledb_information.hypertables h
CROSS JOIN LATERAL
    chunk_columnstore_stats(
        format('%I.%I', h.hypertable_schema, h.hypertable_name)::regclass
    ) cs
WHERE h.hypertable_schema = 'your_schema'   -- ← укажите схему
  AND cs.compression_status = 'Compressed'
ORDER BY h.hypertable_name, before_mb DESC NULLS LAST;
