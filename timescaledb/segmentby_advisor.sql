-- =============================================================================
-- TimescaleDB 2.18+ | Диагностика для выбора segmentby / orderby
-- Замените 'your_table' и 'created_at' на реальные значения
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Глобальная кардинальность кандидатов в segmentby
--    Цель: rows_per_col должно быть 100–10 000 внутри одного чанка
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                    AS total_rows,
    -- кандидат  1
    COUNT(DISTINCT col1)                                        AS uniq_col1,
    COUNT(*) / NULLIF(COUNT(DISTINCT col1), 0)                  AS rows_per_col1,
    SUM(CASE WHEN col1 IS NULL THEN 1 ELSE 0 END)               AS null_col1,
    ROUND(100.0 * SUM(CASE WHEN col1 IS NULL THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                        AS pct_null_col1,
    -- кандидат 2
    COUNT(DISTINCT col2)                                        AS uniq_col2,
    COUNT(*) / NULLIF(COUNT(DISTINCT col2), 0)                  AS rows_per_col2,
    SUM(CASE WHEN col2 IS NULL THEN 1 ELSE 0 END)               AS null_col2,
    ROUND(100.0 * SUM(CASE WHEN col2 IS NULL THEN 1 ELSE 0 END)
          / COUNT(*), 1)                                        AS pct_null_col2
FROM your_table;
-- Интерпретация:
--   rows_per_col < 100        → кардинальность слишком высокая, не использовать
--   rows_per_col 100..10 000  → отличный кандидат
--   rows_per_col > 10 000     → можно, но сегменты будут большими
--   pct_null > 5%             → опасно! все NULL попадают в один сегмент


-- -----------------------------------------------------------------------------
-- 2. Кардинальность внутри одного чанка (ключевой показатель)
--    Берём 5 свежих чанков для репрезентативности
-- -----------------------------------------------------------------------------
SELECT
    c.chunk_schema || '.' || c.chunk_name              AS chunk,
    c.range_start::date,
    c.range_end::date,
    (c.range_end - c.range_start)                      AS chunk_interval,
    (
        SELECT COUNT(*)
        FROM your_table s
        WHERE s.created_at >= c.range_start
          AND s.created_at <  c.range_end
    ) AS chunk_rows,
    (
        SELECT COUNT(DISTINCT col1)
        FROM your_table s
        WHERE s.created_at >= c.range_start
          AND s.created_at <  c.range_end
    ) AS uniq_col1,
    (
        SELECT COUNT(DISTINCT col2)
        FROM your_table s
        WHERE s.created_at >= c.range_start
          AND s.created_at <  c.range_end
    ) AS uniq_col2
FROM timescaledb_information.chunks c
WHERE c.hypertable_name = 'your_table'
  AND c.is_compressed = false           -- только несжатые (реальные строки)
ORDER BY c.range_end DESC
LIMIT 5;
-- Интерпретация: chunk_rows / uniq_col — строк на сегмент в этом чанке
-- Цель: 100–10 000 строк на сегмент


-- -----------------------------------------------------------------------------
-- 3. Распределение по перцентилям (хвосты выбросов)
--    Топ 1% и max могут сломать segmentby если очень высоки
-- -----------------------------------------------------------------------------
SELECT
    percentile_cont(0.50) WITHIN GROUP (ORDER BY cnt) AS p50,
    percentile_cont(0.90) WITHIN GROUP (ORDER BY cnt) AS p90,
    percentile_cont(0.99) WITHIN GROUP (ORDER BY cnt) AS p99,
    MAX(cnt)                                           AS max_rows_per_segment
FROM (
    SELECT col1, COUNT(*) AS cnt
    FROM your_table
    GROUP BY col1
) s;
-- Если max >> p99 — есть выброс.
-- Если этот col1 = NULL — проверьте pct_null_col1 из запроса #1


-- -----------------------------------------------------------------------------
-- 4. Итоговая проверка настроек после применения
-- -----------------------------------------------------------------------------
SELECT *
FROM timescaledb_information.hypertable_columnstore_settings
WHERE hypertable::TEXT = 'your_table';
