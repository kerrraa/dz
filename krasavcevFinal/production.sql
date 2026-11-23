PRAGMA foreign_keys = ON;
BEGIN;

CREATE TABLE products (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    standard_model INTEGER NOT NULL CHECK (standard_model IN (0, 1)),
    purpose TEXT NOT NULL,
    planned_annual_units INTEGER NOT NULL CHECK (planned_annual_units >= 0)
) STRICT;

CREATE TABLE factories (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    phone TEXT NOT NULL
) STRICT;

CREATE TABLE materials (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    material_type TEXT NOT NULL,
    unit TEXT NOT NULL,
    price_kopecks INTEGER NOT NULL CHECK (price_kopecks >= 0)
) STRICT;

-- При изменении норм выпускается новая версия спецификации целиком.
CREATE TABLE recipes (
    id INTEGER PRIMARY KEY,
    product_code TEXT NOT NULL REFERENCES products (code),
    effective_from TEXT NOT NULL CHECK (date(effective_from, '+0 days') IS effective_from),
    cancelled_on TEXT,
    CHECK (cancelled_on IS NULL OR (
        date(cancelled_on, '+0 days') IS cancelled_on AND cancelled_on > effective_from
    )),
    UNIQUE (product_code, effective_from)
) STRICT;

CREATE TABLE recipe_materials (
    recipe_id INTEGER NOT NULL REFERENCES recipes (id),
    material_code TEXT NOT NULL REFERENCES materials (code),
    is_used INTEGER NOT NULL CHECK (is_used IN (0, 1)),
    quantity_per_item REAL NOT NULL,
    CHECK ((is_used = 1 AND quantity_per_item > 0) OR
           (is_used = 0 AND quantity_per_item = 0)),
    PRIMARY KEY (recipe_id, material_code)
) STRICT;

-- Партия ссылается на версию спецификации, по которой её выпустили.
CREATE TABLE batches (
    id INTEGER PRIMARY KEY,
    recipe_id INTEGER NOT NULL REFERENCES recipes (id),
    factory_code TEXT NOT NULL REFERENCES factories (code),
    produced_on TEXT NOT NULL CHECK (date(produced_on, '+0 days') IS produced_on),
    production_year INTEGER GENERATED ALWAYS AS (CAST(substr(produced_on, 1, 4) AS INTEGER)) STORED,
    units INTEGER NOT NULL CHECK (units >= 0)
) STRICT;

INSERT INTO products (code, name, standard_model, purpose, planned_annual_units) VALUES
    ('R-11', 'Промышленный светильник', 1, 'Освещение цехов', 60),
    ('R-12', 'Вентиляционная решётка', 0, 'Защита вентиляционного канала', 35),
    ('R-13', 'Монтажная панель', 1, 'Крепление аппаратуры в шкафу', 40),
    ('R-14', 'Кабельный ввод', 1, 'Подвод кабеля к оборудованию', 25);

INSERT INTO factories (code, name, address, phone) VALUES
    ('L1', 'Завод «Контур»', 'ул. Механическая, 14', '+7 000 000-11-21'),
    ('L2', 'Завод «Луч»', 'ул. Заводская, 7', '+7 000 000-11-22');

INSERT INTO materials (code, name, material_type, unit, price_kopecks) VALUES
    ('AL', 'алюминиевый лист', 'цветной металл', 'кг', 30000),
    ('BR', 'бронзовая втулка', 'цветной металл', 'шт.', 18000),
    ('ZN', 'цинковая лента', 'цветной металл', 'кг', 12000),
    ('ST', 'стальная полоса', 'чёрный металл', 'кг', 9000),
    ('FL', 'лапша', 'плоский провод', 'м', 600);

INSERT INTO recipes (id, product_code, effective_from, cancelled_on) VALUES
    (1, 'R-11', '1999-01-01', '2000-07-01'),
    (2, 'R-11', '2000-07-01', NULL),
    (3, 'R-12', '1999-01-01', NULL),
    (4, 'R-13', '1999-01-01', NULL),
    (5, 'R-14', '2000-01-01', NULL);

INSERT INTO recipe_materials (recipe_id, material_code, is_used, quantity_per_item) VALUES
    (1, 'AL', 1, 1), (1, 'BR', 1, 1), (1, 'ZN', 1, 0.25), (1, 'FL', 1, 3),
    (2, 'AL', 1, 0.5), (2, 'BR', 1, 1), (2, 'ZN', 1, 0.25), (2, 'FL', 1, 2),
    (3, 'BR', 1, 1), (3, 'ST', 1, 0.5), (3, 'FL', 1, 1), (3, 'ZN', 0, 0),
    (4, 'ST', 1, 2),
    (5, 'AL', 1, 0.25), (5, 'FL', 1, 0.5);

