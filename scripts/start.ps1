param(
    [switch]$Settings,
    [switch]$Managed,
    [switch]$DebugLog
)
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\CodexMonitorHUD.ps1'
$arguments = @('-NoProfile', '-Sta', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $scriptPath))
if ($Settings) { $arguments += '-OpenSettings' }
if ($Managed) { $arguments += '-Managed' }
if ($DebugLog) { $arguments += '-DebugLog' }
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments
