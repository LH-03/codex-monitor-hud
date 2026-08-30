param(
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release',
    [switch]$SkipTests,
    [switch]$RunRuntimeTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$privateDotnet = Join-Path $root 'private\toolchain\dotnet\dotnet.exe'
$dotnet = if (Test-Path -LiteralPath $privateDotnet) {
    $privateDotnet
} else {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw 'The .NET 10 SDK is required to build v3.2.1. The repository-private SDK was not found and dotnet is not on PATH.' }
    $command.Source
}
$dotnetRoot = Split-Path -Parent $dotnet
$toolHome = Join-Path $root 'private\toolchain'
if (-not (Test-Path -LiteralPath $toolHome)) { $toolHome = Join-Path $env:TEMP 'CodexMonitorHudDotnetHome' }
New-Item -ItemType Directory -Force -Path $toolHome | Out-Null
$env:DOTNET_CLI_HOME = $toolHome
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:AVALONIA_TELEMETRY_OPTOUT = '1'
$env:NUGET_PACKAGES = Join-Path $toolHome 'nuget'

& $dotnet build (Join-Path $root 'CodexMonitorHud.slnx') -c $Configuration
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
if (-not $SkipTests) {
    & $dotnet run --project (Join-Path $root 'tests-dotnet\CodexMonitorHud.Core.Tests\CodexMonitorHud.Core.Tests.csproj') -c $Configuration --no-build -- $root
    if ($LASTEXITCODE -ne 0) { throw "Core tests failed with exit code $LASTEXITCODE" }
}

$stage = Join-Path $root 'runtime\win-x64'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$appStage = Join-Path $stage 'app'
$runtimeStage = Join-Path $stage 'dotnet'
New-Item -ItemType Directory -Force -Path $appStage,$runtimeStage | Out-Null
& $dotnet publish (Join-Path $root 'src-dotnet\CodexMonitorHud.App\CodexMonitorHud.App.csproj') -c $Configuration --no-build --no-restore --self-contained false -o $appStage
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

$coreRuntime = Get-ChildItem -LiteralPath (Join-Path $dotnetRoot 'shared\Microsoft.NETCore.App') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$desktopRuntime = Get-ChildItem -LiteralPath (Join-Path $dotnetRoot 'shared\Microsoft.WindowsDesktop.App') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$hostFxr = Get-ChildItem -LiteralPath (Join-Path $dotnetRoot 'host\fxr') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($null -eq $coreRuntime -or $null -eq $desktopRuntime -or $null -eq $hostFxr) { throw 'The selected SDK does not contain the required Windows Desktop runtime.' }
Copy-Item -LiteralPath $dotnet -Destination (Join-Path $runtimeStage 'dotnet.exe') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $runtimeStage 'host\fxr'),(Join-Path $runtimeStage 'shared\Microsoft.NETCore.App'),(Join-Path $runtimeStage 'shared\Microsoft.WindowsDesktop.App') | Out-Null
Copy-Item -LiteralPath $hostFxr.FullName -Destination (Join-Path $runtimeStage 'host\fxr') -Recurse -Force
Copy-Item -LiteralPath $coreRuntime.FullName -Destination (Join-Path $runtimeStage 'shared\Microsoft.NETCore.App') -Recurse -Force
Copy-Item -LiteralPath $desktopRuntime.FullName -Destination (Join-Path $runtimeStage 'shared\Microsoft.WindowsDesktop.App') -Recurse -Force

$metadata = [ordered]@{
    product = 'Codex Monitor HUD'
    version = '3.2.1'
    configuration = $Configuration
    framework = 'net10.0-windows'
    runtime = $coreRuntime.Name
    windows_desktop_runtime = $desktopRuntime.Name
}
[IO.File]::WriteAllText((Join-Path $stage 'runtime.json'), ($metadata | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$healthPath = Join-Path $stage 'health-check.json'
& (Join-Path $runtimeStage 'dotnet.exe') (Join-Path $appStage 'CodexMonitorHud.dll') --plugin-root $root --health-check $healthPath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $healthPath)) { throw 'Staged compiled runtime health check failed.' }
$health = Get-Content -Raw -Encoding UTF8 -LiteralPath $healthPath | ConvertFrom-Json
if ([string]$health.version -ne '3.2.1' -or [string]$health.config -ne 'ok' -or [string]$health.xaml -ne 'ok' -or [string]$health.parser -ne 'ok') {
    throw ('Staged compiled runtime health check returned an invalid result: ' + ($health | ConvertTo-Json -Compress))
}
if ($RunRuntimeTests) {
    $runtimeGateRoot = Join-Path $env:TEMP ('codex-monitor-hud-staged-gate-' + [Guid]::NewGuid().ToString('N'))
    try {
        & (Join-Path $root 'scripts\test-runtime-isolated.ps1') -HostMode compiled -Mode list -TaskCount 5 -ChurnCycles 0 -TestOutputRoot $runtimeGateRoot
        & (Join-Path $root 'scripts\test-runtime-isolated.ps1') -HostMode compiled -Mode split -TaskCount 5 -ChurnCycles 0 -TestOutputRoot $runtimeGateRoot
    } finally {
        if (Test-Path -LiteralPath $runtimeGateRoot) { Remove-Item -LiteralPath $runtimeGateRoot -Recurse -Force }
    }
}
Write-Output "Compiled runtime staged: $stage"
