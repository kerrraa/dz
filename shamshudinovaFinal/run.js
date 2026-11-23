const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const assignments = [
  { title: "Задание №1. Расписание", source: "schedule.sql" },
  { title: "Задание №2. Производство", source: "production.sql" }
];

for (const assignment of assignments) {
  const text = readFileSync(join(__dirname, assignment.source), "utf8");
  const [setup, ...reports] = text.split(/\r?\n(?=-- \d+\. )/);
  const db = new DatabaseSync(":memory:");

  try {
    db.exec(setup);
    console.log("\n" + assignment.title);

    for (const report of reports) {
      const endOfTitle = report.indexOf("\n");
      console.log("\n" + report.slice(3, endOfTitle).trim());
      console.table(db.prepare(report).all());
    }
  } finally {
    db.close();
  }
}
