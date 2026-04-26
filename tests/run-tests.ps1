$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
  param([string] $Message)
  $Failures.Add($Message)
}

function Assert-True {
  param(
    [bool] $Condition,
    [string] $Message
  )
  if (-not $Condition) {
    Add-Failure $Message
  }
}

function Read-Text {
  param([string] $RelativePath)
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    Add-Failure "Missing required file: $RelativePath"
    return ""
  }
  return Get-Content -LiteralPath $path -Raw
}

function Invoke-JsonCommand {
  param(
    [string[]] $Arguments,
    [hashtable] $Environment = @{},
    [string] $WorkingDirectory = $RepoRoot
  )

  $script = Join-Path $RepoRoot "oc-browse-history\scripts\oc-browse-history.ps1"
  if (-not (Test-Path -LiteralPath $script)) {
    Add-Failure "Missing PowerShell wrapper: oc-browse-history\scripts\oc-browse-history.ps1"
    return $null
  }

  $old = @{}
  foreach ($key in $Environment.Keys) {
    $old[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    [Environment]::SetEnvironmentVariable($key, [string] $Environment[$key], "Process")
  }

  try {
    Push-Location -LiteralPath $WorkingDirectory
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
      Add-Failure "Command failed: $($Arguments -join ' ')`n$output"
      return $null
    }
    return ($output | Out-String | ConvertFrom-Json)
  } finally {
    Pop-Location
    foreach ($key in $Environment.Keys) {
      [Environment]::SetEnvironmentVariable($key, $old[$key], "Process")
    }
  }
}

$agents = Read-Text "AGENTS.md"
Assert-True ($agents -match "red-green-refactor") "AGENTS.md must require red-green-refactor TDD."
Assert-True ($agents -match "\.tasks/todo\.md") "AGENTS.md must require ignored task tracking in .tasks/todo.md."
Assert-True ($agents -match "\.gitignore") "AGENTS.md must require .gitignore maintenance."
Assert-True ($agents -match "Windows 11") "AGENTS.md must require Windows 11-compatible user commands."

$gitignore = Read-Text ".gitignore"
foreach ($pattern in @(".env", "*.log", "node_modules/", "*.db", "*.db-wal", "*.db-shm", ".DS_Store", "Thumbs.db")) {
  Assert-True ($gitignore.Contains($pattern)) ".gitignore must include $pattern."
}
Assert-True ($gitignore.Contains(".tasks/")) ".gitignore must include hidden local task scratch space."

$readme = Read-Text "README.md"
Assert-True ($readme -match "OpenCode") "README.md must be written for OpenCode users."
Assert-True ($readme -match "Windows") "README.md must explain Windows support."
Assert-True ($readme -match "Install|installation") "README.md must include installation guidance."
Assert-True ($readme -match "PowerShell") "README.md must include PowerShell usage."
Assert-True ($readme -match "sqlite3\.exe") "README.md must explain that sqlite3.exe is not required."
Assert-True ($readme -match "Privacy|private|read-only") "README.md must cover privacy/read-only behavior."
Assert-True ($readme -match "oc-browse-history") "README.md must name the skill."

$skill = Read-Text "oc-browse-history/SKILL.md"
Assert-True ($skill -match "Windows") "SKILL.md must be Windows-first."
Assert-True ($skill -match "PowerShell") "SKILL.md must prefer PowerShell."
Assert-True ($skill -match "sqlite3\.exe") "SKILL.md must explicitly say external sqlite3.exe is not required."
Assert-True ($skill -match "does not use external sqlite3\.exe") "SKILL.md must not recommend installing sqlite3.exe."
Assert-True ($skill -match "OpenCode server") "SKILL.md must prefer a running OpenCode server/API."
Assert-True ($skill -match "Node|Bun") "SKILL.md must document Node/Bun SQLite fallback."
Assert-True ($skill -match "mode=ro|read-only") "SKILL.md must require read-only DB access."
Assert-True ($skill -match "%USERPROFILE%\\\.local\\share\\opencode\\opencode\.db") "SKILL.md must document the Windows DB path."
Assert-True ($skill -match "storage\\session_diff") "SKILL.md must document session diff storage."
Assert-True ($skill -match "\.opencode\\plans") "SKILL.md must document project-local plans."

$reference = Read-Text "oc-browse-history/references/windows-storage.md"
Assert-True ($reference -match "bun:sqlite") "Reference must cite Bun SQLite storage."
Assert-True ($reference -match "node:sqlite") "Reference must cite Node SQLite storage."
Assert-True ($reference -match "session") "Reference must document session storage."
Assert-True ($reference -match "message") "Reference must document message storage."
Assert-True ($reference -match "part") "Reference must document part storage."
Assert-True ($reference -match "prompt-history\.jsonl") "Reference must explain the prompt-history.jsonl change."

