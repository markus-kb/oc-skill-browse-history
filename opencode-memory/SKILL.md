---
name: opencode-memory
description: >
  Browse and recall local OpenCode memory on Windows: sessions, messages, parts,
  todos, project records, saved plans, and session diffs. Use when the user asks
  to check OpenCode history, previous sessions, prior work, plans, local memory,
  session diffs, or whether something was discussed before on this Windows
  machine. Do not use for unrelated ChatGPT or cloud history.
---

# Windows OpenCode Memory

Use this skill to inspect OpenCode local memory on Windows without modifying user data. Prefer a running OpenCode server/API when available; otherwise use the bundled PowerShell entrypoint, which calls a read-only Node/Bun SQLite reader.

OpenCode on Windows does not use external sqlite3.exe. Do not ask the user to install sqlite3.exe and do not shell out to it. OpenCode stores current session data in SQLite through embedded runtimes (`bun:sqlite` or `node:sqlite`), and this skill follows that model.

## Storage Model

- Database: `%USERPROFILE%\.local\share\opencode\opencode.db`, unless `OPENCODE_DB`, channel DB naming, or XDG environment variables override it.
- Session diffs: `%USERPROFILE%\.local\share\opencode\storage\session_diff\<session-id>.json`.
- Project plans: `<worktree>\.opencode\plans\*.md`.
- Global plans: `%USERPROFILE%\.local\share\opencode\plans\*.md`.

Read `references/windows-storage.md` when schema details or source-backed rationale are needed.

## Workflow

1. If the local OpenCode server is known to be running, prefer its API for supported lookups.
2. Otherwise run `scripts\opencode-memory.ps1` from PowerShell.
3. Keep queries focused with `-Limit` and search terms.
4. Summarize relevant findings; do not paste broad raw history dumps.

## Commands

```powershell
.\opencode-memory\scripts\opencode-memory.ps1 Paths -Json
.\opencode-memory\scripts\opencode-memory.ps1 Summary -Json
.\opencode-memory\scripts\opencode-memory.ps1 Projects -Limit 10 -Json
.\opencode-memory\scripts\opencode-memory.ps1 RecentSessions -Limit 10 -Json
.\opencode-memory\scripts\opencode-memory.ps1 ProjectSessions -ProjectPath "C:\path\to\repo" -Limit 10 -Json
.\opencode-memory\scripts\opencode-memory.ps1 Messages -SessionId "ses_..." -Limit 50 -Json
.\opencode-memory\scripts\opencode-memory.ps1 Search -Search "topic" -Limit 10 -Json
.\opencode-memory\scripts\opencode-memory.ps1 Plans -ProjectPath "C:\path\to\repo" -Limit 20 -Json
.\opencode-memory\scripts\opencode-memory.ps1 Diffs -SessionId "ses_..." -Json
```

All database access must be read-only. If the reader cannot open the database read-only, stop and report the failure instead of creating or changing files.

## Privacy Rules

- Read only what is needed for the current request.
- Use `-Limit` on broad queries.
- Do not expose secrets or unrelated private conversation content.
- Never write to OpenCode storage, database, plans, or diff files.
