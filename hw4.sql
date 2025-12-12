-- Домашнее задание по SQL: Транзакции
-- Тема: Транзакции

-- Устанавливаю search_path, чтобы не писать "university.students" перед каждой таблицей
SET search_path TO university, public;

-- ============================================================
-- ЗАДАНИЕ 1 (транзакции)
-- ============================================================
-- Реализуйте "перевод денег" между счетами tx_accounts:
--   - списать со счета 1 сумму 200
--   - зачислить на счет 2 сумму 200
--   - если на счете 1 недостаточно средств — откатить
-- Подсказка: SELECT ... FOR UPDATE + проверка + UPDATE + COMMIT/ROLLBACK.
--
-- Для реализации перевода денег использую следующую логику:
-- 1. BEGIN транзакции для атомарности операции
-- 2. SELECT ... FOR UPDATE для блокировки строк счетов, чтобы избежать
--    гонок условий (race conditions) при параллельных транзакциях
-- 3. Проверка баланса счета 1: если баланс меньше 200, то откат транзакции
-- 4. Если баланс достаточен, выполняю UPDATE для списания и зачисления
-- 5. COMMIT для фиксации изменений или ROLLBACK при ошибке
--
-- SELECT ... FOR UPDATE блокирует строки до конца транзакции, что гарантирует,
-- что другой транзакции не удастся изменить баланс между проверкой и обновлением

BEGIN;

    -- Блокируем счета для обновления, чтобы избежать race conditions
    -- SELECT ... FOR UPDATE блокирует строки до конца транзакции
    SELECT balance
    FROM tx_accounts
    WHERE account_id IN (1, 2)
    FOR UPDATE
    LIMIT 10000;

    -- Проверяем баланс счета 1 и выполняем перевод в одном блоке
    DO $$
    DECLARE
        account1_balance NUMERIC(12,2);
    BEGIN
        -- Получаем текущий баланс счета 1
        SELECT balance INTO account1_balance
        FROM tx_accounts
        WHERE account_id = 1
        LIMIT 1;
        
        -- Если баланс недостаточен, откатываем транзакцию
        IF account1_balance < 200.00 THEN
            RAISE EXCEPTION 'Недостаточно средств на счете 1. Текущий баланс: %', account1_balance;
        END IF;
    END $$;

    -- Выполняем перевод: списываем со счета 1
    UPDATE tx_accounts
    SET balance = balance - 200.00,
        updated_at = now()
    WHERE account_id = 1;

    -- Зачисляем на счет 2
    UPDATE tx_accounts
    SET balance = balance + 200.00,
        updated_at = now()
    WHERE account_id = 2;

    -- Проверяем результат перед коммитом
    SELECT * FROM tx_accounts WHERE account_id IN (1, 2) ORDER BY account_id LIMIT 10000;

COMMIT;

-- Проверка финального состояния счетов
SELECT * FROM tx_accounts ORDER BY account_id LIMIT 10000;

-- ============================================================
-- ЗАДАНИЕ 2 (savepoint)
-- ============================================================
-- В одной транзакции:
--   - обновить Alice (+10)
--   - SAVEPOINT
--   - сделать действие, которое нарушит CHECK
--   - откатиться к SAVEPOINT и завершить COMMIT.
--
-- Логика:
-- 1. Обновляем баланс Alice (+10) - это успешная операция
-- 2. Создаем SAVEPOINT - точка сохранения состояния
-- 3. Пытаемся выполнить операцию, которая нарушит CHECK (например, установить
--    отрицательный баланс) - это вызовет ошибку
-- 4. Откатываемся к SAVEPOINT - отменяем только ошибочную операцию,
--    но сохраняем изменения до SAVEPOINT
-- 5. COMMIT - фиксируем успешные изменения (обновление Alice)

