-- Домашнее задание по SQL: Виртуализация в PostgreSQL (CTE, VIEW, TEMP, MATERIALIZED VIEW)
-- Тема: CTE, VIEW, TEMP + сравнение VIEW vs MATERIALIZED VIEW

-- Устанавливаю search_path, чтобы не писать "university.students" перед каждой таблицей
SET search_path TO university, public;

-- ============================================================
-- ЗАДАНИЕ 1 (CTE)
-- ============================================================
-- Найдите студентов, у которых средняя посещаемость >= 85 по всем курсам.
-- Выведите: student_id, ФИО, avg_attendance.
--
-- Для решения используем CTE (Common Table Expression) - виртуальную таблицу
-- внутри запроса. В CTE student_attendance вычисляем среднюю посещаемость
-- для каждого студента по всем его зачислениям (enrollments).
--
-- Использую HAVING вместо WHERE, потому что нужно фильтровать по результату
-- агрегации (AVG). HAVING применяется после GROUP BY и позволяет фильтровать
-- группы по агрегированным значениям.
--
-- Затем делаю JOIN с таблицей students, чтобы получить ФИО студентов.
-- Сортирую по убыванию посещаемости, затем по фамилии и имени для удобства.

WITH student_attendance AS (
    SELECT
        student_id,
        ROUND(AVG(attendance_percent), 2) AS avg_attendance
    FROM enrollments
    GROUP BY student_id
    HAVING AVG(attendance_percent) >= 85
)
SELECT
    s.student_id,
    s.first_name,
    s.last_name,
    sa.avg_attendance
FROM student_attendance sa
JOIN students s ON s.student_id = sa.student_id
ORDER BY sa.avg_attendance DESC, s.last_name, s.first_name;

-- ============================================================
-- ЗАДАНИЕ 2 (CTE + TOP-N)
-- ============================================================
-- Выведите TOP-3 кафедры по среднему GPA студентов (major_department).
--
-- Здесь используем CTE для подготовки данных и затем применяем TOP-N запрос.
-- В CTE department_gpa вычисляем средний GPA студентов для каждой кафедры,
-- используя поле major_department_id из таблицы students.
--
-- Делаю JOIN departments с students по major_department_id, чтобы получить
-- название кафедры. Группирую по кафедре и считаю средний GPA и количество
-- студентов (для полноты информации).
--
-- После CTE сортирую по среднему GPA по убыванию и ограничиваю результат
-- LIMIT 3, чтобы получить топ-3 кафедры.

WITH department_gpa AS (
    SELECT
        d.department_id,
        d.name AS department_name,
        ROUND(AVG(s.gpa), 2) AS avg_gpa,
        COUNT(s.student_id) AS students_count
    FROM departments d
    JOIN students s ON s.major_department_id = d.department_id
    GROUP BY d.department_id, d.name
)
SELECT
    department_name,
    avg_gpa,
    students_count
FROM department_gpa
ORDER BY avg_gpa DESC
LIMIT 3;

-- ============================================================
-- ЗАДАНИЕ 3 (VIEW)
-- ============================================================
-- Создайте VIEW v_instructor_salary_level:
--   salary >= 100000 -> 'high'
--   salary >= 70000  -> 'mid'
--   иначе            -> 'low'
-- Затем посчитайте, сколько преподавателей в каждой категории.
--
-- Использую CASE WHEN для категоризации зарплат. Условия проверяются
-- последовательно: сначала >= 100000 (high), потом >= 70000 (mid), иначе low
--
-- CREATE OR REPLACE позволяет пересоздать VIEW, если он уже существует.

CREATE OR REPLACE VIEW v_instructor_salary_level AS
SELECT
    instructor_id,
    first_name,
    last_name,
    salary,
    CASE
        WHEN salary >= 100000 THEN 'high'
        WHEN salary >= 70000 THEN 'mid'
        ELSE 'low'
    END AS salary_level
FROM instructors;

