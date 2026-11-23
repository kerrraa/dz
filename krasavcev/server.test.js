const assert = require("node:assert/strict");
const { once } = require("node:events");
const test = require("node:test");
const { promisify } = require("node:util");
const { createApp } = require("./server");

const sample = { name: "Проектор", inventoryNumber: "INV-101", room: "205" };

async function openServer(t) {
  const { app, close } = await createApp(":memory:");
  const server = app.listen(0, "127.0.0.1");
  t.after(async () => {
    try {
      await promisify(server.close.bind(server))();
    } finally {
      await close();
    }
  });
  await once(server, "listening");
  return `http://127.0.0.1:${server.address().port}/items`;
}

function sendJson(url, method, body) {
  return fetch(url, {
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
}

async function addItem(url, changes) {
  const response = await sendJson(url, "POST", { ...sample, ...changes });
  assert.equal(response.status, 201);
  return response.json();
}

test("GET /items отдаёт список оборудования", async (t) => {
  const url = await openServer(t);
  const empty = await fetch(url);
  assert.equal(empty.status, 200);
  assert.deepEqual(await empty.json(), []);

  const first = await addItem(url);
  const second = await addItem(url, { name: "Монитор", inventoryNumber: "INV-102" });
  const response = await fetch(url);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), [first, second]);
});

test("GET /items/:id отдаёт одну карточку", async (t) => {
  const url = await openServer(t);
  const item = await addItem(url);
  const response = await fetch(`${url}/${item.id}`);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), item);
  assert.equal((await fetch(`${url}/999`)).status, 404);
  assert.equal((await fetch(`${url}/abc`)).status, 400);
});

test("POST /items создаёт карточку с рабочим состоянием по умолчанию", async (t) => {
  const url = await openServer(t);
  const response = await sendJson(url, "POST", sample);

  assert.equal(response.status, 201);
  const item = await response.json();
  assert.ok(Number.isSafeInteger(item.id) && item.id > 0);
  assert.equal(response.headers.get("location"), `/items/${item.id}`);
  assert.deepEqual(item, { id: item.id, ...sample, status: "working" });
});

test("PATCH /items/:id меняет только переданные поля", async (t) => {
  const url = await openServer(t);
  const item = await addItem(url);
  const itemUrl = `${url}/${item.id}`;
  const changes = { room: "310", status: "repair" };
  const response = await sendJson(itemUrl, "PATCH", changes);
  const updated = { ...item, ...changes };

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), updated);
  assert.deepEqual(await (await fetch(itemUrl)).json(), updated);
  assert.equal((await sendJson(itemUrl, "PATCH", {})).status, 400);
  assert.equal((await sendJson(`${url}/999`, "PATCH", changes)).status, 404);
});

test("DELETE /items/:id удаляет карточку", async (t) => {
  const url = await openServer(t);
  const item = await addItem(url);
  const itemUrl = `${url}/${item.id}`;
  const response = await fetch(itemUrl, { method: "DELETE" });

  assert.equal(response.status, 204);
  assert.equal(await response.text(), "");
  assert.equal((await fetch(itemUrl)).status, 404);
  assert.equal((await fetch(itemUrl, { method: "DELETE" })).status, 404);
});

test("POST и PATCH отклоняют занятый инвентарный номер", async (t) => {
  const url = await openServer(t);
  await addItem(url);
  const second = await addItem(url, { inventoryNumber: "INV-102" });
  const duplicate = await sendJson(url, "POST", sample);
  const itemUrl = `${url}/${second.id}`;
  const conflict = await sendJson(itemUrl, "PATCH", { inventoryNumber: sample.inventoryNumber });

  assert.equal(duplicate.status, 409);
  assert.equal(conflict.status, 409);
  assert.deepEqual(await (await fetch(itemUrl)).json(), second);
});

test("POST /items отклоняет неполные данные и сломанный JSON", async (t) => {
  const url = await openServer(t);
  const incomplete = await sendJson(url, "POST", { name: sample.name });
  const malformed = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{"
  });

  assert.equal(incomplete.status, 400);
  assert.equal(malformed.status, 400);
});
