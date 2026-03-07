# Памятка: Сжатие данных в TimescaleDB (Compression & Policies)

## 1. Включение и выключение сжатия на таблице

### Включить сжатие
```sql
ALTER TABLE table_name SET (
    timescaledb.compress = true,
    timescaledb.compress_segmentby = 'col1, col2', -- Колонки для группировки
    timescaledb.compress_orderby = 'created_at DESC' -- Колонки для сортировки внутри группы
);
```

### Полностью отключить сжатие (и удалить настройки)
*Важно: перед выполнением все чанки должны быть распакованы!*
```sql
ALTER TABLE table_name SET (timescaledb.compress = false);
```

---

## 2. Управление автоматическим сжатием (Compression Policies)

### Создать политику (джоб) автоматического сжатия
Сжимать все чанки, в которых данные старше 90 дней:
```sql
CALL add_columnstore_policy('lk_sessions', after => INTERVAL '24 weeks');
```

### Удалить политику сжатия
Останавливает джоб. Уже сжатые данные остаются сжатыми.
```sql
SELECT remove_compression_policy('table_name');
```

---

## 3. Ручное сжатие и распаковка чанков

### Сжать конкретный чанк
```sql
SELECT compress_chunk('_timescaledb_internal._hyper_1_10_chunk');
```

### Распаковать конкретный чанк
```sql
SELECT decompress_chunk('_timescaledb_internal._hyper_1_10_chunk');
```

### Распаковать ВСЕ сжатые чанки таблицы
```sql
SELECT decompress_chunk(c.chunk_full_name) 
FROM timescaledb_information.chunks c
WHERE c.hypertable_name = 'table_name' AND c.is_compressed = true;
```

---

## 4. Информационные представления (Мониторинг)

### Посмотреть настройки сжатия по таблицам (только схема public)
Показывает `segmentby` и `orderby` колонки.
```sql
SELECT 
    hypertable_schema,
    hypertable_name, 
    attname AS column_name, 
    segmentby_column_index, 
    orderby_column_index, 
    orderby_asc 
FROM timescaledb_information.compression_settings
WHERE hypertable_schema = 'public'
ORDER BY hypertable_name, attname;
```

### Посмотреть созданные политики сжатия (джобы)
```sql
SELECT 
    job_id,
    hypertable_name,
    schedule_interval,
    config->>'compress_after' AS compress_after
FROM timescaledb_information.jobs
WHERE proc_name = 'policy_compression'
ORDER BY hypertable_name;
```

### Посмотреть статистику выполнения джобов (успех/ошибки)
```sql
SELECT 
    j.hypertable_name,
    j.config->>'compress_after' AS compress_after,
    s.last_run_started_at,
    s.last_run_status,
    s.total_runs,
    s.total_failures
FROM timescaledb_information.jobs j
LEFT JOIN timescaledb_information.job_stats s ON j.job_id = s.job_id
WHERE j.proc_name = 'policy_compression';
```

### Посмотреть статус сжатия самих чанков (какие сжаты, а какие нет)
```sql
SELECT
    chunk_name,
    range_start,
    range_end,
    is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'table_name'
ORDER BY range_start DESC;
```

### Посмотреть экономию места от сжатия
```sql
SELECT
    chunk_name,
    compression_status,
    before_compression_total_bytes,
    after_compression_total_bytes,
    round(
        100.0 * after_compression_total_bytes 
        / NULLIF(before_compression_total_bytes, 0), 1
    ) AS compression_ratio_pct
FROM chunk_compression_stats('table_name')
ORDER BY chunk_name;
```