$wrapper = Read-Text "oc-browse-history/scripts/oc-browse-history.ps1"
Assert-True ($wrapper -match "param") "PowerShell wrapper must define parameters."
Assert-True ($wrapper -match "read-oc-browse-history\.mjs") "PowerShell wrapper must invoke the JS reader."
Assert-True ($wrapper -notmatch "sqlite3(\.exe)?\s") "PowerShell wrapper must not invoke sqlite3."

$reader = Read-Text "oc-browse-history/scripts/read-oc-browse-history.mjs"
Assert-True ($reader -match "bun:sqlite") "JS reader must support Bun SQLite."
Assert-True ($reader -match "node:sqlite") "JS reader must support Node SQLite."
Assert-True ($reader -match "readOnly|readonly") "JS reader must open SQLite read-only."
Assert-True ($reader -notmatch "sqlite3(\.exe)?") "JS reader must not shell out to sqlite3."

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("oc-memory-home-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempHome -Force | Out-Null
$pathsDefault = Invoke-JsonCommand @("Paths", "-Json") @{ USERPROFILE = $tempHome; OPENCODE_DB = ""; XDG_DATA_HOME = "" }
if ($null -ne $pathsDefault) {
  $expectedDb = Join-Path $tempHome ".local\share\opencode\opencode.db"
  Assert-True ($pathsDefault.dbPath -eq $expectedDb) "Default DB path should resolve to USERPROFILE .local share opencode."
}

$xdgRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("oc-memory-xdg-" + [Guid]::NewGuid().ToString("N"))
$pathsXdg = Invoke-JsonCommand @("Paths", "-Json") @{ USERPROFILE = $tempHome; OPENCODE_DB = ""; XDG_DATA_HOME = $xdgRoot }
if ($null -ne $pathsXdg) {
  $expectedDb = Join-Path $xdgRoot "opencode\opencode.db"
  Assert-True ($pathsXdg.dbPath -eq $expectedDb) "XDG_DATA_HOME should override USERPROFILE data root."
}

$customDb = Join-Path ([System.IO.Path]::GetTempPath()) ("custom-" + [Guid]::NewGuid().ToString("N") + ".db")
$pathsCustom = Invoke-JsonCommand @("Paths", "-Json") @{ USERPROFILE = $tempHome; OPENCODE_DB = $customDb; XDG_DATA_HOME = "" }
if ($null -ne $pathsCustom) {
  Assert-True ($pathsCustom.dbPath -eq $customDb) "Absolute OPENCODE_DB should override default DB path."
}

$nodeSqliteAvailable = $false
try {
  $null = & node -e "import('node:sqlite').then(()=>process.exit(0)).catch(()=>process.exit(1))" 2>$null
  $nodeSqliteAvailable = $LASTEXITCODE -eq 0
} catch {
  $nodeSqliteAvailable = $false
}

if ($nodeSqliteAvailable) {
  $integrationRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("oc-memory-it-" + [Guid]::NewGuid().ToString("N"))
  $dataRoot = Join-Path $integrationRoot "data"
  $projectRoot = Join-Path $integrationRoot "project"
  $dbPath = Join-Path $dataRoot "opencode.db"
  $diffRoot = Join-Path $dataRoot "storage\session_diff"
  $planRoot = Join-Path $projectRoot ".opencode\plans"
  New-Item -ItemType Directory -Path $dataRoot, $diffRoot, $planRoot -Force | Out-Null

  $setupScript = Join-Path $integrationRoot "setup.mjs"
  @'
import { DatabaseSync } from 'node:sqlite';
const db = new DatabaseSync(process.argv[2]);
db.exec(`
  CREATE TABLE project (
    id TEXT PRIMARY KEY,
    worktree TEXT NOT NULL,
    vcs TEXT,
    name TEXT,
    icon_url TEXT,
    icon_url_override TEXT,
    icon_color TEXT,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL,
    time_initialized INTEGER,
    sandboxes TEXT NOT NULL,
    commands TEXT
  );
  CREATE TABLE session (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    workspace_id TEXT,
    parent_id TEXT,
    slug TEXT NOT NULL,
    directory TEXT NOT NULL,
    title TEXT NOT NULL,
    version TEXT NOT NULL,
    share_url TEXT,
    summary_additions INTEGER,
    summary_deletions INTEGER,
    summary_files INTEGER,
    summary_diffs TEXT,
    revert TEXT,
    permission TEXT,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL,
    time_compacting INTEGER,
    time_archived INTEGER
  );
  CREATE TABLE message (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL,
    data TEXT NOT NULL
  );
  CREATE TABLE part (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL,
    data TEXT NOT NULL
  );
  CREATE TABLE todo (
    session_id TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT NOT NULL,
    priority TEXT NOT NULL,
    position INTEGER NOT NULL,
    time_created INTEGER NOT NULL,
    time_updated INTEGER NOT NULL
  );
`);
const now = 1710000000000;
db.prepare('INSERT INTO project VALUES (?, ?, ?, ?, NULL, NULL, NULL, ?, ?, NULL, ?, NULL)')
  .run('proj_1', process.argv[3], 'git', 'Example Project', now, now, '[]');
db.prepare('INSERT INTO session VALUES (?, ?, NULL, NULL, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?, NULL, NULL)')
  .run('ses_1', 'proj_1', 'slug', process.argv[3], 'Investigate Windows memory', '1.0.0', now, now);
db.prepare('INSERT INTO message VALUES (?, ?, ?, ?, ?)')
  .run('msg_1', 'ses_1', now, now, JSON.stringify({ role: 'user', time: { created: now }, agent: 'build', model: { providerID: 'test', modelID: 'test' } }));
db.prepare('INSERT INTO part VALUES (?, ?, ?, ?, ?, ?)')
  .run('prt_1', 'msg_1', 'ses_1', now, now, JSON.stringify({ type: 'text', text: 'windows native memory search target' }));
db.prepare('INSERT INTO todo VALUES (?, ?, ?, ?, ?, ?, ?)')
  .run('ses_1', 'write tests', 'completed', 'high', 0, now, now);
db.close();
'@ | Set-Content -LiteralPath $setupScript -Encoding utf8

  & node $setupScript $dbPath $projectRoot | Out-Null
  Set-Content -LiteralPath (Join-Path $planRoot "1710000000000-plan.md") -Value "# Plan`nWindows native plan" -Encoding utf8
  Set-Content -LiteralPath (Join-Path $diffRoot "ses_1.json") -Value '[{"path":"file.ts","additions":1,"deletions":0}]' -Encoding utf8

  $summary = Invoke-JsonCommand @("Summary", "-DbPath", $dbPath, "-DataRoot", $dataRoot, "-Json") @{}
  if ($null -ne $summary) {
    Assert-True (($summary | Where-Object { $_.name -eq "sessions_total" }).count -eq 1) "Integration Summary should count one session."
  }

  $sessions = Invoke-JsonCommand @("ProjectSessions", "-DbPath", $dbPath, "-DataRoot", $dataRoot, "-ProjectPath", $projectRoot, "-Json") @{}
  if ($null -ne $sessions) {
    Assert-True ($sessions[0].id -eq "ses_1") "Integration ProjectSessions should return ses_1."
  }

  $messages = Invoke-JsonCommand @("Messages", "-DbPath", $dbPath, "-DataRoot", $dataRoot, "-SessionId", "ses_1", "-Json") @{}
  if ($null -ne $messages) {
    Assert-True ($messages[0].text -match "windows native memory") "Integration Messages should read text parts."
  }

  $search = Invoke-JsonCommand @("Search", "-DbPath", $dbPath, "-DataRoot", $dataRoot, "-Search", "search target", "-Json") @{}
  if ($null -ne $search) {
    Assert-True ($search[0].sessionId -eq "ses_1") "Integration Search should find the seeded text part."
  }

  $plans = Invoke-JsonCommand @("Plans", "-DbPath", $dbPath, "-DataRoot", $dataRoot, "-ProjectPath", $projectRoot, "-Json") @{}
  if ($null -ne $plans) {
    Assert-True ($plans[0].name -eq "1710000000000-plan.md") "Integration Plans should list project-local plan files."
  }

  $plansFromCurrentDirectory = Invoke-JsonCommand @("-Plans", "-DbPath", $dbPath, "-DataRoot", $dataRoot, "-Json") @{} $projectRoot
  if ($null -ne $plansFromCurrentDirectory) {
    Assert-True ($plansFromCurrentDirectory[0].name -eq "1710000000000-plan.md") "Integration -Plans should list current-directory project plans."
  }

  $diffs = Invoke-JsonCommand @("Diffs", "-DbPath", $dbPath, "-DataRoot", $dataRoot, "-SessionId", "ses_1", "-Json") @{}
  if ($null -ne $diffs) {
    Assert-True ($diffs.diffs[0].path -eq "file.ts") "Integration Diffs should read session diff JSON."
  }
}

if ($Failures.Count -gt 0) {
  Write-Host "FAILED $($Failures.Count) test(s):"
  foreach ($failure in $Failures) {
    Write-Host "- $failure"
  }
  exit 1
}

Write-Host "All tests passed."
