[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet("Paths", "Summary", "Projects", "RecentSessions", "ProjectSessions", "Messages", "Search", "Plans", "Diffs")]
  [string] $Command = "Summary",

  [switch] $Json,
  [string] $DbPath,
  [string] $DataRoot,
  [string] $ProjectPath,
  [string] $SessionId,
  [string] $Search,
  [int] $Limit = 10,
  [switch] $UseServer,
  [switch] $Paths,
  [switch] $Summary,
  [switch] $Projects,
  [switch] $RecentSessions,
  [switch] $ProjectSessions,
  [switch] $Messages,
  [switch] $Plans,
  [switch] $Diffs
)

$ErrorActionPreference = "Stop"

$Constants = @{
  AppName = "opencode"
  DefaultDb = "opencode.db"
  RelativeDataRoot = ".local\share\opencode"
  SessionDiffRoot = "storage\session_diff"
}

function Resolve-Command {
  $aliases = [ordered]@{
    Paths = $Paths
    Summary = $Summary
    Projects = $Projects
    RecentSessions = $RecentSessions
    ProjectSessions = $ProjectSessions
    Messages = $Messages
    Plans = $Plans
    Diffs = $Diffs
  }

  $selected = @($aliases.GetEnumerator() | Where-Object { $_.Value.IsPresent } | ForEach-Object { $_.Key })
  if ($selected.Count -gt 1) {
    throw "Use only one command switch. Received: $($selected -join ', ')"
  }
  if ($selected.Count -eq 1) {
    if ($Command -ne "Summary") {
      throw "Use either a positional command or a command switch, not both."
    }
    return $selected[0]
  }
  return $Command
}

function Resolve-ProjectPath {
  if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
    return [System.IO.Path]::GetFullPath($ProjectPath)
  }
  return [System.IO.Path]::GetFullPath((Get-Location).Path)
}

function Get-FirstEnv {
  param([string[]] $Names)
  foreach ($name in $Names) {
    $value = [Environment]::GetEnvironmentVariable($name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return $value
    }
  }
  return $null
}

function Resolve-DataRoot {
  if (-not [string]::IsNullOrWhiteSpace($DataRoot)) {
    return [System.IO.Path]::GetFullPath($DataRoot)
  }

  $xdgData = Get-FirstEnv @("XDG_DATA_HOME")
  if ($xdgData) {
    return [System.IO.Path]::GetFullPath((Join-Path $xdgData $Constants.AppName))
  }

  $userHome = Get-FirstEnv @("USERPROFILE", "HOME")
  if (-not $userHome) {
    throw "Cannot resolve OpenCode data root: USERPROFILE and HOME are not set."
  }

  return [System.IO.Path]::GetFullPath((Join-Path $userHome $Constants.RelativeDataRoot))
}

function Resolve-StateRoot {
  $xdgState = Get-FirstEnv @("XDG_STATE_HOME")
  if ($xdgState) {
    return [System.IO.Path]::GetFullPath((Join-Path $xdgState $Constants.AppName))
  }

  $userHome = Get-FirstEnv @("USERPROFILE", "HOME")
  if (-not $userHome) {
    throw "Cannot resolve OpenCode state root: USERPROFILE and HOME are not set."
  }

  return [System.IO.Path]::GetFullPath((Join-Path $userHome ".local\state\opencode"))
}

function Resolve-DatabasePath {
  param([string] $ResolvedDataRoot)

  if (-not [string]::IsNullOrWhiteSpace($DbPath)) {
    return [System.IO.Path]::GetFullPath($DbPath)
  }

  $envDb = Get-FirstEnv @("OPENCODE_DB")
  if ($envDb) {
    if ($envDb -eq ":memory:") {
      throw "OPENCODE_DB=:memory: cannot be inspected after the OpenCode process exits."
    }
    if ([System.IO.Path]::IsPathRooted($envDb)) {
      return [System.IO.Path]::GetFullPath($envDb)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $ResolvedDataRoot $envDb))
  }

  return [System.IO.Path]::GetFullPath((Join-Path $ResolvedDataRoot $Constants.DefaultDb))
}

function Write-Result {
  param([object] $Value)
  if ($Json) {
    $Value | ConvertTo-Json -Depth 20
    return
  }
  $Value | Format-Table -AutoSize
}

function Resolve-ReaderRuntime {
  $bun = Get-Command bun -ErrorAction SilentlyContinue
  if ($bun) {
    return $bun.Source
  }

  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($node) {
    return $node.Source
  }

  throw "Neither Bun nor Node is available. Install or use the same runtime family OpenCode uses for embedded SQLite access."
}

$Command = Resolve-Command
$effectiveProjectPath = Resolve-ProjectPath
$resolvedDataRoot = Resolve-DataRoot
$resolvedStateRoot = Resolve-StateRoot
$resolvedDbPath = Resolve-DatabasePath -ResolvedDataRoot $resolvedDataRoot
$diffRoot = Join-Path $resolvedDataRoot $Constants.SessionDiffRoot

if ($Command -eq "Paths") {
  Write-Result ([ordered]@{
    dataRoot = $resolvedDataRoot
    stateRoot = $resolvedStateRoot
    dbPath = $resolvedDbPath
    diffRoot = $diffRoot
    defaultProjectPlans = Join-Path $effectiveProjectPath ".opencode\plans"
    globalPlans = Join-Path $resolvedDataRoot "plans"
  })
  exit 0
}

if ($UseServer) {
  try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:4096/api/health" -TimeoutSec 2
    if ($Command -eq "Summary") {
      Write-Result ([ordered]@{
        source = "server"
        health = $health
        note = "Server is reachable. Use OpenCode API endpoints for supported lookups; falling back to local read-only storage for this command."
      })
    }
  } catch {
    Write-Verbose "OpenCode server is not reachable; using local read-only storage."
  }
}

$reader = Join-Path $PSScriptRoot "read-opencode-memory.mjs"
if (-not (Test-Path -LiteralPath $reader)) {
  throw "Reader not found: $reader"
}

$runtime = Resolve-ReaderRuntime
$args = @(
  "--command", $Command,
  "--db", $resolvedDbPath,
  "--data-root", $resolvedDataRoot,
  "--diff-root", $diffRoot,
  "--limit", [string] $Limit
)

if ($Json) { $args += "--json" }
if ($effectiveProjectPath) { $args += @("--project-path", $effectiveProjectPath) }
if ($SessionId) { $args += @("--session-id", $SessionId) }
if ($Search) { $args += @("--search", $Search) }

$runtimeName = [System.IO.Path]::GetFileNameWithoutExtension($runtime)
if ($runtimeName -eq "node") {
  & $runtime "--no-warnings" $reader @args
} else {
  & $runtime $reader @args
}
exit $LASTEXITCODE
