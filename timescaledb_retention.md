# TimescaleDB: Управление Data Retention

Памятка по основным командам для управления политиками хранения данных (Data Retention) в TimescaleDB.

## 1. Создание политики удержания
Автоматически удаляет чанки, когда все данные в них становятся старше указанного интервала.
```sql
-- Для TimescaleDB 2.0+ рекомендуется использовать именованный параметр:
SELECT add_retention_policy('table_name', drop_after => INTERVAL '90 days');
```

## 2. Удаление политики удержания
Останавливает автоматическое удаление чанков для конкретной гипертаблицы.
```sql
SELECT remove_retention_policy('table_name');
```

## 3. Просмотр активных политик
Проверить, какие политики удержания настроены в данный момент.
```sql
SELECT * FROM timescaledb_information.jobs 
WHERE application_name LIKE 'Retention%';
-- Или
SELECT * FROM timescaledb_information.jobs 
WHERE proc_name = 'policy_retention';
```

## 4. Ручное удаление чанков
Если не хочется ждать срабатывания фонового процесса, можно удалить старые чанки вручную.
```sql
-- Удалить все чанки старше 90 дней
SELECT drop_chunks('table_name', older_than => INTERVAL '90 days');

-- Удалить чанки для определенного диапазона времени
SELECT drop_chunks('table_name', older_than => INTERVAL '90 days', newer_than => INTERVAL '120 days');
```

## 5. Просмотр информации о чанках
Посмотреть размер и границы чанков гипертаблицы. Это полезно для понимания, какие именно данные будут удалены.
```sql
SELECT chunk_name, range_start, range_end 
FROM timescaledb_information.chunks 
WHERE hypertable_name = 'table_name' 
ORDER BY range_start;
```

## Важные нюансы
- Чанк удаляется целиком **только тогда**, когда самая свежая (последняя) запись в этом чанке становится старше заданного интервала (`drop_after`).
- При ручном удалении через `DELETE FROM ...` место на диске не освобождается мгновенно, и требуется `VACUUM`, что вызывает нагрузку на базу. При использовании политик удержания или `drop_chunks` удаляются сами файлы партиций — это работает быстро и сразу освобождает диск.
