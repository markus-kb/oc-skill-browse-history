# # OpenCode history browsing for Windows

`oc-browse-history` is a Windows-first OpenCode skill for looking up your local OpenCode history: recent sessions, messages, project records, saved plans, todos, and session diffs.

It is built for OpenCode users who want an agent to answer questions like:

- "What did we do in the last OpenCode session?"
- "Find the session where we discussed Windows storage."
- "Show me saved plans for this project."
- "Did we already debug this issue before?"

## Why This Exists

The original memory-browsing workflow was Unix-oriented and assumed shell tools such as `sqlite3`. On Windows, OpenCode does not manage sessions through an external `sqlite3.exe` command. OpenCode stores session data in SQLite through embedded runtimes such as `bun:sqlite` or `node:sqlite`.

This skill follows that Windows-native model:

- PowerShell is the main entrypoint.
- `sqlite3.exe` is not required.
- Local OpenCode files are read only.
- Broad history queries are limited by default.

## Installation

Copy the `oc-browse-history` folder into your OpenCode skills directory.

For a project-local skill:

```powershell
New-Item -ItemType Directory -Force .opencode\skills | Out-Null
Copy-Item -Recurse .\oc-browse-history .opencode\skills\oc-browse-history
```

For a global skill, copy it into your OpenCode global skills folder:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.config\opencode\skills" | Out-Null
Copy-Item -Recurse .\oc-browse-history "$env:USERPROFILE\.config\opencode\skills\oc-browse-history"
```

Restart OpenCode after copying the skill so it can be discovered.

## How To Use

Ask OpenCode naturally:

```text
Use oc-browse-history to find recent sessions for this project.
```

```text
Search my OpenCode history for "node:sqlite".
```

```text
Show saved plans for this repo.
```

The skill tells the agent to prefer a running OpenCode server/API when available. If that is not available, it uses the bundled PowerShell wrapper and read-only Node/Bun reader.

You can also run the wrapper yourself:

```powershell
.\oc-browse-history\scripts\oc-browse-history.ps1 Paths -Json
.\oc-browse-history\scripts\oc-browse-history.ps1 RecentSessions -Limit 10 -Json
.\oc-browse-history\scripts\oc-browse-history.ps1 Search -Search "Windows storage" -Limit 10 -Json
.\oc-browse-history\scripts\oc-browse-history.ps1 Messages -SessionId "ses_..." -Limit 50 -Json
.\oc-browse-history\scripts\oc-browse-history.ps1 Plans -ProjectPath "C:\path\to\repo" -Json
.\oc-browse-history\scripts\oc-browse-history.ps1 -Plans -Json
.\oc-browse-history\scripts\oc-browse-history.ps1 Diffs -SessionId "ses_..." -Json
```

For project plans, run the command from the project root or pass `-ProjectPath`. The switch form, such as `-Plans`, is accepted for agents that use PowerShell-style command switches.

## What It Reads

By default, OpenCode stores its Windows data under:

```text
%USERPROFILE%\.local\share\opencode
```

The skill reads:

- `%USERPROFILE%\.local\share\opencode\opencode.db`
- `%USERPROFILE%\.local\share\opencode\storage\session_diff\*.json`
- `<project>\.opencode\plans\*.md`
- `%USERPROFILE%\.local\share\opencode\plans\*.md`

If you use `OPENCODE_DB`, `XDG_DATA_HOME`, or `XDG_STATE_HOME`, the wrapper resolves those paths before falling back to `%USERPROFILE%`.

## Privacy And Safety

OpenCode history can contain private code, prompts, tool output, and secrets accidentally pasted into a session. This skill is designed to reduce accidental exposure:

- Database access is read-only.
- The wrapper does not create, migrate, vacuum, checkpoint, or modify OpenCode databases.
- Query commands use `-Limit` to keep output focused.
- Agents are instructed to summarize relevant findings instead of dumping broad history.

Do not share command output publicly unless you have reviewed it.

## Requirements

- Windows 11.
- PowerShell 7 or Windows PowerShell.
- Bun or a Node version that exposes `node:sqlite` for offline database reads.

You do not need `sqlite3.exe`.

## Troubleshooting

If OpenCode memory cannot be read:

- Run `.\oc-browse-history\scripts\oc-browse-history.ps1 Paths -Json` to confirm resolved paths.
- Check that OpenCode has created `%USERPROFILE%\.local\share\opencode\opencode.db`.
- If offline DB reads fail, confirm `node -e "import('node:sqlite')"` works or use Bun.
- If you run OpenCode with a custom database, set `OPENCODE_DB` before running the wrapper.

The skill reference at `oc-browse-history\references\windows-storage.md` documents the Windows storage layout in more detail.

## Credits

This project was inspired by Carson Grossman's [`carson2222/skills`](https://github.com/carson2222/skills), especially the original `opencode-memory` skill. This repository adapts that idea into `oc-browse-history`, a Windows-native implementation for OpenCode users.
