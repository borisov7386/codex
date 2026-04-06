# Памятка: Колоночное хранение в TimescaleDB (Columnstore API 2.18+)

> ⚠️ Устаревший API (не использовать):
> `timescaledb.compress`, `compress_segmentby`, `compress_orderby`,
> `compress_chunk()`, `decompress_chunk()`, `add_compression_policy()`, `remove_compression_policy()`

---

## 1. Включение и выключение колоночного хранения

### Включить
```sql
ALTER TABLE table_name SET (
    timescaledb.enable_columnstore = true,
    timescaledb.segmentby = 'col1',          -- колонка группировки (LOW cardinality!)
    timescaledb.orderby   = 'created_at DESC' -- сортировка внутри сегмента
);
```

> ⚠️ **NULL в segmentby** — все NULL-строки попадают в один гигантский сегмент.
> Если колонка содержит много NULL — не используй её как segmentby.
> Цель: 100–10 000 строк на сегмент внутри одного чанка.

### Отключить
*Важно: перед выполнением все чанки должны быть конвертированы в строчный формат!*
```sql
ALTER TABLE table_name SET (timescaledb.enable_columnstore = false);
```

---

## 2. Управление политиками (Columnstore Policies)

### Создать политику автоматической конвертации
```sql
SELECT add_columnstore_policy('table_name', after => INTERVAL '14 days');
```

### Удалить политику
Останавливает джоб. Уже сконвертированные данные остаются в колоночном формате.
```sql
SELECT remove_columnstore_policy('table_name');
```

### Остановить/возобновить джоб без удаления
```sql
-- Найти job_id
SELECT job_id, proc_name, scheduled, config
FROM timescaledb_information.jobs
WHERE hypertable_name = 'table_name';

-- Остановить
SELECT alter_job(<job_id>, scheduled => false);

-- Возобновить
SELECT alter_job(<job_id>, scheduled => true);
```

---

## 3. Ручная конвертация чанков

### Строчный → колоночный
```sql
CALL convert_to_columnstore('_timescaledb_internal._hyper_1_10_chunk'::regclass);
```

### Колоночный → строчный
```sql
CALL convert_to_rowstore('_timescaledb_internal._hyper_1_10_chunk'::regclass);
```

### Репаковка без полного разжатия (для late data)
```sql
CALL convert_to_columnstore('_timescaledb_internal._hyper_1_10_chunk'::regclass, recompress => true);
```

### Конвертировать ВСЕ чанки таблицы в строчный формат
```sql
DO $$
DECLARE chunk record;
BEGIN
    FOR chunk IN
        SELECT format('%I.%I', chunk_schema, chunk_name) AS full_name
        FROM timescaledb_information.chunks
        WHERE hypertable_name = 'table_name' AND is_compressed = true
    LOOP
        CALL convert_to_rowstore(chunk.full_name::regclass);
    END LOOP;
END $$;
```

---

## 4. Sparse индексы по значениям (Chunk Skipping)

Позволяет **полностью пропускать чанки** по фильтру `WHERE col = $1` без декомпрессии.
Метаданные min/max записываются в момент `convert_to_columnstore` — вызывать **до сжатия**.

```sql
-- Включить chunk skipping для колонки
SELECT enable_chunk_skipping('table_name', 'col_name');

-- Работает с: WHERE col = $1, WHERE col > $1, WHERE col BETWEEN $1 AND $2
-- НЕ работает с: WHERE col IN (1,2,3), WHERE col IS NULL
```

---

## 5. Мониторинг

### Настройки колоночного хранения
```sql
SELECT * FROM timescaledb_information.hypertable_columnstore_settings
WHERE hypertable_schema = 'public'
ORDER BY hypertable_name;
```

### Активные политики (джобы)
```sql
SELECT job_id, hypertable_name, schedule_interval, config
FROM timescaledb_information.jobs
WHERE proc_name = 'policy_columnstore'
ORDER BY hypertable_name;
```

### Статус чанков
```sql
SELECT chunk_name, range_start::date, range_end::date,
       (range_end - range_start) AS interval,
       is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'table_name'
ORDER BY range_end DESC;
```

### Экономия места
```sql
SELECT
    chunk_name,
    compression_status,
    pg_size_pretty(before_compression_total_bytes) AS before,
    pg_size_pretty(after_compression_total_bytes)  AS after,
    ROUND(
        100.0 * (1 - after_compression_total_bytes::numeric
                   / NULLIF(before_compression_total_bytes, 0)), 1
    ) AS saved_pct
FROM chunk_columnstore_stats('table_name')
ORDER BY chunk_name DESC;
```
