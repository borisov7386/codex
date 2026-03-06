-- Удаление старых партиций (чанков) в TimescaleDB до 2024 года.
-- Использование 6 аргументов необходимо для обхода ошибки перегрузки типов:
-- ERROR: function drop_chunks(...) is not unique

-- Скрипт 1: lk_sessions
-- created_at имеет тип: timestamp WITH time zone
-- Используем AT TIME ZONE 'Asia/Novokuznetsk' для явного приведения к UTC
SELECT drop_chunks(
    'lk_sessions'::regclass,                                            -- 1. relation
    '2024-01-01 00:00:00'::timestamp AT TIME ZONE 'Asia/Novokuznetsk',  -- 2. older_than
    NULL,                                                               -- 3. newer_than (пропускаем)
    false,                                                              -- 4. verbose (вывод подробностей)
    NULL,                                                               -- 5. created_before (пропускаем)
    NULL                                                                -- 6. created_after (пропускаем)
);

-- Скрипт 2: lk_events
-- Колонка времени имеет тип: timestamp WITHOUT time zone
-- AT TIME ZONE здесь НЕ используется — иначе будет ошибка:
-- ERROR: invalid time argument type "timestamp with time zone"
-- HINT: Try casting the argument to "timestamp without time zone"
SELECT drop_chunks(
    'lk_events'::regclass,                                            -- 1. relation
    '2024-01-01 00:00:00'::timestamp,                                 -- 2. older_than (без AT TIME ZONE)
    NULL,                                                             -- 3. newer_than (пропускаем)
    false,                                                            -- 4. verbose (вывод подробностей)
    NULL,                                                             -- 5. created_before (пропускаем)
    NULL                                                              -- 6. created_after (пропускаем)
);
