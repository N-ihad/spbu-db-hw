-- Домашнее задание по SQL: Индексы + Группировки + Оконные функции
-- Тема: Индексы + Группировки + Оконные функции

-- Устанавливаю search_path, чтобы не писать "university.students" перед каждой таблицей
SET search_path TO university, public;

-- ============================================================
-- ЗАДАНИЕ 1 (GROUP BY + HAVING)
-- ============================================================
-- Найдите курсы, у которых доля сдавших (is_passed=true) < 60%.
-- Выведите: code, title, total, passed, passed_percent.
--
-- Для решения использую GROUP BY по курсу, чтобы сгруппировать все зачисления
-- по каждому курсу. Использую COUNT(*) для подсчета общего количества зачислений
-- и COUNT(*) FILTER (WHERE is_passed = true) для подсчета только сдавших студентов.
--
-- Затем вычисляю процент сдавших как отношение количества сдавших к общему
-- количеству, умноженное на 100. Использую NULLIF для защиты от деления на ноль.
--
-- HAVING использую для фильтрации групп, где процент сдавших меньше 60%

SELECT
    c.code,
    c.title,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE e.is_passed = true) AS passed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE e.is_passed = true) / NULLIF(COUNT(*), 0), 2) AS passed_percent
FROM enrollments e
JOIN courses c ON c.course_id = e.course_id
GROUP BY c.code, c.title
HAVING 100.0 * COUNT(*) FILTER (WHERE e.is_passed = true) / NULLIF(COUNT(*), 0) < 60.0
ORDER BY passed_percent ASC, c.code;

-- ============================================================
-- ЗАДАНИЕ 2 (WINDOW)
-- ============================================================
-- Для каждого курса выведите:
--   semester, course_code, enrollments_count,
--   и место курса в семестре (RANK) по числу зачислений.
-- Подсказка: сначала GROUP BY semester, course_id, потом оконная.
--
-- Сначала делаю GROUP BY по semester и course_id, чтобы получить количество
-- зачислений для каждого курса в каждом семестре. Затем использую оконную
-- функцию RANK() для определения места курса в семестре по количеству зачислений.
--
-- RANK() внутри PARTITION BY semester упорядочивает курсы по количеству зачислений
-- внутри каждого семестра отдельно. Использую сортировку по убыванию (DESC), чтобы курсы
-- с наибольшим количеством зачислений получили ранг 1.

WITH course_semester_stats AS (
    SELECT
        e.semester,
        c.code AS course_code,
        COUNT(*) AS enrollments_count
    FROM enrollments e
    JOIN courses c ON c.course_id = e.course_id
    GROUP BY e.semester, e.course_id, c.code
)
SELECT
    semester,
    course_code,
    enrollments_count,
    RANK() OVER (PARTITION BY semester ORDER BY enrollments_count DESC) AS rank_in_semester
FROM course_semester_stats
ORDER BY semester, rank_in_semester, course_code;

-- ============================================================
-- ЗАДАНИЕ 3 (WINDOW)
-- ============================================================
-- Выведите студентов, которые входят в TOP-3 по GPA внутри своей кафедры.
--
-- Использую оконную функцию ROW_NUMBER() или DENSE_RANK() для ранжирования
-- студентов по GPA внутри каждой кафедры. ROW_NUMBER() присваивает уникальный
-- номер каждому студенту, даже если GPA одинаковые. DENSE_RANK() присваивает
-- одинаковый ранг студентам с одинаковым GPA, но не пропускает номера.
--
-- Использую CTE для создания ранжированного списка, затем фильтрую только
-- студентов с рангом <= 3. Это даст топ-3 студентов по GPA в каждой кафедре.
--
-- Если несколько студентов имеют одинаковый GPA и находятся на границе топ-3,
-- то с ROW_NUMBER() можно пропустить некоторых из них

WITH ranked_students AS (
    SELECT
        s.student_id,
        s.first_name,
        s.last_name,
        s.gpa,
        s.major_department_id,
        ROW_NUMBER() OVER (PARTITION BY s.major_department_id ORDER BY s.gpa DESC) AS rank_in_department
    FROM students s
)
SELECT
    d.name AS department_name,
    r.student_id,
    r.first_name,
    r.last_name,
    r.gpa,
    r.rank_in_department
FROM ranked_students r
JOIN departments d ON d.department_id = r.major_department_id
WHERE r.rank_in_department <= 3
ORDER BY department_name, r.rank_in_department, r.last_name, r.first_name;

