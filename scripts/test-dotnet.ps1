param([ValidateSet('Debug','Release')][string]$Configuration = 'Release')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$privateDotnet = Join-Path $root 'private\toolchain\dotnet\dotnet.exe'
$dotnet = if (Test-Path -LiteralPath $privateDotnet) { $privateDotnet } else { (Get-Command dotnet -ErrorAction Stop).Source }
$toolHome = Join-Path $root 'private\toolchain'
if (-not (Test-Path -LiteralPath $toolHome)) { $toolHome = Join-Path $env:TEMP 'CodexMonitorHudDotnetHome' }
$env:DOTNET_CLI_HOME = $toolHome
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:AVALONIA_TELEMETRY_OPTOUT = '1'
$env:NUGET_PACKAGES = Join-Path $toolHome 'nuget'
& $dotnet run --project (Join-Path $root 'tests-dotnet\CodexMonitorHud.Core.Tests\CodexMonitorHud.Core.Tests.csproj') -c $Configuration
if ($LASTEXITCODE -ne 0) { throw "Core tests failed with exit code $LASTEXITCODE" }
