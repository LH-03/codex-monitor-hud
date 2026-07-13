param(
    [string]$TargetRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$startScript = Join-Path $TargetRoot 'scripts\start.ps1'
$shell = New-Object -ComObject WScript.Shell
$startMenuFolder = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Token HUD'
$desktop = [Environment]::GetFolderPath('Desktop')
New-Item -ItemType Directory -Force -Path $startMenuFolder | Out-Null

foreach ($path in @(
    (Join-Path $startMenuFolder 'Open Token HUD Settings.lnk'),
    (Join-Path $desktop 'Codex Token HUD Settings.lnk')
)) {
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Settings' -f $startScript)
    $shortcut.WorkingDirectory = $TargetRoot
    $shortcut.Description = 'Open Codex Token HUD settings'
    $shortcut.Save()
}

Write-Output "Desktop shortcut: $(Join-Path $desktop 'Codex Token HUD Settings.lnk')"
Write-Output "Start menu shortcut: $(Join-Path $startMenuFolder 'Open Token HUD Settings.lnk')"
