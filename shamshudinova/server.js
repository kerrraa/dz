import { once } from 'node:events';
import { fileURLToPath, pathToFileURL } from 'node:url';
import Koa from 'koa';
import Router from '@koa/router';
import { bodyParser } from '@koa/bodyparser';
import { openStock } from './storage.js';

const textFields = ['name', 'category', 'location'];
const itemFields = [...textFields, 'quantity'];

function readItemId(ctx) {
  const value = ctx.params.id;
  const id = Number(value);

  ctx.assert(/^[1-9]\d*$/.test(value) && Number.isSafeInteger(id), 400, 'Некорректный ID');
  return id;
}

function readItem(ctx, partial = false) {
  const input = ctx.request.body;
  ctx.assert(input && typeof input === 'object' && !Array.isArray(input), 400, 'Ожидается объект JSON');

  const keys = Object.keys(input);
  ctx.assert(keys.every((key) => itemFields.includes(key)), 400, 'В запросе есть неизвестное поле');
  ctx.assert(keys.length > 0, 400, 'Передайте поля оборудования');

  const item = {};
  for (const key of textFields) {
    if (partial && !Object.hasOwn(input, key)) continue;
    const value = input[key];
    ctx.assert(typeof value === 'string' && value.trim().length > 0, 400, `Заполните поле ${key}`);
    item[key] = value.trim();
  }

  if (!partial || Object.hasOwn(input, 'quantity')) {
    const { quantity } = input;
    ctx.assert(Number.isSafeInteger(quantity) && quantity >= 0, 400, 'Количество должно быть целым и неотрицательным');
    item.quantity = quantity;
  }

  return item;
}

export function createStockApp(stock) {
  const app = new Koa();
  const router = new Router({ prefix: '/items' });

  app.use(async (ctx, next) => {
    try {
      await next();
    } catch (error) {
      ctx.status = error.status ?? 500;
      ctx.body = { error: error.expose ? error.message : 'Внутренняя ошибка сервера' };
      if (ctx.status >= 500) ctx.app.emit('error', error, ctx);
    }
  });

  app.use(bodyParser({ enableTypes: ['json'] }));

  router.get('/', async (ctx) => {
    ctx.body = await stock.list();
  });

  router.get('/:id', async (ctx) => {
    const item = await stock.find(readItemId(ctx));
    ctx.assert(item, 404, 'Оборудование не найдено');
    ctx.body = item;
  });

  router.post('/', async (ctx) => {
    const item = await stock.add(readItem(ctx));
    ctx.status = 201;
    ctx.set('Location', `/items/${item.id}`);
    ctx.body = item;
  });

  router.patch('/:id', async (ctx) => {
    const item = await stock.update(readItemId(ctx), readItem(ctx, true));
    ctx.assert(item, 404, 'Оборудование не найдено');
    ctx.body = item;
  });

  router.delete('/:id', async (ctx) => {
    const item = await stock.remove(readItemId(ctx));
    ctx.assert(item, 404, 'Оборудование не найдено');
    ctx.status = 204;
  });

  app.use(router.routes());
  app.use(router.allowedMethods());
  return app;
}

async function start() {
  const port = Number(process.env.PORT ?? 3001);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT должен быть целым числом от 1 до 65535');
  }

  const databasePath = fileURLToPath(new URL('./stock.sqlite', import.meta.url));
  const stock = await openStock(databasePath);

  try {
    const server = createStockApp(stock).listen(port, '127.0.0.1');
    await once(server, 'listening');
    console.log(`Склад оборудования: http://127.0.0.1:${port}`);
  } catch (error) {
    await stock.close();
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await start();
  } catch (error) {
    console.error('Не удалось запустить сервер:', error.message);
    process.exitCode = 1;
  }
}
