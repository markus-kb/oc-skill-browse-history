# Windows OpenCode Storage Reference

This reference is based on the current OpenCode source layout for the storage, session, and project modules.

## Runtime Storage

OpenCode does not call an external SQLite CLI. Its database adapter imports `#db`, which resolves to:

- `bun:sqlite` in Bun (`packages/opencode/src/storage/db.bun.ts`)
- `node:sqlite` in Node (`packages/opencode/src/storage/db.node.ts`)

The shared database wrapper in `packages/opencode/src/storage/db.ts` opens `Global.Path.data\opencode.db` by default and applies migrations through Drizzle. For non-standard installation channels, OpenCode may use `opencode-<channel>.db`; `OPENCODE_DB` can also override the path.

On Windows, `Global.Path.data` comes from `xdg-basedir` and resolves to `%USERPROFILE%\.local\share\opencode` unless XDG environment variables are set.

## Tables

The main session data is SQLite:

- `project`: project id, worktree, VCS, name, icon fields, timestamps, sandboxes, commands.
- `session`: session id, project id, optional parent id, directory, title, version, summary fields, revert data, permission data, timestamps, archive/compact timestamps.
- `message`: message id, session id, timestamps, JSON `data` containing the role and message metadata.
- `part`: part id, message id, session id, timestamps, JSON `data` containing text, tool, reasoning, file, and other part payloads.
- `todo`: session id, content, status, priority, position, timestamps.

Session, message, and part rows are written by sync-event projectors in `packages/opencode/src/session/projectors.ts`.

## Non-Database Files

- Session diffs are JSON files under `%USERPROFILE%\.local\share\opencode\storage\session_diff\<session-id>.json`.
- Project plans are markdown files under `<worktree>\.opencode\plans\*.md`.
- Global plans are markdown files under `%USERPROFILE%\.local\share\opencode\plans\*.md`.
- Snapshots, tool output, logs, and bundled binaries may also exist under the data root but are not needed for ordinary memory recall.

## Prompt History

Older memory notes may mention `prompt-history.jsonl`. Current OpenCode desktop prompt history is stored through the app persistence layer, including Tauri store files such as `opencode.global.dat`, not a simple `prompt-history.jsonl` file. Treat prompt history as a separate desktop app persistence concern unless a concrete file is present and the user explicitly asks for it.

## Read-Only Discipline

Readers must never migrate, vacuum, checkpoint, or write to the OpenCode database. Use a runtime that can open SQLite in read-only mode. If read-only opening is not available, fail closed.
