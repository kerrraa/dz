PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE products (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    is_standard INTEGER NOT NULL CHECK (is_standard IN (0, 1)),
    purpose TEXT NOT NULL,
    annual_volume INTEGER NOT NULL CHECK (annual_volume >= 0)
) STRICT;

CREATE TABLE enterprises (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    phone TEXT NOT NULL
) STRICT;

CREATE TABLE materials (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL,
    unit TEXT NOT NULL,
    unit_price REAL NOT NULL CHECK (unit_price >= 0)
) STRICT;

CREATE TABLE specifications (
    product_code TEXT NOT NULL REFERENCES products(code),
    material_id INTEGER NOT NULL REFERENCES materials(id),
    established_on TEXT NOT NULL CHECK (established_on IS date(established_on, '+0 days')),
    cancelled_on TEXT CHECK (
        cancelled_on IS NULL
        OR (cancelled_on IS date(cancelled_on, '+0 days') AND cancelled_on > established_on)
    ),
    is_used INTEGER NOT NULL CHECK (is_used IN (0, 1)),
    quantity_per_unit REAL NOT NULL CHECK (
        (is_used = 1 AND quantity_per_unit > 0) OR (is_used = 0 AND quantity_per_unit = 0)
    ),
    PRIMARY KEY (product_code, material_id, established_on)
) STRICT;

-- Одна строка хранит выпуск изделия на предприятии за конкретный день.
CREATE TABLE production (
    product_code TEXT NOT NULL REFERENCES products(code),
    enterprise_code TEXT NOT NULL REFERENCES enterprises(code),
    produced_on TEXT NOT NULL CHECK (produced_on IS date(produced_on, '+0 days')),
    production_year INTEGER GENERATED ALWAYS AS (CAST(substr(produced_on, 1, 4) AS INTEGER)) STORED,
    volume INTEGER NOT NULL CHECK (volume >= 0),
    PRIMARY KEY (product_code, enterprise_code, produced_on)
) STRICT;

INSERT INTO products (code, name, is_standard, purpose, annual_volume) VALUES
    ('P-01', 'Электродвигатель', 1, 'Привод станков', 120),
    ('P-02', 'Насос', 1, 'Перекачка воды', 70),
    ('P-03', 'Редуктор', 0, 'Снижение оборотов привода', 40),
    ('P-04', 'Клеммный блок', 1, 'Подключение проводов', 60);

INSERT INTO enterprises (code, name, address, phone) VALUES
    ('Z-01', 'Завод «Механика»', 'Промышленная ул., 10', '+7 000 000-00-01'),
    ('Z-02', 'Завод «Электропривод»', 'Заводская ул., 4', '+7 000 000-00-02');

-- Цена указана в рублях за единицу измерения. «Лапша» — плоский провод.
INSERT INTO materials (id, name, type, unit, unit_price) VALUES
    (1, 'медь', 'цветной металл', 'кг', 50),
    (2, 'алюминий', 'цветной металл', 'кг', 25),
    (3, 'латунь', 'цветной металл', 'кг', 40),
    (4, 'сталь', 'чёрный металл', 'кг', 10),
    (5, 'лапша', 'провод', 'м', 4);

INSERT INTO specifications
    (product_code, material_id, established_on, cancelled_on, is_used, quantity_per_unit)
VALUES
    ('P-01', 1, '1999-01-01', NULL, 1, 2),
    ('P-01', 2, '1999-01-01', NULL, 1, 1),
    ('P-01', 3, '1999-01-01', NULL, 1, 0.5),
    ('P-01', 4, '1999-01-01', NULL, 0, 0),
    ('P-01', 5, '1999-01-01', '2000-07-01', 1, 3),
    ('P-01', 5, '2000-07-01', NULL, 1, 2),
    ('P-02', 3, '1999-01-01', NULL, 1, 0.5),
    ('P-02', 4, '1999-01-01', NULL, 1, 3),
    ('P-02', 5, '1999-01-01', NULL, 1, 1),
    ('P-03', 2, '1999-01-01', NULL, 1, 0.5),
    ('P-03', 4, '1999-01-01', NULL, 1, 4),
    ('P-04', 1, '2000-01-01', NULL, 1, 0.25),
    ('P-04', 5, '2000-01-01', NULL, 1, 1.5);

