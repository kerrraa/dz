PRAGMA foreign_keys = ON;
BEGIN;

CREATE TABLE departments (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    head_teacher_id INTEGER NOT NULL,
    FOREIGN KEY (head_teacher_id, code) REFERENCES teachers (id, department_code)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE teachers (
    id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    address TEXT NOT NULL,
    position TEXT NOT NULL,
    academic_degree TEXT,
    department_code TEXT NOT NULL REFERENCES departments (code),
    UNIQUE (id, department_code)
);

CREATE TABLE discipline_cycles (
    name TEXT PRIMARY KEY
);

CREATE TABLE disciplines (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    hours INTEGER NOT NULL CHECK (hours > 0),
    assessment_type TEXT NOT NULL,
    cycle TEXT NOT NULL REFERENCES discipline_cycles (name)
);

CREATE TABLE teacher_disciplines (
    teacher_id INTEGER REFERENCES teachers (id),
    discipline_code TEXT REFERENCES disciplines (code),
    PRIMARY KEY (teacher_id, discipline_code)
) WITHOUT ROWID;

CREATE TABLE student_groups (
    code TEXT PRIMARY KEY
);

CREATE TABLE lessons (
    id INTEGER PRIMARY KEY,
    teacher_id INTEGER NOT NULL,
    discipline_code TEXT NOT NULL,
    group_code TEXT NOT NULL REFERENCES student_groups (code),
    room TEXT NOT NULL,
    lesson_date TEXT NOT NULL CHECK (date(lesson_date, '+0 days') IS lesson_date),
    starts_at TEXT NOT NULL CHECK (starts_at GLOB '[0-2][0-9]:[0-5][0-9]' AND starts_at < '24:00'),
    ends_at TEXT NOT NULL CHECK (ends_at GLOB '[0-2][0-9]:[0-5][0-9]' AND ends_at <= '24:00'),
    CHECK (starts_at < ends_at),
    FOREIGN KEY (teacher_id, discipline_code) REFERENCES teacher_disciplines (teacher_id, discipline_code)
);

-- Номер заведующего проверяется после добавления преподавателей, при COMMIT.
INSERT INTO departments (code, name, head_teacher_id) VALUES
    ('MATH', 'Кафедра математики', 1),
    ('CS', 'Кафедра информатики', 2),
    ('HUM', 'Кафедра гуманитарных дисциплин', 3);

INSERT INTO teachers (id, full_name, address, position, academic_degree, department_code) VALUES
    (1, 'Власова Марина Сергеевна', 'ул. Садовая, 12', 'заведующая кафедрой', 'кандидат наук', 'MATH'),
    (2, 'Денисов Игорь Павлович', 'ул. Школьная, 8', 'заведующий кафедрой', 'кандидат наук', 'CS'),
    (3, 'Романова Елена Андреевна', 'ул. Речная, 17', 'заведующая кафедрой', 'доктор наук', 'HUM'),
    (4, 'Котов Алексей Викторович', 'ул. Полевая, 5', 'преподаватель', NULL, 'CS');

INSERT INTO discipline_cycles (name) VALUES
    ('гуманитарный'), ('общеинженерный'), ('математический'), ('компьютерный');

INSERT INTO disciplines (code, name, hours, assessment_type, cycle) VALUES
    ('M101', 'Математический анализ', 96, 'экзамен', 'математический'),
    ('C101', 'Программирование', 80, 'экзамен', 'компьютерный'),
    ('C102', 'Базы данных', 48, 'зачёт', 'компьютерный'),
    ('H101', 'История', 36, 'зачёт', 'гуманитарный'),
    ('E101', 'Инженерная графика', 48, 'зачёт', 'общеинженерный');

INSERT INTO teacher_disciplines (teacher_id, discipline_code) VALUES
    (1, 'M101'), (1, 'E101'), (2, 'C101'), (2, 'C102'), (3, 'H101'), (4, 'C101');

INSERT INTO student_groups (code) VALUES ('АП-17а'), ('МС-21б'), ('ЭК-12');

INSERT INTO lessons (id, teacher_id, discipline_code, group_code, room, lesson_date, starts_at, ends_at) VALUES
    (1, 1, 'M101', 'АП-17а', '204', '2001-03-05', '09:00', '10:30'),
    (2, 2, 'C101', 'МС-21б', '204', '2001-03-05', '10:00', '11:30'),
    (3, 3, 'H101', 'АП-17а', '204', '2001-03-05', '11:30', '13:00'),
    (4, 1, 'M101', 'АП-17а', '310', '2001-03-12', '09:00', '10:30'),
    (5, 2, 'C101', 'АП-17а', '212', '2001-03-19', '10:00', '11:30'),
    (6, 2, 'C102', 'АП-17а', '212', '2001-03-26', '12:00', '13:30'),
    (7, 1, 'E101', 'МС-21б', '102', '2001-04-02', '12:00', '13:30'),
    (8, 4, 'C101', 'МС-21б', '310', '2001-02-28', '09:00', '10:30'),
    (9, 4, 'C101', 'АП-17а', '310', '2001-06-01', '09:00', '10:30'),
    (10, 3, 'H101', 'МС-21б', '102', '2001-05-31', '12:00', '13:30');

COMMIT;

-- 1. Преподаватели без занятий весной 2001 года
SELECT teacher.id AS "Номер", teacher.full_name AS "Преподаватель"
FROM teachers AS teacher
WHERE NOT EXISTS (
    SELECT 1
    FROM lessons AS lesson
    WHERE lesson.teacher_id = teacher.id
      AND lesson.lesson_date >= '2001-03-01'
      AND lesson.lesson_date < '2001-06-01'
)
ORDER BY teacher.id;

-- 2. Накладки аудиторий
-- Строгие сравнения позволяют ставить занятия подряд в одной аудитории.
SELECT first.room AS "Аудитория", first.lesson_date AS "Дата",
       first.group_code AS "Первая группа", first.starts_at || '–' || first.ends_at AS "Первое занятие",
       second.group_code AS "Вторая группа", second.starts_at || '–' || second.ends_at AS "Второе занятие"
FROM lessons AS first
JOIN lessons AS second
    ON first.id < second.id
    AND first.room = second.room
    AND first.lesson_date = second.lesson_date
    AND first.starts_at < second.ends_at
    AND second.starts_at < first.ends_at
ORDER BY first.lesson_date, first.room, first.starts_at, second.starts_at;

-- 3. Расписание группы АП-17а на март 2001 года
SELECT lesson.lesson_date AS "Дата", lesson.starts_at AS "Начало", lesson.ends_at AS "Конец",
       lesson.room AS "Аудитория", discipline.name AS "Дисциплина", teacher.full_name AS "Преподаватель"
FROM lessons AS lesson
JOIN disciplines AS discipline ON discipline.code = lesson.discipline_code
JOIN teachers AS teacher ON teacher.id = lesson.teacher_id
WHERE lesson.group_code = 'АП-17а'
  AND lesson.lesson_date >= '2001-03-01'
  AND lesson.lesson_date < '2001-04-01'
ORDER BY lesson.lesson_date, lesson.starts_at, lesson.id;

-- 4. Доля дисциплин каждого цикла по группам
-- Повторные занятия по одной дисциплине учитываются один раз.
SELECT student_group.code AS "Группа", cycle.name AS "Цикл",
       COALESCE(ROUND(
           100.0 * COUNT(DISTINCT CASE WHEN discipline.cycle = cycle.name THEN discipline.code END)
           / NULLIF(COUNT(DISTINCT discipline.code), 0), 2
       ), 0) AS "Доля, %"
FROM student_groups AS student_group
CROSS JOIN discipline_cycles AS cycle
LEFT JOIN lessons AS lesson ON lesson.group_code = student_group.code
LEFT JOIN disciplines AS discipline ON discipline.code = lesson.discipline_code
GROUP BY student_group.code, cycle.name
ORDER BY student_group.code, cycle.name;
