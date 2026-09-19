# Launcher for check.lua. Finds lua.exe even when PATH has not been refreshed
# (a terminal opened before `winget install DEVCOM.Lua` keeps a stale PATH).
#   .\check.ps1

$lua = $null
$cmd = Get-Command lua -ErrorAction SilentlyContinue
if ($cmd) { $lua = $cmd.Source }
if (-not $lua) {
  $fallback = Join-Path $env:LOCALAPPDATA "Programs\Lua\bin\lua.exe"
  if (Test-Path $fallback) { $lua = $fallback }
}
if (-not $lua) {
  Write-Output "Lua not found. Install it with:  winget install DEVCOM.Lua"
  exit 1
}

Push-Location $PSScriptRoot
try {
  & $lua "check.lua" @args
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}
exit $code