-- Подсчет преподавателей по категориям
-- Используем созданный VIEW как обычную таблицу. Группируем по salary_level
-- и считаем количество преподавателей в каждой категории.
--
-- Для сортировки использую CASE в ORDER BY, чтобы вывести категории в логическом
-- порядке: сначала high, потом mid, потом low

SELECT
    salary_level,
    COUNT(*) AS instructors_count
FROM v_instructor_salary_level
GROUP BY salary_level
ORDER BY
    CASE salary_level
        WHEN 'high' THEN 1
        WHEN 'mid' THEN 2
        WHEN 'low' THEN 3
    END;

-- ============================================================
-- ЗАДАНИЕ 4 (TEMP)
-- ============================================================
-- Создайте TEMP таблицу tmp_failed_enrollments (is_passed = false).
-- Выведите: топ-10 курсов с максимальным числом провалов (id, число провалов).
--
-- Сначала удаляем таблицу, если она существует (DROP TABLE IF EXISTS), чтобы
-- можно было перезапустить скрипт без ошибок.
--
-- CREATE TEMP TABLE ... AS (CTAS - Create Table As Select) создает временную
-- таблицу и заполняет её результатом SELECT. Фильтруем только проваленные
-- зачисления (is_passed = false).

DROP TABLE IF EXISTS tmp_failed_enrollments;

CREATE TEMP TABLE tmp_failed_enrollments AS
SELECT
    enrollment_id,
    student_id,
    course_id,
    semester,
    grade,
    attendance_percent,
    is_passed
FROM enrollments
WHERE is_passed = false;

-- Топ-10 курсов с максимальным числом провалов
-- Используем созданную TEMP таблицу для анализа. Делаем JOIN с courses,
-- чтобы получить информацию о курсах (code, title).
--
-- Группируем по курсу и считаем количество провалов (COUNT). Сортируем
-- по убыванию количества провалов и ограничиваем результат LIMIT 10.
-- Включил code и title для удобства чтения результата.

SELECT
    c.course_id,
    c.code,
    c.title,
    COUNT(tfe.enrollment_id) AS failures_count
FROM tmp_failed_enrollments tfe
JOIN courses c ON c.course_id = tfe.course_id
GROUP BY c.course_id, c.code, c.title
ORDER BY failures_count DESC
LIMIT 10;

-- ============================================================
-- ЗАДАНИЕ 5 (VIEW + CTE)
-- ============================================================
-- На основе v_student_course_enrollments найдите студентов, у которых >= 2 оценок 'F'.
-- Выведите student_id, ФИО, count_f.
--
-- Сначала создадим VIEW, если его еще нет. Этот VIEW объединяет
-- зачисления со студентами, курсами и кафедрами, предоставляя все нужные поля в одном месте

CREATE OR REPLACE VIEW v_student_course_enrollments AS
SELECT
    e.enrollment_id,
    e.semester,
    e.grade,
    e.attendance_percent,
    e.is_passed,
    s.student_id,
    s.first_name AS student_first_name,
    s.last_name  AS student_last_name,
    s.enrollment_year,
    s.gpa,
    s.is_full_time,
    c.course_id,
    c.code AS course_code,
    c.title AS course_title,
    c.credits,
    c.level AS course_level,
    d.department_id AS course_department_id,
    d.name AS course_department_name
FROM enrollments e
JOIN students s  ON s.student_id = e.student_id
JOIN courses  c  ON c.course_id  = e.course_id
JOIN departments d ON d.department_id = c.department_id;

-- Решение задания с использованием VIEW и CTE
-- В CTE student_f_grades фильтруем записи из VIEW по grade = 'F',
-- группируем по студенту и считаем количество оценок 'F'.
--
-- Использую HAVING COUNT(*) >= 2, чтобы оставить только студентов
-- с двумя и более оценками 'F'.
--
-- Затем просто выбираем нужные поля из CTE и сортируем по количеству
-- оценок 'F' по убыванию, затем по фамилии и имени.

