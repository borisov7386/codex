-- Удаление старых партиций (чанков) в TimescaleDB до 2024 года.
-- Использование 6 аргументов необходимо для обхода ошибки перегрузки типов:
-- ERROR: function drop_chunks(...) is not unique

SELECT drop_chunks(
    'lk_sessions'::regclass,                                            -- 1. relation
    '2024-01-01 00:00:00'::timestamp AT TIME ZONE 'Asia/Novokuznetsk',  -- 2. older_than
    NULL,                                                               -- 3. newer_than (пропускаем)
    false,                                                              -- 4. verbose (вывод подробностей)
    NULL,                                                               -- 5. created_before (пропускаем)
    NULL                                                                -- 6. created_after (пропускаем)
);