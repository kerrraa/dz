import { promisify } from 'node:util';
import sqlite3 from 'sqlite3';

const createTable = `
  CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity >= 0),
    location TEXT NOT NULL
  )
`;

export async function openStock(filename) {
  const database = await new Promise((resolve, reject) => {
    const connection = new sqlite3.Database(filename, (error) => {
      if (error) reject(error);
      else resolve(connection);
    });
  });

  const close = promisify(database.close.bind(database));
  const exec = promisify(database.exec.bind(database));
  const all = promisify(database.all.bind(database));
  const get = promisify(database.get.bind(database));

  try {
    await exec(createTable);
  } catch (error) {
    await close();
    throw error;
  }

  return {
    close,

    list() {
      return all('SELECT * FROM items ORDER BY id');
    },

    find(id) {
      return get('SELECT * FROM items WHERE id = ?', [id]);
    },

    add({ name, category, quantity, location }) {
      return get(
        'INSERT INTO items (name, category, quantity, location) VALUES (?, ?, ?, ?) RETURNING *',
        [name, category, quantity, location],
      );
    },

    update(id, { name, category, quantity, location }) {
      return get(`
        UPDATE items
        SET name = COALESCE(?, name), category = COALESCE(?, category),
            quantity = COALESCE(?, quantity), location = COALESCE(?, location)
        WHERE id = ?
        RETURNING *
      `, [name ?? null, category ?? null, quantity ?? null, location ?? null, id]);
    },

    remove(id) {
      return get('DELETE FROM items WHERE id = ? RETURNING id', [id]);
    },
  };
}