INSERT INTO batches (id, recipe_id, factory_code, produced_on, units) VALUES
    (1, 1, 'L1', '1999-04-15', 30),
    (2, 1, 'L2', '1999-11-20', 20),
    (3, 3, 'L1', '1999-09-07', 20),
    (4, 4, 'L2', '1999-12-03', 40),
    (5, 1, 'L1', '2000-02-10', 12),
    (6, 1, 'L2', '2000-06-30', 8),
    (7, 2, 'L1', '2000-07-01', 20),
    (8, 2, 'L2', '2000-10-17', 10),
    (9, 3, 'L1', '2000-03-21', 30),
    (10, 4, 'L2', '2000-08-09', 0),
    (11, 5, 'L2', '2000-09-14', 20);

CREATE VIEW batch_materials AS
SELECT recipe.product_code, batch.production_year, material.code AS material_code,
       batch.units * line.quantity_per_item AS quantity_used,
       batch.units * line.quantity_per_item * material.price_kopecks AS cost_kopecks
FROM batches AS batch
JOIN recipes AS recipe ON recipe.id = batch.recipe_id
JOIN recipe_materials AS line ON line.recipe_id = recipe.id AND line.is_used = 1
JOIN materials AS material ON material.code = line.material_code
WHERE batch.units > 0;

COMMIT;

-- RESULT: Изделия с наибольшим числом цветных металлов
-- Для этой выборки берём действующую на сегодня версию спецификации.
WITH latest_recipes AS (
    SELECT id, product_code, cancelled_on,
           ROW_NUMBER() OVER (PARTITION BY product_code ORDER BY effective_from DESC) AS version_rank
    FROM recipes
    WHERE effective_from <= CURRENT_DATE
), metal_counts AS (
    SELECT recipe.product_code, COUNT(DISTINCT line.material_code) AS metal_count
    FROM latest_recipes AS recipe
    JOIN recipe_materials AS line ON line.recipe_id = recipe.id AND line.is_used = 1
    JOIN materials AS material ON material.code = line.material_code
    WHERE recipe.version_rank = 1
      AND (recipe.cancelled_on IS NULL OR recipe.cancelled_on > CURRENT_DATE)
      AND material.material_type = 'цветной металл'
    GROUP BY recipe.product_code
), ranked AS (
    SELECT product_code, metal_count,
           DENSE_RANK() OVER (ORDER BY metal_count DESC) AS place
    FROM metal_counts
)
SELECT product.code AS "Код", product.name AS "Изделие",
       ranked.metal_count AS "Число материалов"
FROM ranked
JOIN products AS product ON product.code = ranked.product_code
WHERE ranked.place = 1
ORDER BY product.code;

-- RESULT: Изделия, которые не выпускались в 2000 году
WITH without_output AS (
    SELECT code FROM products
    EXCEPT
    SELECT recipe.product_code
    FROM batches AS batch
    JOIN recipes AS recipe ON recipe.id = batch.recipe_id
    WHERE batch.production_year = 2000 AND batch.units > 0
)
SELECT product.code AS "Код", product.name AS "Изделие"
FROM without_output
JOIN products AS product ON product.code = without_output.code
ORDER BY product.code;

-- RESULT: Снижение затрат на материалы в 2000 году по сравнению с 1999 годом
-- Отсутствие выпуска означает нулевые затраты на материалы в этом году.
WITH yearly_costs AS (
    SELECT product_code, production_year, ROUND(SUM(cost_kopecks) / 100.0, 2) AS rubles
    FROM batch_materials
    WHERE production_year IN (1999, 2000)
    GROUP BY product_code, production_year
)
SELECT product.code AS "Код", product.name AS "Изделие",
       past.rubles AS "1999, руб.", COALESCE(present.rubles, 0) AS "2000, руб.",
       ROUND(past.rubles - COALESCE(present.rubles, 0), 2) AS "Снижение, руб."
FROM yearly_costs AS past
JOIN products AS product ON product.code = past.product_code
LEFT JOIN yearly_costs AS present ON present.product_code = past.product_code
                                AND present.production_year = 2000
WHERE past.production_year = 1999 AND past.rubles > COALESCE(present.rubles, 0)
ORDER BY product.code;

-- RESULT: Среднемесячный расход материала «лапша» в 2000 году
SELECT material.name AS "Материал", material.unit AS "Единица",
       COALESCE(SUM(consumption.quantity_used), 0) AS "Расход за год",
       ROUND(COALESCE(SUM(consumption.quantity_used), 0) / 12.0, 2) AS "Среднее за месяц"
FROM materials AS material
LEFT JOIN batch_materials AS consumption ON consumption.material_code = material.code
                                         AND consumption.production_year = 2000
WHERE material.name = 'лапша'
GROUP BY material.code, material.name, material.unit;
