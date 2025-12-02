-- Домашнее задание по SQL: базовые запросы и JOIN'ы
-- Тема: ER-диаграммы и базовые запросы

-- Устанавливаю search_path, чтобы не писать "university.students" перед каждой таблицей
SET search_path TO university, public;

-- ============================================================
-- ЗАДАНИЕ 1
-- ============================================================
-- Нужно найти всех студентов кафедры 'Computer Science'
-- 
-- В таблице students есть только department_id, нам нужно
-- найти по названию кафедры. Поэтому делаем JOIN с таблицей departments
-- по внешнему ключу department_id. Использую INNER JOIN, чтобы получить
-- только студентов, у которых точно есть кафедра (без NULL значений)
-- 
-- В результат включил основные поля студента плюс название кафедры для проверки.
-- Отсортировал по фамилии и имени, чтобы было удобнее смтреть

SELECT 
    s.student_id,
    s.first_name,
    s.last_name,
    s.enrollment_year,
    s.gpa,
    d.name AS department_name
FROM students s
INNER JOIN departments d ON s.department_id = d.department_id
WHERE d.name = 'Computer Science'
ORDER BY s.last_name, s.first_name;

-- ============================================================
-- ЗАДАНИЕ 2
-- ============================================================
-- Нужно вывести курсы кафедры 'Mathematics', только code и title
--
-- Аналогично заданию 1: делаю JOIN courses с departments, чтобы
-- отфильтровать по названию кафедры. В SELECT только code и title.
-- Сортирую по code, так как коды курсов обычно идут в алфавитном порядке

SELECT 
    c.code,
    c.title
FROM courses c
INNER JOIN departments d ON c.department_id = d.department_id
WHERE d.name = 'Mathematics'
ORDER BY c.code;

-- ============================================================
-- ЗАДАНИЕ 3
-- ============================================================
-- Найти студентов с низким GPA (меньше 2.5) и отсортировать по возрастанию
--
-- Нужно сделать запрос с фильтрацинй WHERE. Использую < 2.5, потому что
-- нужно найти тех, у кого GPA ниже этого порога. Сортировка по возрастанию
-- покажет сначала самых проблемных студентов (с самым низким GPA)

SELECT 
    student_id,
    first_name,
    last_name,
    gpa,
    enrollment_year
FROM students
WHERE gpa < 2.5
ORDER BY gpa ASC;

-- ============================================================
-- ЗАДАНИЕ 4
-- ============================================================
-- Показать зачисления с оценками: имя, фамилия студента, семестр и код курса
--
-- Здесь нужно объединить три таблицы: enrollments (где хранятся оценки),
-- students (чтобы получить имя и фамилию) и courses (чтобы получить код курса).
-- Делаю два JOIN'а: сначала enrollments с students, потом с courses
-- 
-- Фильтрую по e.grade IS NOT NULL, чтобы показать только те зачисления,
-- где уже проставлена оценка. Если бы использовал просто WHERE e.grade != NULL,
-- это не сработало бы (для проверки на NULL нужно использовать IS NULL/IS NOT NULL)
-- 
-- Отсортировал для дуобства чтения

SELECT 
    s.first_name,
    s.last_name,
    e.semester,
    c.code AS course_code
FROM enrollments e
INNER JOIN students s ON e.student_id = s.student_id
INNER JOIN courses c ON e.course_id = c.course_id
WHERE e.grade IS NOT NULL
ORDER BY s.last_name, s.first_name, e.semester, c.code;

-- ============================================================
-- ЗАДАНИЕ 5
-- ============================================================
-- Топ-10 студентов по GPA
--
-- Нужно найти студентов с самым высоким средним баллом. Для этого:
-- 1. Сортирую по GPA по убыванию (DESC) - сначала самые высокие баллы
-- 2. Ограничиваю результат LIMIT 10 - беру только первые 10 записей
-- Включил enrollment_year на всякий случай

SELECT 
    student_id,
    first_name,
    last_name,
    gpa,
    enrollment_year
FROM students
ORDER BY gpa DESC
LIMIT 10;

