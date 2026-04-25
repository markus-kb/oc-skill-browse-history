# Project Instructions

## Engineering Workflow
- Use red-green-refactor TDD for every functional change.
  - Red: write or update a failing automated test first.
  - Green: implement the smallest correct change that passes the test.
  - Refactor: improve structure without changing behavior, then rerun tests.
- Track work in ignored `.tasks/todo.md` before implementation starts when a checklist is useful, mark items complete as progress is made, and add a review section with verification results.
- Prefer focused, incremental changes. Avoid unrelated refactors.
- Document intent and responsibilities as if this were an open-source project, especially for non-obvious Windows/OpenCode storage behavior.

## Windows Requirements
- Terminal commands shown to users must be Windows 11 compatible unless explicitly requested otherwise.
- Prefer PowerShell examples for this project.
- Do not require external `sqlite3.exe`; OpenCode uses embedded SQLite runtimes, and this project should mirror that expectation.

## Testing
- Never claim tests were run unless they were actually run.
- Add tests for new features and regression tests for behavior changes.
- Keep tests deterministic and avoid touching a user's real OpenCode data. Use temp directories and temp databases.

## `.gitignore` Maintenance
- Update `.gitignore` whenever adding generated files, caches, temporary outputs, local databases, logs, or secret-bearing files.
- Never commit secrets. Use environment variables or untracked `.env` files for configuration.

## OpenCode Memory Safety
- Treat OpenCode memory as private local user data.
- Read only the specific sessions, plans, diffs, and snippets needed for the user's request.
- Do not modify OpenCode databases, storage files, plan files, or prompt history.
