-- TimescaleDB Compression Policy Cheatsheet

-- 1. Просмотр всех активных политик (Jobs), включая компрессию
-- Полезно для проверки, включена ли политика и когда она запускается.
SELECT * FROM timescaledb_information.jobs 
WHERE application_name LIKE '%compression%';

-- 2. Просмотр детальных настроек компрессии для каждой гипертаблицы
-- Показывает колонки segmentby_column_index и orderby_column_index.
SELECT * FROM timescaledb_information.compression_settings;

-- 3. Полная информация о настройках компрессии гипертаблиц (более читаемый вид)
-- Показывает segmentby и orderby в понятном формате.
SELECT * FROM timescaledb_information.hypertable_compression_settings;

-- 4. Статистика сжатия (насколько эффективно сжатие)
-- Показывает размер до и после сжатия, а также процент сжатия.
SELECT * FROM hypertable_compression_stats('your_hypertable_name');

-- 5. Проверка статуса сжатия для конкретных чанков (chunks)
SELECT * FROM chunk_compression_stats('your_hypertable_name');
