#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const COMMANDS = new Set([
  "Summary",
  "Projects",
  "RecentSessions",
  "ProjectSessions",
  "Messages",
  "Search",
  "Plans",
  "Diffs",
]);

function parseArgs(argv) {
  const result = {
    command: "Summary",
    db: "",
    dataRoot: "",
    diffRoot: "",
    projectPath: "",
    sessionId: "",
    search: "",
    limit: 10,
    json: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (item === "--json") {
      result.json = true;
      continue;
    }
    const next = argv[index + 1];
    if (next === undefined) throw new Error(`Missing value for ${item}`);
    index += 1;
    if (item === "--command") result.command = next;
    else if (item === "--db") result.db = next;
    else if (item === "--data-root") result.dataRoot = next;
    else if (item === "--diff-root") result.diffRoot = next;
    else if (item === "--project-path") result.projectPath = next;
    else if (item === "--session-id") result.sessionId = next;
    else if (item === "--search") result.search = next;
    else if (item === "--limit") result.limit = Number.parseInt(next, 10);
    else throw new Error(`Unknown argument: ${item}`);
  }

  if (!COMMANDS.has(result.command)) throw new Error(`Unknown command: ${result.command}`);
  if (!Number.isInteger(result.limit) || result.limit < 1) result.limit = 10;
  return result;
}

function hasBun() {
  return Boolean(globalThis.Bun || process.versions?.bun);
}

async function openReadOnlyDatabase(dbPath) {
  if (!dbPath) throw new Error("Database path is required.");
  if (!fs.existsSync(dbPath)) throw new Error(`OpenCode database not found: ${dbPath}`);

  if (hasBun()) {
    const mod = await import("bun:sqlite");
    const sqlite = new mod.Database(dbPath, { readonly: true, create: false });
    return {
      all(sql, params = []) {
        return sqlite.query(sql).all(...params);
      },
      get(sql, params = []) {
        return sqlite.query(sql).get(...params);
      },
      close() {
        sqlite.close();
      },
    };
  }

  let mod;
  try {
    mod = await import("node:sqlite");
  } catch (error) {
    throw new Error(
      `Node runtime does not expose node:sqlite. Use Bun or a Node version with node:sqlite support. Original error: ${error.message}`,
    );
  }

  const sqlite = new mod.DatabaseSync(dbPath, { readOnly: true });
  return {
    all(sql, params = []) {
      return sqlite.prepare(sql).all(...params);
    },
    get(sql, params = []) {
      return sqlite.prepare(sql).get(...params);
    },
    close() {
      sqlite.close();
    },
  };
}

