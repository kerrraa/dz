const { once } = require("node:events");
const { join } = require("node:path");
const { promisify } = require("node:util");
const Koa = require("koa");
const Router = require("@koa/router");
const { bodyParser } = require("@koa/bodyparser");
const sqlite3 = require("sqlite3");

const databaseFile = join(__dirname, "inventory.sqlite");
const fields = ["name", "inventoryNumber", "room", "status"];
const statuses = ["working", "repair", "retired"];
const columns = "id, name, inventory_number AS inventoryNumber, room, status";

function readId(ctx) {
  const value = ctx.params.id;
  const id = Number(value);
  ctx.assert(/^[1-9]\d*$/.test(value) && Number.isSafeInteger(id), 400, "Некорректный ID");
  return id;
}

function readItem(ctx, partial = false) {
  ctx.assert(ctx.is("application/json"), 415, "Ожидается application/json");
  const body = ctx.request.body;
  ctx.assert(body && typeof body === "object" && !Array.isArray(body), 400, "Ожидается объект JSON");

  const keys = Object.keys(body);
  ctx.assert(keys.length > 0, 400, "Укажите хотя бы одно поле");
  const item = partial ? {} : { status: "working" };

  for (const key of keys) {
    ctx.assert(fields.includes(key), 400, `Неизвестное поле: ${key}`);
    const value = body[key];
    ctx.assert(typeof value === "string" && value.trim(), 400, `Заполните поле ${key}`);
    item[key] = value.trim();
  }

  if (!partial) {
    ctx.assert(item.name && item.inventoryNumber && item.room, 400, "Нужны name, inventoryNumber и room");
  }
  if (item.status !== undefined) {
    ctx.assert(statuses.includes(item.status), 400, "Состояние должно быть working, repair или retired");
  }
  return item;
}

async function createApp(filename = databaseFile) {
  const db = await new Promise((resolve, reject) => {
    const connection = new sqlite3.Database(filename, (error) => {
      if (error) reject(error);
      else resolve(connection);
    });
  });
  const close = promisify(db.close.bind(db));
  const exec = promisify(db.exec.bind(db));
  const all = promisify(db.all.bind(db));
  const get = promisify(db.get.bind(db));

  try {
    await exec(`
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        inventory_number TEXT NOT NULL UNIQUE,
        room TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('working', 'repair', 'retired'))
      )
    `);
  } catch (error) {
    await close();
    throw error;
  }

  const app = new Koa();
  const router = new Router();

  app.use(async (ctx, next) => {
    try {
      await next();
    } catch (error) {
      if (error.code === "SQLITE_CONSTRAINT" &&
          error.message.includes("UNIQUE constraint failed: items.inventory_number")) {
        ctx.status = 409;
        ctx.body = { error: "Инвентарный номер уже занят" };
        return;
      }

      ctx.status = error.status || 500;
      ctx.body = { error: error.expose ? error.message : "Ошибка сервера" };
      if (ctx.status >= 500) app.emit("error", error, ctx);
    }
  });

  app.use(bodyParser({ enableTypes: ["json"] }));

  router.get("/items", async (ctx) => {
    ctx.body = await all(`SELECT ${columns} FROM items ORDER BY id`);
  });

  router.get("/items/:id", async (ctx) => {
    const item = await get(`SELECT ${columns} FROM items WHERE id = ?`, [readId(ctx)]);
    ctx.assert(item, 404, "Оборудование не найдено");
    ctx.body = item;
  });

  router.post("/items", async (ctx) => {
    const { name, inventoryNumber, room, status } = readItem(ctx);
    const item = await get(
      `INSERT INTO items (name, inventory_number, room, status)
       VALUES (?, ?, ?, ?) RETURNING ${columns}`,
      [name, inventoryNumber, room, status]
    );
    ctx.status = 201;
    ctx.set("Location", `/items/${item.id}`);
    ctx.body = item;
  });

  router.patch("/items/:id", async (ctx) => {
    const id = readId(ctx);
    const { name = null, inventoryNumber = null, room = null, status = null } = readItem(ctx, true);
    const item = await get(
      `UPDATE items
       SET name = COALESCE(?, name), inventory_number = COALESCE(?, inventory_number),
           room = COALESCE(?, room), status = COALESCE(?, status)
       WHERE id = ? RETURNING ${columns}`,
      [name, inventoryNumber, room, status, id]
    );
    ctx.assert(item, 404, "Оборудование не найдено");
    ctx.body = item;
  });

  router.delete("/items/:id", async (ctx) => {
    const item = await get("DELETE FROM items WHERE id = ? RETURNING id", [readId(ctx)]);
    ctx.assert(item, 404, "Оборудование не найдено");
    ctx.status = 204;
  });

  app.use(router.routes());
  app.use(router.allowedMethods());
  return { app, close };
}

async function start() {
  const { app, close } = await createApp();
  try {
    const server = app.listen(Number(process.env.PORT ?? 3000), "127.0.0.1");
    await once(server, "listening");
    console.log(`Сервер запущен: http://127.0.0.1:${server.address().port}`);
  } catch (error) {
    await close();
    throw error;
  }
}

if (require.main === module) {
  start().catch((error) => {
    console.error("Не удалось запустить сервер:", error.message);
    process.exitCode = 1;
  });
}

module.exports = { createApp };
