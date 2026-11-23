const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const assignments = [
  { title: "Задание №1. Расписание", source: "schedule.sql" },
  { title: "Задание №2. Производство", source: "production.sql" }
];

for (const assignment of assignments) {
  const text = readFileSync(join(__dirname, assignment.source), "utf8");
  const [setup, ...reports] = text.split(/^-- RESULT: /m);
  const db = new DatabaseSync(":memory:");

  try {
    db.exec(setup);
    console.log(`\n${assignment.title}`);

    for (const report of reports) {
      const lineBreak = report.indexOf("\n");
      const title = report.slice(0, lineBreak).trim();
      const sql = report.slice(lineBreak + 1);
      console.log(`\n${title}`);
      console.table(db.prepare(sql).all());
    }
  } finally {
    db.close();
  }
}