function tableExists(db, table) {
  const row = db.get("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [table]);
  return Boolean(row);
}

function countTable(db, table, where = "") {
  if (!tableExists(db, table)) return 0;
  const row = db.get(`SELECT COUNT(*) AS count FROM ${table} ${where}`);
  return row?.count ?? 0;
}

function rows(db, sql, params = []) {
  return db.all(sql, params);
}

function jsonTextExpr(alias) {
  return `json_extract(${alias}.data, '$.text')`;
}

function commandSummary(db) {
  return [
    { name: "projects", count: countTable(db, "project") },
    { name: "sessions_main", count: countTable(db, "session", "WHERE parent_id IS NULL") },
    { name: "sessions_total", count: countTable(db, "session") },
    { name: "messages", count: countTable(db, "message") },
    { name: "parts", count: countTable(db, "part") },
    { name: "todos", count: countTable(db, "todo") },
  ];
}

function commandProjects(db, limit) {
  return rows(
    db,
    `
      SELECT
        p.id,
        COALESCE(p.name, CASE WHEN p.worktree = '/' THEN '(global)' ELSE p.worktree END) AS name,
        p.worktree,
        p.vcs,
        datetime(p.time_updated / 1000, 'unixepoch', 'localtime') AS updated,
        (SELECT COUNT(*) FROM session s WHERE s.project_id = p.id AND s.parent_id IS NULL) AS sessions
      FROM project p
      ORDER BY p.time_updated DESC
      LIMIT ?
    `,
    [limit],
  );
}

function commandRecentSessions(db, limit) {
  return rows(
    db,
    `
      SELECT
        s.id,
        s.title,
        s.directory,
        s.project_id AS projectId,
        COALESCE(p.name, p.worktree, '(unknown)') AS project,
        datetime(s.time_updated / 1000, 'unixepoch', 'localtime') AS updated,
        (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) AS messages
      FROM session s
      LEFT JOIN project p ON p.id = s.project_id
      WHERE s.parent_id IS NULL
      ORDER BY s.time_updated DESC, s.id DESC
      LIMIT ?
    `,
    [limit],
  );
}

function commandProjectSessions(db, projectPath, limit) {
  if (!projectPath) throw new Error("ProjectSessions requires --project-path.");
  return rows(
    db,
    `
      SELECT
        s.id,
        s.title,
        s.directory,
        datetime(s.time_updated / 1000, 'unixepoch', 'localtime') AS updated,
        (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) AS messages
      FROM session s
      JOIN project p ON p.id = s.project_id
      WHERE (p.worktree = ? OR s.directory = ?)
        AND s.parent_id IS NULL
      ORDER BY s.time_updated DESC, s.id DESC
      LIMIT ?
    `,
    [projectPath, projectPath, limit],
  );
}

function commandMessages(db, sessionId, limit) {
  if (!sessionId) throw new Error("Messages requires --session-id.");
  return rows(
    db,
    `
      SELECT
        m.id AS messageId,
        json_extract(m.data, '$.role') AS role,
        datetime(m.time_created / 1000, 'unixepoch', 'localtime') AS created,
        GROUP_CONCAT(CASE WHEN json_extract(p.data, '$.type') = 'text' THEN ${jsonTextExpr("p")} END, char(10)) AS text
      FROM message m
      LEFT JOIN part p ON p.message_id = m.id
      WHERE m.session_id = ?
      GROUP BY m.id
      ORDER BY m.time_created ASC, m.id ASC
      LIMIT ?
    `,
    [sessionId, limit],
  );
}

function commandSearch(db, search, limit) {
  if (!search) throw new Error("Search requires --search.");
  return rows(
    db,
    `
      SELECT
        s.id AS sessionId,
        s.title,
        json_extract(m.data, '$.role') AS role,
        datetime(m.time_created / 1000, 'unixepoch', 'localtime') AS created,
        substr(${jsonTextExpr("p")}, 1, 240) AS snippet
      FROM part p
      JOIN message m ON m.id = p.message_id
      JOIN session s ON s.id = m.session_id
      WHERE s.parent_id IS NULL
        AND json_extract(p.data, '$.type') = 'text'
        AND ${jsonTextExpr("p")} LIKE ?
      ORDER BY m.time_created DESC, m.id DESC
      LIMIT ?
    `,
    [`%${search}%`, limit],
  );
}

function statToRecord(file) {
  const stat = fs.statSync(file);
  return {
    path: file,
    name: path.basename(file),
    updated: stat.mtime.toISOString(),
    size: stat.size,
  };
}

function commandPlans(dataRoot, projectPath, limit) {
  const roots = [];
  if (projectPath) roots.push(path.join(projectPath, ".opencode", "plans"));
  roots.push(path.join(dataRoot, "plans"));

  const seen = new Set();
  const files = [];
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    for (const item of fs.readdirSync(root)) {
      if (!item.endsWith(".md")) continue;
      const full = path.join(root, item);
      if (seen.has(full)) continue;
      seen.add(full);
      files.push(statToRecord(full));
    }
  }

  return files.sort((a, b) => b.updated.localeCompare(a.updated)).slice(0, limit);
}

function commandDiffs(diffRoot, sessionId) {
  if (!sessionId) throw new Error("Diffs requires --session-id.");
  const file = path.join(diffRoot, `${sessionId}.json`);
  if (!fs.existsSync(file)) return { path: file, diffs: [] };
  return { path: file, diffs: JSON.parse(fs.readFileSync(file, "utf8")) };
}

function writeOutput(value, json) {
  if (json) {
    process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
    return;
  }
  if (Array.isArray(value)) console.table(value);
  else console.log(value);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.command === "Plans") {
    writeOutput(commandPlans(args.dataRoot, args.projectPath, args.limit), args.json);
    return;
  }
  if (args.command === "Diffs") {
    writeOutput(commandDiffs(args.diffRoot, args.sessionId), args.json);
    return;
  }

  const db = await openReadOnlyDatabase(args.db);
  try {
    const value =
      args.command === "Summary"
        ? commandSummary(db)
        : args.command === "Projects"
          ? commandProjects(db, args.limit)
          : args.command === "RecentSessions"
            ? commandRecentSessions(db, args.limit)
            : args.command === "ProjectSessions"
              ? commandProjectSessions(db, args.projectPath, args.limit)
              : args.command === "Messages"
                ? commandMessages(db, args.sessionId, args.limit)
                : commandSearch(db, args.search, args.limit);
    writeOutput(value, args.json);
  } finally {
    db.close();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
