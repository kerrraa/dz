PRAGMA foreign_keys = ON;
BEGIN;

CREATE TABLE departments (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    head_id INTEGER,
    FOREIGN KEY (id, head_id) REFERENCES instructors (department_id, id)
) STRICT;

CREATE TABLE instructors (
    id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    address TEXT NOT NULL,
    position TEXT NOT NULL,
    degree TEXT,
    department_id INTEGER NOT NULL REFERENCES departments (id),
    UNIQUE (department_id, id)
) STRICT;

CREATE TABLE cycles (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
) STRICT;

CREATE TABLE courses (
    code TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    hours INTEGER NOT NULL CHECK (hours > 0),
    assessment TEXT NOT NULL CHECK (assessment IN ('зачёт', 'экзамен')),
    cycle_id INTEGER NOT NULL REFERENCES cycles (id)
) STRICT;

CREATE TABLE course_assignments (
    id INTEGER PRIMARY KEY,
    instructor_id INTEGER NOT NULL REFERENCES instructors (id),
    course_code TEXT NOT NULL REFERENCES courses (code),
    UNIQUE (instructor_id, course_code)
) STRICT;

CREATE TABLE classrooms (
    number TEXT PRIMARY KEY
) STRICT;

CREATE TABLE study_groups (
    code TEXT PRIMARY KEY
) STRICT;

CREATE TABLE class_sessions (
    id INTEGER PRIMARY KEY,
    assignment_id INTEGER NOT NULL REFERENCES course_assignments (id),
    classroom_number TEXT NOT NULL REFERENCES classrooms (number),
    group_code TEXT NOT NULL REFERENCES study_groups (code),
    class_date TEXT NOT NULL CHECK (date(class_date, '+0 days') IS class_date),
    start_minute INTEGER NOT NULL CHECK (start_minute BETWEEN 0 AND 1439),
    duration_minutes INTEGER NOT NULL CHECK (duration_minutes > 0),
    end_minute INTEGER GENERATED ALWAYS AS (start_minute + duration_minutes) STORED,
    CHECK (end_minute <= 1440)
) STRICT;

INSERT INTO departments (id, code, name) VALUES
    (1, 'MAT', 'Кафедра прикладной математики'),
    (2, 'ENG', 'Кафедра инженерных систем'),
    (3, 'LAN', 'Кафедра языка и коммуникации');

INSERT INTO instructors (id, full_name, address, position, degree, department_id) VALUES
    (31, 'Крылов Пётр Андреевич', 'ул. Ясная, 18', 'заведующий кафедрой', 'кандидат наук', 1),
    (32, 'Лебедева Ирина Олеговна', 'ул. Берёзовая, 42', 'заведующая кафедрой', 'кандидат наук', 2),
    (33, 'Никитина Светлана Викторовна', 'ул. Сиреневая, 9', 'заведующая кафедрой', 'доктор наук', 3),
    (34, 'Орлов Максим Денисович', 'ул. Липовая, 27', 'ассистент', NULL, 2);

UPDATE departments SET head_id = 31 WHERE code = 'MAT';
UPDATE departments SET head_id = 32 WHERE code = 'ENG';
UPDATE departments SET head_id = 33 WHERE code = 'LAN';

INSERT INTO cycles (id, name) VALUES
    (1, 'математический'),
    (2, 'компьютерный'),
    (3, 'общеинженерный'),
    (4, 'гуманитарный');

INSERT INTO courses (code, title, hours, assessment, cycle_id) VALUES
    ('AL-12', 'Линейная алгебра', 72, 'экзамен', 1),
    ('ST-17', 'Статистика', 52, 'экзамен', 1),
    ('NET-21', 'Компьютерные сети', 64, 'экзамен', 2),
    ('CAD-61', 'Техническое черчение', 56, 'зачёт', 3),
    ('RU-05', 'Деловое общение', 34, 'зачёт', 4);

INSERT INTO course_assignments (id, instructor_id, course_code) VALUES
    (1, 31, 'AL-12'),
    (2, 31, 'ST-17'),
    (3, 32, 'NET-21'),
    (4, 32, 'CAD-61'),
    (5, 33, 'RU-05'),
    (6, 34, 'NET-21');

INSERT INTO classrooms VALUES ('А-108'), ('Б-207'), ('В-310');
INSERT INTO study_groups VALUES ('АП-17а'), ('ИВ-22б'), ('ТМ-18');

