-- TimescaleDB 2.18+ Columnstore Policy Cheatsheet

-- 1. Просмотр всех активных политик (Jobs), включая колоночное хранение
-- Полезно для проверки, включена ли политика и когда она запускается.
SELECT * FROM timescaledb_information.jobs 
WHERE application_name LIKE '%columnstore%' OR application_name LIKE '%compression%';

-- 2. Просмотр настроек колоночного хранения для гипертаблиц
-- Заменяет устаревшие timescaledb_information.compression_settings 
-- и timescaledb_information.hypertable_compression_settings
SELECT * FROM timescaledb_information.hypertable_columnstore_settings;

-- 3. Статистика колоночного хранения (насколько эффективно сжатие)
-- Показывает размер до и после сжатия, а также процент сжатия.
SELECT * FROM hypertable_compression_stats('your_hypertable_name');

-- 4. Проверка статуса для конкретных чанков (chunks)
SELECT * FROM chunk_compression_stats('your_hypertable_name');
