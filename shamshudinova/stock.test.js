import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test } from 'node:test';
import { createStockApp } from './server.js';
import { openStock } from './storage.js';

const projector = {
  name: 'Проектор',
  category: 'Видеотехника',
  quantity: 4,
  location: 'Стеллаж А2',
};

async function setup(t) {
  const stock = await openStock(':memory:');
  const server = createStockApp(stock).listen(0, '127.0.0.1');

  t.after(async () => {
    try {
      await new Promise((resolve, reject) => {
        server.close((error) => error ? reject(error) : resolve());
      });
    } finally {
      await stock.close();
    }
  });

  await once(server, 'listening');
  const origin = `http://127.0.0.1:${server.address().port}`;

  function request(path = '/items', method = 'GET', body) {
    return fetch(`${origin}${path}`, {
      method,
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  }

  return { stock, request };
}

test('GET /items возвращает пустой список, затем позиции в порядке ID', async (t) => {
  const { stock, request } = await setup(t);
  const empty = await request();
  assert.equal(empty.status, 200);
  assert.deepEqual(await empty.json(), []);

  const first = await stock.add(projector);
  const second = await stock.add({ ...projector, name: 'Монитор', quantity: 1 });
  const response = await request();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), [first, second]);
});

test('GET /items/:id возвращает позицию по ID', async (t) => {
  const { stock, request } = await setup(t);
  const item = await stock.add(projector);
  const response = await request(`/items/${item.id}`);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), item);
});

test('POST /items добавляет оборудование и назначает ID', async (t) => {
  const { stock, request } = await setup(t);
  const response = await request('/items', 'POST', projector);

  assert.equal(response.status, 201);
  const item = await response.json();
  assert.ok(Number.isSafeInteger(item.id) && item.id > 0);
  assert.equal(response.headers.get('Location'), `/items/${item.id}`);
  assert.deepEqual(item, { id: item.id, ...projector });
  assert.deepEqual(await stock.find(item.id), item);
});

test('PATCH /items/:id сохраняет неизменённые поля и разрешает нулевой остаток', async (t) => {
  const { stock, request } = await setup(t);
  const item = await stock.add(projector);
  const response = await request(`/items/${item.id}`, 'PATCH', { quantity: 0 });

  assert.equal(response.status, 200);
  const updated = { ...item, quantity: 0 };
  assert.deepEqual(await response.json(), updated);
  assert.deepEqual(await stock.find(item.id), updated);
});

test('DELETE /items/:id удаляет позицию и возвращает пустой ответ', async (t) => {
  const { stock, request } = await setup(t);
  const item = await stock.add(projector);
  const response = await request(`/items/${item.id}`, 'DELETE');

  assert.equal(response.status, 204);
  assert.equal(await response.text(), '');
  const read = await request(`/items/${item.id}`);
  assert.equal(read.status, 404);
});

test('Запросы по отсутствующему ID возвращают 404', async (t) => {
  const { request } = await setup(t);

  assert.equal((await request('/items/42')).status, 404);
  assert.equal((await request('/items/42', 'PATCH', { quantity: 1 })).status, 404);
  assert.equal((await request('/items/42', 'DELETE')).status, 404);
});

test('Некорректный ID, пустой PATCH и отрицательный остаток возвращают 400', async (t) => {
  const { stock, request } = await setup(t);
  const item = await stock.add(projector);

  assert.equal((await request('/items/1.5')).status, 400);
  assert.equal((await request(`/items/${item.id}`, 'PATCH', {})).status, 400);
  assert.equal((await request('/items', 'POST', { ...projector, quantity: -1 })).status, 400);
  assert.deepEqual(await stock.list(), [item]);
});