-- Начало занятий задаётся в минутах от полуночи.
INSERT INTO class_sessions (id, assignment_id, classroom_number, group_code, class_date, start_minute, duration_minutes) VALUES
    (1, 1, 'Б-207', 'АП-17а', '2001-03-01', 8 * 60 + 30, 90),
    (2, 3, 'Б-207', 'ИВ-22б', '2001-03-01', 9 * 60 + 40, 120),
    (3, 5, 'Б-207', 'АП-17а', '2001-03-01', 11 * 60 + 40, 90),
    (4, 4, 'А-108', 'АП-17а', '2001-03-14', 10 * 60 + 30, 90),
    (5, 3, 'Б-207', 'АП-17а', '2001-03-20', 12 * 60, 90),
    (6, 1, 'В-310', 'АП-17а', '2001-03-27', 11 * 60 + 10, 90),
    (7, 2, 'А-108', 'АП-17а', '2001-04-03', 9 * 60, 90),
    (8, 6, 'Б-207', 'ИВ-22б', '2001-02-28', 14 * 60, 90),
    (9, 6, 'В-310', 'АП-17а', '2001-06-01', 10 * 60, 90),
    (10, 5, 'А-108', 'ИВ-22б', '2001-05-31', 12 * 60, 90),
    (11, 4, 'В-310', 'ИВ-22б', '2001-05-31', 12 * 60, 90),
    (12, 4, 'В-310', 'АП-17а', '2001-04-01', 9 * 60, 90);

COMMIT;

-- RESULT: 1. Преподаватели без занятий весной 2001 года
WITH spring_instructors AS (
    SELECT DISTINCT assignment.instructor_id
    FROM class_sessions AS session
    JOIN course_assignments AS assignment ON assignment.id = session.assignment_id
    WHERE session.class_date BETWEEN '2001-03-01' AND '2001-05-31'
)
SELECT instructor.id AS "Номер", instructor.full_name AS "Преподаватель"
FROM instructors AS instructor
LEFT JOIN spring_instructors AS active ON active.instructor_id = instructor.id
WHERE active.instructor_id IS NULL
ORDER BY instructor.id;

-- RESULT: 2. Пересечения занятий в одной аудитории
WITH overlaps AS (
    SELECT a.class_date, a.classroom_number,
           a.group_code AS first_group, b.group_code AS second_group,
           MAX(a.start_minute, b.start_minute) AS common_start,
           MIN(a.end_minute, b.end_minute) AS common_end
    FROM class_sessions AS a
    JOIN class_sessions AS b
      ON a.id < b.id AND a.class_date = b.class_date
     AND a.classroom_number = b.classroom_number
)
SELECT class_date AS "Дата", classroom_number AS "Аудитория",
       first_group AS "Первая группа", second_group AS "Вторая группа",
       printf('%02d:%02d', common_start / 60, common_start % 60) AS "С какого времени",
       printf('%02d:%02d', common_end / 60, common_end % 60) AS "До какого времени",
       common_end - common_start AS "Минут пересечения"
FROM overlaps
WHERE common_start < common_end
ORDER BY class_date, classroom_number, common_start;

-- RESULT: 3. Расписание группы АП-17а на март 2001 года
SELECT session.class_date AS "Дата",
       printf('%02d:%02d', session.start_minute / 60, session.start_minute % 60) AS "Начало",
       printf('%02d:%02d', session.end_minute / 60, session.end_minute % 60) AS "Конец",
       session.classroom_number AS "Аудитория",
       course.title AS "Дисциплина", instructor.full_name AS "Преподаватель"
FROM class_sessions AS session
JOIN course_assignments AS assignment ON assignment.id = session.assignment_id
JOIN instructors AS instructor ON instructor.id = assignment.instructor_id
JOIN courses AS course ON course.code = assignment.course_code
WHERE session.group_code = 'АП-17а'
  AND session.class_date BETWEEN '2001-03-01' AND '2001-03-31'
ORDER BY session.class_date, session.start_minute, session.id;

-- RESULT: 4. Доля дисциплин каждого цикла по группам
WITH group_courses AS (
    SELECT DISTINCT session.group_code, assignment.course_code
    FROM class_sessions AS session
    JOIN course_assignments AS assignment ON assignment.id = session.assignment_id
),
cycle_counts AS (
    SELECT taken.group_code, course.cycle_id, COUNT(*) AS amount
    FROM group_courses AS taken
    JOIN courses AS course ON course.code = taken.course_code
    GROUP BY taken.group_code, course.cycle_id
),
cycle_shares AS (
    SELECT group_code, cycle_id, amount,
           ROUND(100.0 * amount / SUM(amount) OVER (PARTITION BY group_code), 2) AS share
    FROM cycle_counts
)
SELECT study_group.code AS "Группа", cycle.name AS "Цикл",
       COALESCE(cycle_share.amount, 0) AS "Дисциплин",
       COALESCE(cycle_share.share, 0) AS "Доля, %"
FROM study_groups AS study_group
CROSS JOIN cycles AS cycle
LEFT JOIN cycle_shares AS cycle_share
  ON cycle_share.group_code = study_group.code AND cycle_share.cycle_id = cycle.id
ORDER BY study_group.code, cycle.id;
