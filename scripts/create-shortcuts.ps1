param(
    [string]$TargetRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$startScript = Join-Path $TargetRoot 'scripts\start.ps1'
$sourceIconPath = Join-Path $TargetRoot 'assets\codex-monitor-hud.ico'
$manifestPath = Join-Path $TargetRoot '.codex-plugin\plugin.json'
$buildVersion = if (Test-Path -LiteralPath $manifestPath) { [string](Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json).version } else { 'current' }
$safeVersion = [regex]::Replace($buildVersion, '[^A-Za-z0-9._-]', '_')
$iconCacheRoot = Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD\icons'
$iconPath = Join-Path $iconCacheRoot ('codex-monitor-hud-' + $safeVersion + '.ico')
New-Item -ItemType Directory -Force -Path $iconCacheRoot | Out-Null
if (Test-Path -LiteralPath $sourceIconPath) { Copy-Item -LiteralPath $sourceIconPath -Destination $iconPath -Force }
$shell = New-Object -ComObject WScript.Shell
$startMenuFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Monitor HUD'
$desktop = [Environment]::GetFolderPath('Desktop')
New-Item -ItemType Directory -Force -Path $startMenuFolder | Out-Null

foreach ($path in @(
    (Join-Path $startMenuFolder 'Open Monitor HUD Settings.lnk'),
    (Join-Path $desktop 'Codex Monitor HUD Settings.lnk')
)) {
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Settings' -f $startScript)
    $shortcut.WorkingDirectory = $TargetRoot
    $shortcut.Description = 'Open Codex Monitor HUD settings'
    if (Test-Path -LiteralPath $iconPath) { $shortcut.IconLocation = $iconPath + ',0' }
    $shortcut.Save()
}

# A build-specific icon path avoids Explorer retaining the previous design for
# a stable .lnk name. Ask Explorer to refresh after both shortcuts are saved.
$iconRefresh = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
if (Test-Path -LiteralPath $iconRefresh) { & $iconRefresh -show 2>$null }

Write-Output "Desktop shortcut: $(Join-Path $desktop 'Codex Monitor HUD Settings.lnk')"
Write-Output "Start menu shortcut: $(Join-Path $startMenuFolder 'Open Monitor HUD Settings.lnk')"