WITH student_f_grades AS (
    SELECT
        student_id,
        student_first_name,
        student_last_name,
        COUNT(*) AS count_f
    FROM v_student_course_enrollments
    WHERE grade = 'F'
    GROUP BY student_id, student_first_name, student_last_name
    HAVING COUNT(*) >= 2
)
SELECT
    student_id,
    student_first_name,
    student_last_name,
    count_f
FROM student_f_grades
ORDER BY count_f DESC, student_last_name, student_first_name;

-- ============================================================
-- ЗАДАНИЕ 6 (MATERIALIZED VIEW)
-- ============================================================
-- Создайте MATERIALIZED VIEW по средней посещаемости курсов:
--   course_id, code, title, avg_attendance, enroll_count
-- Создайте индекс на avg_attendance DESC.
-- Сравните время/план запроса:
--   EXPLAIN ANALYZE SELECT ... ORDER BY avg_attendance DESC LIMIT 10
-- для обычного VIEW и для MATERIALIZED VIEW.
--
-- Создаем обычный VIEW для сравнения. Этот VIEW будет вычислять среднюю посещаемость
-- и количество зачислений каждый раз при обращении.

CREATE OR REPLACE VIEW v_course_attendance AS
SELECT
    c.course_id,
    c.code,
    c.title,
    ROUND(AVG(e.attendance_percent), 2) AS avg_attendance,
    COUNT(e.enrollment_id) AS enroll_count
FROM courses c
JOIN enrollments e ON e.course_id = c.course_id
GROUP BY c.course_id, c.code, c.title;

-- Создаем MATERIALIZED VIEW
-- Сначала удаляем, если существует, чтобы можно было перезапустить скрипт.
-- MATERIALIZED VIEW хранит результат запроса как таблицу, 
-- данные "заморожены" на момент создания и не обновляются автоматически
-- при изменении исходных таблиц. Для обновления нужно выполнить
-- REFRESH MATERIALIZED VIEW mv_course_attendance.

DROP MATERIALIZED VIEW IF EXISTS mv_course_attendance;

CREATE MATERIALIZED VIEW mv_course_attendance AS
SELECT
    c.course_id,
    c.code,
    c.title,
    ROUND(AVG(e.attendance_percent), 2) AS avg_attendance,
    COUNT(e.enrollment_id) AS enroll_count
FROM courses c
JOIN enrollments e ON e.course_id = c.course_id
GROUP BY c.course_id, c.code, c.title;

-- Создаем индекс на MATERIALIZED VIEW
-- На обычном VIEW нельзя создать индекс, потому что VIEW не хранит данные.
-- На MATERIALIZED VIEW можно создавать индексы, так как это фактически таблица.
-- Индекс на avg_attendance DESC ускорит запросы с сортировкой по этому полю.
-- IF NOT EXISTS позволяет перезапустить скрипт без ошибок, если индекс уже есть.

CREATE INDEX IF NOT EXISTS mv_course_attendance_avg_attendance_idx 
ON mv_course_attendance (avg_attendance DESC);

-- Сравнение планов выполнения для обычного VIEW
-- EXPLAIN ANALYZE показывает план выполнения запроса и реальное время выполнения.
-- Для VIEW будет видно, что выполняется полный запрос с JOIN и агрегацией

EXPLAIN ANALYZE
SELECT
    course_id,
    code,
    title,
    avg_attendance,
    enroll_count
FROM v_course_attendance
ORDER BY avg_attendance DESC
LIMIT 10;

-- Сравнение планов выполнения для MATERIALIZED VIEW
-- Для MATERIALIZED VIEW план будет показывать простой SELECT из таблицы
-- с использованием индекса (Index Scan)

EXPLAIN ANALYZE
SELECT
    course_id,
    code,
    title,
    avg_attendance,
    enroll_count
FROM mv_course_attendance
ORDER BY avg_attendance DESC
LIMIT 10;