BEGIN;

    -- Обновляем баланс Alice (+10)
    UPDATE tx_accounts
    SET balance = balance + 10.00,
        updated_at = now()
    WHERE account_id = 1 AND owner_name = 'Alice';

    -- Проверяем состояние после первого обновления
    SELECT * FROM tx_accounts WHERE account_id = 1 LIMIT 1;

    -- Создаем точку сохранения
    SAVEPOINT sp_before_error;

    -- Пытаемся выполнить операцию, которая нарушит CHECK constraint
    -- (попытка установить отрицательный баланс)
    -- Это вызовет ошибку из-за CHECK (balance >= 0)
    -- Используем DO блок для перехвата ошибки, чтобы не прервать всю транзакцию
    DO $$
    BEGIN
        UPDATE tx_accounts
        SET balance = balance - 100000.00
        WHERE account_id = 1;
    EXCEPTION
        WHEN check_violation THEN
            -- Продолжаем выполнение, чтобы сделать ROLLBACK TO SAVEPOINT
            NULL;
    END $$;

    -- Откатываемся к SAVEPOINT, чтобы отменить ошибочную операцию
    -- но сохранить изменения до SAVEPOINT (обновление Alice)
    ROLLBACK TO SAVEPOINT sp_before_error;

    -- Проверяем состояние: баланс Alice должен быть увеличен на 10,
    -- а ошибочное изменение отменено
    SELECT * FROM tx_accounts WHERE account_id = 1 LIMIT 1;

COMMIT;

-- Финальная проверка: баланс Alice должен быть увеличен на 10
SELECT * FROM tx_accounts ORDER BY account_id LIMIT 10000;

-- ============================================================
-- ЗАДАНИЕ 3 (изоляция)
-- ============================================================
-- В 2 консолях сравните READ COMMITTED и REPEATABLE READ на tx_demo
-- и сформулируйте вывод.

-- ===== Console A =====
-- BEGIN;
-- SHOW transaction_isolation;  -- должно показать "read committed"
-- SELECT COUNT(*) FROM tx_demo; -- например, 3 или 4
-- 
-- ===== Console B =====
-- BEGIN;
-- INSERT INTO tx_demo(note) VALUES ('row_from_B');
-- COMMIT;
-- 
-- ===== Console A =====
-- SELECT COUNT(*) FROM tx_demo; -- число изменится (станет на 1 больше)
-- COMMIT;

-- ===== Console A =====
-- BEGIN ISOLATION LEVEL REPEATABLE READ;
-- SELECT COUNT(*) FROM tx_demo; -- например, 4
-- 
-- ===== Console B =====
-- BEGIN;
-- INSERT INTO tx_demo(note) VALUES ('another_row_from_B');
-- COMMIT;
-- 
-- ===== Console A =====
-- SELECT COUNT(*) FROM tx_demo; -- останется 4 (снимок), хотя в БД уже 5
-- COMMIT;

-- Вывод:
-- READ COMMITTED позволяет видеть изменения, зафиксированные другими транзакциями
-- во время выполнения текущей транзакции. Это может привести к "фантомному чтению"
-- (phantom read) - когда повторный запрос в рамках транзакции видит новые строки,
-- добавленные другими транзакциями.
--
-- REPEATABLE READ гарантирует, что все SELECT в рамках транзакции видят один и тот же
-- снимок данных, зафиксированный на момент начала транзакции. Это предотвращает
-- фантомное чтение, но может привести к ошибкам сериализации при попытке обновить
-- данные, которые были изменены другими транзакциями.
--
-- - READ COMMITTED подходит для большинства приложений, где важно видеть актуальные данные
-- - REPEATABLE READ нужен, когда важно обеспечить консистентность данных в рамках
--   одной транзакции (например, при расчетах, которые зависят от нескольких чтений)

-- Демонстрационный запрос для проверки текущего уровня изоляции
SHOW transaction_isolation;

-- Проверка данных в tx_demo для справки
SELECT * FROM tx_demo ORDER BY id LIMIT 10000;

