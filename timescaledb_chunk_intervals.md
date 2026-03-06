# Шпаргалка: Смена чанк-интервала в TimescaleDB

## 1. Проверка текущего интервала
```sql
SELECT hypertable_schema, hypertable_name, time_interval
FROM timescaledb_information.dimensions
WHERE hypertable_name = 'your_table';
```
*Интервалы времени возвращаются в микросекундах.*

## 2. Установка нового интервала
```sql
-- Для TIMESTAMPTZ / TIMESTAMP колонок:
SELECT set_chunk_time_interval('your_table', INTERVAL '1 day');

-- Для INTEGER / BIGINT колонок (значение в микросекундах, 1 день = 86400000000 мкс):
SELECT set_chunk_time_interval('your_table', 86400000000);

-- Если у таблицы несколько временны́х измерений:
SELECT set_chunk_time_interval('your_table', INTERVAL '1 day', dimension_name => 'created_at');
```
⚠️ **Важно:** новый интервал применяется только к *будущим* чанкам. Существующие чанки не изменяются.

## 3. Проверка: является ли таблица гипертаблицей?
Если запрос из п.1 вернул пустоту, проверяем наличие таблицы в каталоге:
```sql
SELECT * FROM timescaledb_information.hypertables
WHERE hypertable_name = 'your_table';
```

## 4. Проверка схемы таблицы
Если таблица не в схеме `public`, ищем ее в каталоге:
```sql
SELECT schema_name, table_name
FROM _timescaledb_catalog.hypertable
WHERE table_name = 'your_table';
```

## 5. Создание гипертаблицы (миграция обычной таблицы)
Если таблица оказалась не гипертаблицей и в ней уже есть данные:
```sql
SELECT create_hypertable(
  'your_table',
  'created_at',                -- колонка с временем
  migrate_data => true,        -- перенести существующие данные (блокирует таблицу на время миграции!)
  chunk_time_interval => INTERVAL '1 day'
);
```