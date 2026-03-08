# Памятка: Колоночное хранение в TimescaleDB 2.18+ (Columnstore & Policies)

## 1. Включение и выключение колоночного хранения на таблице

### Включить колоночное хранение
```sql
ALTER TABLE table_name SET (
    timescaledb.enable_columnstore = true,
    timescaledb.segmentby = 'col1, col2', -- Колонки для группировки
    timescaledb.orderby   = 'created_at DESC' -- Колонки для сортировки внутри группы
);
```

### Полностью отключить колоночное хранение (и удалить настройки)
*Важно: перед выполнением все чанки должны быть распакованы (конвертированы в строчный формат)!*
```sql
ALTER TABLE table_name SET (timescaledb.enable_columnstore = false);
```

---

## 2. Управление автоматическим колоночным хранением (Columnstore Policies)

### Создать политику (джоб) автоматической конвертации
Конвертировать все чанки, в которых данные старше 90 дней, в колоночный формат:
```sql
SELECT add_columnstore_policy('lk_sessions', after => INTERVAL '24 weeks');
```

### Удалить политику
Останавливает джоб. Уже сконвертированные данные остаются в колоночном формате.
```sql
SELECT remove_columnstore_policy('table_name');
```

---

## 3. Ручная конвертация чанков

### Сконвертировать конкретный чанк в колоночный формат (Строчный → колоночный)
```sql
CALL convert_to_columnstore('_timescaledb_internal._hyper_1_10_chunk'::regclass);
```

### Сконвертировать конкретный чанк обратно в строчный формат (Колоночный → строчный)
```sql
CALL convert_to_rowstore('_timescaledb_internal._hyper_1_10_chunk'::regclass);
```

### Репаковка с late data (без полного разжатия)
```sql
CALL convert_to_columnstore('_timescaledb_internal._hyper_1_10_chunk'::regclass, recompress => true);
```

### Распаковать ВСЕ колоночные чанки таблицы
```sql
DO $$
DECLARE
    chunk record;
BEGIN
    FOR chunk IN 
        SELECT c.chunk_full_name::text 
        FROM timescaledb_information.chunks c
        WHERE c.hypertable_name = 'table_name' AND c.is_compressed = true
    LOOP
        CALL convert_to_rowstore(chunk.chunk_full_name::regclass);
    END LOOP;
END $$;
```

---

## 4. Информационные представления (Мониторинг)

### Посмотреть настройки колоночного хранения по таблицам
Показывает `segmentby` и `orderby` колонки.
```sql
SELECT * FROM timescaledb_information.hypertable_columnstore_settings
WHERE hypertable_schema = 'public'
ORDER BY hypertable_name;
```

### Посмотреть созданные политики (джобы)
```sql
SELECT 
    job_id,
    hypertable_name,
    schedule_interval,
    config
FROM timescaledb_information.jobs
WHERE application_name LIKE '%columnstore%' OR proc_name = 'policy_compression'
ORDER BY hypertable_name;
```

### Посмотреть статус чанков (какие сконвертированы, а какие нет)
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

### Посмотреть экономию места от колоночного формата
```sql
SELECT * FROM chunk_compression_stats('table_name')
ORDER BY chunk_name;
```