-- ============================================================
-- ЗАДАНИЕ 4 (INDEX DESIGN)
-- ============================================================
-- Придумайте индексы для запроса:
--   SELECT * FROM enrollments
--   WHERE semester='Fall 2023' AND is_passed=false
--   ORDER BY course_id;
-- Проверьте EXPLAIN (ANALYZE, BUFFERS) до и после.
--
-- Для этого запроса нужен индекс, который:
-- 1. Поддерживает фильтрацию по semester и is_passed
-- 2. Поддерживает сортировку по course_id
--
-- Вариант 1: Составной индекс (semester, is_passed, course_id)
--   - Первые два поля для фильтрации
--   - Последнее поле для сортировки
--   - Это покрывающий индекс для данной выборки
--
-- Вариант 2: Частичный индекс на (semester, course_id) WHERE is_passed=false
--   - Оптимизирован специально для запросов с is_passed=false
--   - Меньше размер, быстрее обновления
--
-- В данном случае лучше использую составной индекс, так как он более универсален.
-- Порядок полей важен: сначала фильтрующие поля, потом сортирующее.

-- План запроса ДО создания индекса
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE semester = 'Fall 2023'
  AND is_passed = false
ORDER BY course_id;

-- Создаю составной индекс для оптимизации запроса
-- Порядок полей: сначала фильтрующие (semester, is_passed), потом сортирующее (course_id)
CREATE INDEX IF NOT EXISTS enrollments_sem_passed_course_idx
ON enrollments (semester, is_passed, course_id);

-- План запроса ПОСЛЕ создания индекса
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE semester = 'Fall 2023'
  AND is_passed = false
ORDER BY course_id;

-- Альтернативный вариант: частичный индекс для часто используемого фильтра
-- Этот индекс будет полезен, если часто ищем именно проваливших студентов
CREATE INDEX IF NOT EXISTS enrollments_sem_course_failed_partial_idx
ON enrollments (semester, course_id)
WHERE is_passed = false;

-- Проверка работы частичного индекса
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM enrollments
WHERE semester = 'Fall 2023'
  AND is_passed = false
ORDER BY course_id;

-- Удаление индексов после проверки (для чистоты эксперимента)
-- DROP INDEX IF EXISTS enrollments_sem_passed_course_idx;
-- DROP INDEX IF EXISTS enrollments_sem_course_failed_partial_idx;

-- ============================================================
-- ЗАДАНИЕ 5 (EXPLAIN)
-- ============================================================
-- Возьмите любой ваш запрос с JOIN + GROUP BY и разберите план:
--   scan (Seq/Index/Bitmap), join (Nested/Hash/Merge), где узкое место.
--
-- Выбираю запрос из задания 1.1 (количество студентов по кафедрам)
--
-- Разбираю план выполнения:
-- 1. Seq Scan - последовательное сканирование таблицы (самый медленный способ)
-- 2. Index Scan - сканирование по индексу (быстрее для выборочных запросов)
-- 3. Bitmap Scan - создание битовой карты для множественных условий
-- 4. Nested Loop Join - вложенные циклы (хорошо для маленьких таблиц)
-- 5. Hash Join - хеш-соединение (хорошо для больших таблиц без индексов)
-- 6. Merge Join - соединение слиянием (требует сортированных данных)

-- Выбираю запрос для анализа: количество студентов по кафедрам с средним GPA
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.name AS department_name,
    COUNT(*) AS students_count,
    ROUND(AVG(s.gpa), 2) AS avg_gpa
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
GROUP BY d.name
ORDER BY students_count DESC, department_name;

-- Анализирую план выполнения:
-- 
-- 1. SCAN типы:
--    - Seq Scan на students: последовательное чтение всей таблицы студентов
--      Это может быть узким местом, если таблица большая.
--    - Seq Scan на departments: обычно departments - маленькая таблица,
--      поэтому Seq Scan здесь приемлем.
--
-- 2. JOIN стратегия:
--    - Hash Join: PostgreSQL использует хеш-соединение
--      - Сначала строит хеш-таблицу из departments (меньшая таблица)
--      - Затем сканирует students и ищет совпадения в хеш-таблице
--      - Это эффективно, когда одна таблица значительно меньше другой
--
-- 3. Узкие места:
--    - Seq Scan на students может быть медленным для больших таблиц
--    - Отсутствие индекса на major_department_id может замедлять JOIN
--
-- 4. Оптимизация:
--    - Индекс на students(major_department_id) ускорит JOIN
--    - Если departments маленькая, то Hash Join - оптимальный выбор
--
-- Проверяю, есть ли индекс на major_department_id:
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.name AS department_name,
    COUNT(*) AS students_count,
    ROUND(AVG(s.gpa), 2) AS avg_gpa
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
GROUP BY d.name
ORDER BY students_count DESC, department_name;

-- Если индекса нет, создаю его для демонстрации улучшения:
CREATE INDEX IF NOT EXISTS students_major_department_idx
ON students (major_department_id);

-- План после создания индекса (может использовать Index Scan или остаться на Hash Join
-- в зависимости от размера данных и статистики PostgreSQL):
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    d.name AS department_name,
    COUNT(*) AS students_count,
    ROUND(AVG(s.gpa), 2) AS avg_gpa
FROM students s
JOIN departments d ON d.department_id = s.major_department_id
GROUP BY d.name
ORDER BY students_count DESC, department_name;