INSERT INTO production (product_code, enterprise_code, produced_on, volume) VALUES
    ('P-01', 'Z-01', '1999-02-11', 40),
    ('P-01', 'Z-02', '1999-11-06', 60),
    ('P-02', 'Z-01', '1999-05-14', 50),
    ('P-03', 'Z-01', '1999-07-13', 40),
    ('P-01', 'Z-01', '2000-01-20', 20),
    ('P-01', 'Z-02', '2000-06-22', 30),
    ('P-01', 'Z-01', '2000-07-01', 30),
    ('P-01', 'Z-02', '2000-12-03', 10),
    ('P-02', 'Z-01', '2000-08-17', 65),
    ('P-03', 'Z-01', '2000-08-17', 0),
    ('P-04', 'Z-02', '2000-11-05', 60);

-- День установления входит в срок действия. Отмена или новая версия его завершает.
CREATE VIEW specification_periods AS
WITH changes AS (
    SELECT *,
           LEAD(established_on) OVER (
               PARTITION BY product_code, material_id ORDER BY established_on
           ) AS next_date
    FROM specifications
)
SELECT product_code, material_id, established_on, is_used, quantity_per_unit,
       CASE
           WHEN cancelled_on IS NULL THEN next_date
           WHEN next_date IS NULL THEN cancelled_on
           ELSE MIN(cancelled_on, next_date)
       END AS effective_until
FROM changes;

CREATE VIEW material_consumption AS
SELECT p.product_code, p.production_year, s.material_id,
       p.volume * s.quantity_per_unit AS consumed_quantity,
       p.volume * s.quantity_per_unit * m.unit_price AS material_cost
FROM production AS p
JOIN specification_periods AS s
    ON s.product_code = p.product_code
   AND s.established_on <= p.produced_on
   AND (s.effective_until IS NULL OR p.produced_on < s.effective_until)
   AND s.is_used = 1
JOIN materials AS m ON m.id = s.material_id
WHERE p.volume > 0;

COMMIT;

-- 1. Изделия с наибольшим числом материалов типа «цветной металл»
WITH metal_counts AS (
    SELECT s.product_code, COUNT(DISTINCT s.material_id) AS material_count
    FROM specification_periods AS s
    JOIN materials AS m ON m.id = s.material_id
    WHERE m.type = 'цветной металл'
      AND s.is_used = 1
      AND s.established_on <= CURRENT_DATE
      AND (s.effective_until IS NULL OR CURRENT_DATE < s.effective_until)
    GROUP BY s.product_code
)
SELECT p.code AS "Код", p.name AS "Изделие", c.material_count AS "Число материалов"
FROM metal_counts AS c
JOIN products AS p ON p.code = c.product_code
WHERE c.material_count = (SELECT MAX(material_count) FROM metal_counts)
ORDER BY p.code;

-- 2. Изделия без выпуска в 2000 году
SELECT p.code AS "Код", p.name AS "Изделие"
FROM products AS p
WHERE NOT EXISTS (
    SELECT 1
    FROM production AS f
    WHERE f.product_code = p.code AND f.production_year = 2000 AND f.volume > 0
)
ORDER BY p.code;

-- 3. Изделия, у которых затраты на материалы снизились в 2000 году
-- При отсутствии выпуска годовые затраты равны нулю.
WITH annual_costs AS (
    SELECT product_code,
           ROUND(SUM(CASE WHEN production_year = 1999 THEN material_cost ELSE 0 END), 2) AS cost_1999,
           ROUND(SUM(CASE WHEN production_year = 2000 THEN material_cost ELSE 0 END), 2) AS cost_2000
    FROM material_consumption
    WHERE production_year IN (1999, 2000)
    GROUP BY product_code
)
SELECT p.code AS "Код", p.name AS "Изделие",
       c.cost_1999 AS "1999, руб.", c.cost_2000 AS "2000, руб.",
       ROUND(c.cost_1999 - c.cost_2000, 2) AS "Снижение, руб."
FROM annual_costs AS c
JOIN products AS p ON p.code = c.product_code
WHERE c.cost_2000 < c.cost_1999
ORDER BY p.code;

-- 4. Среднемесячный расход материала «лапша» в 2000 году
-- Делим годовой расход на 12, включая месяцы без выпуска.
SELECT m.name AS "Материал", m.unit AS "Единица",
       COALESCE(SUM(c.consumed_quantity), 0) AS "Расход за год",
       ROUND(COALESCE(SUM(c.consumed_quantity), 0) / 12.0, 2) AS "Среднее за месяц"
FROM materials AS m
LEFT JOIN material_consumption AS c ON c.material_id = m.id AND c.production_year = 2000
WHERE m.name = 'лапша'
GROUP BY m.id, m.name, m.unit;
