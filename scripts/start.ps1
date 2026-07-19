param(
    [switch]$Settings,
    [switch]$Managed,
    [switch]$DebugLog,
    [switch]$Legacy
)
$root = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $root 'runtime\win-x64'
$dotnet = Join-Path $runtimeRoot 'dotnet\dotnet.exe'
$app = Join-Path $runtimeRoot 'app\CodexMonitorHud.dll'
$compiledStarted = $false
if (-not $Legacy -and (Test-Path -LiteralPath $dotnet) -and (Test-Path -LiteralPath $app)) {
    $compiledArguments = @(
        ('"{0}"' -f $app),
        '--plugin-root',
        ('"{0}"' -f $root)
    )
    if ($Settings) { $compiledArguments += '--open-settings' }
    if ($Managed) { $compiledArguments += '--managed' }
    if ($DebugLog) { $compiledArguments += '--debug-log' }
    try {
        $process = Start-Process -FilePath $dotnet -WindowStyle Hidden -ArgumentList $compiledArguments -PassThru
        if ($process.WaitForExit(1200)) {
            $compiledStarted = $process.ExitCode -eq 0
        } else {
            $compiledStarted = $true
        }
    } catch {
        $compiledStarted = $false
    }
}
if ($compiledStarted) { return }

$scriptPath = Join-Path $root 'src\CodexMonitorHUD.ps1'
$arguments = @('-NoProfile', '-Sta', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $scriptPath))
if ($Settings) { $arguments += '-OpenSettings' }
if ($Managed) { $arguments += '-Managed' }
if ($DebugLog) { $arguments += '-DebugLog' }
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments
