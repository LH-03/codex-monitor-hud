param([Parameter(Mandatory=$true)][string]$TestOutputRoot)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $TestOutputRoot 'install-transaction'
$profileRoot = Join-Path $fixtureRoot 'profile'
$localAppData = Join-Path $fixtureRoot 'localappdata'
$pluginsRoot = Join-Path $profileRoot 'plugins'
$targetRoot = Join-Path $pluginsRoot 'codex-monitor-hud'
$rollback22 = Join-Path $pluginsRoot '.codex-monitor-hud-rollback-2.2.0'
$marketplacePath = Join-Path $profileRoot '.agents\plugins\marketplace.json'
$encoding = New-Object Text.UTF8Encoding($false)

function New-FixturePlugin {
    param([string]$Path, [string]$Version, [bool]$FailStart)
    foreach ($directory in @('.codex-plugin','scripts','src')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Path $directory) | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $Path '.codex-plugin\plugin.json'), ('{"name":"codex-monitor-hud","version":"' + $Version + '"}'), $encoding)
    [IO.File]::WriteAllText((Join-Path $Path 'config.default.json'), '{"language":"en"}', $encoding)
    [IO.File]::WriteAllText((Join-Path $Path 'src\CodexMonitorHUD.ps1'), "param()`n", $encoding)
    [IO.File]::WriteAllText((Join-Path $Path 'scripts\create-shortcuts.ps1'), "param([string]`$TargetRoot)`n", $encoding)
    $startBody = if ($FailStart) { "param([switch]`$Settings)`nthrow 'synthetic post-switch failure'`n" } else { "param([switch]`$Settings)`n" }
    [IO.File]::WriteAllText((Join-Path $Path 'scripts\start.ps1'), $startBody, $encoding)
}

function Invoke-IsolatedRollback {
    param([string]$Version)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    # Windows PowerShell 5.1 exposes the modern Environment dictionary through
    # a lazy compatibility getter whose first access can return null.
    $null = $info.Environment
    $info.Environment['HOME'] = $profileRoot
    $info.Environment['USERPROFILE'] = $profileRoot
    $info.Environment['LOCALAPPDATA'] = $localAppData
    $installPath = Join-Path $root 'scripts\install.ps1'
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $installPath + '" -RollbackVersion ' + $Version
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    if (-not $process.WaitForExit(15000)) {
        $process.Kill()
        throw 'Isolated install transaction test timed out.'
    }
    return [pscustomobject]@{ ExitCode=$process.ExitCode; Stdout=$stdout; Stderr=$stderr }
}

function Get-FixtureVersion {
    param([string]$Path)
    return [string](Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Path '.codex-plugin\plugin.json') | ConvertFrom-Json).version
}

try {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $pluginsRoot,(Split-Path -Parent $marketplacePath),$localAppData | Out-Null
    New-FixturePlugin $targetRoot '3.0.0' $true
    New-FixturePlugin $rollback22 '2.2.0' $false
    foreach ($unsafeDirectory in @('.agents','nested\bin','nested\obj')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $rollback22 $unsafeDirectory) | Out-Null
    }
    foreach ($unsafeRelativePath in @('.agents\local.txt','nested\bin\leak.dll','nested\obj\leak.cache','nested\session.jsonl','.env.local','settings.json')) {
        [IO.File]::WriteAllText((Join-Path $rollback22 $unsafeRelativePath), 'synthetic local-only data', $encoding)
    }
    [IO.File]::WriteAllText($marketplacePath, '{"name":"personal","plugins":[]}', $encoding)

    $success = Invoke-IsolatedRollback '2.2.0'
    if ($success.ExitCode -ne 0 -or (Get-FixtureVersion $targetRoot) -ne '2.2.0') {
        throw ('Successful rollback transaction failed: ' + $success.Stderr)
    }
    foreach ($unsafeRelativePath in @('.agents','nested\bin','nested\obj','nested\session.jsonl','.env.local','settings.json')) {
        if (Test-Path -LiteralPath (Join-Path $targetRoot $unsafeRelativePath)) { throw "Installer copied excluded material: $unsafeRelativePath" }
    }
    $rollback30 = Join-Path $pluginsRoot '.codex-monitor-hud-rollback-3.0.0'
    if ((Get-FixtureVersion $rollback30) -ne '3.0.0') { throw 'Successful rollback did not retain the previous 3.0.0 tree.' }
    $marketplaceBeforeFailure = [IO.File]::ReadAllBytes($marketplacePath)

    $failure = Invoke-IsolatedRollback '3.0.0'
    if ($failure.ExitCode -eq 0) { throw 'Synthetic post-switch failure unexpectedly succeeded.' }
    if ((Get-FixtureVersion $targetRoot) -ne '2.2.0') { throw 'Failed post-switch action did not restore the prior installed tree.' }
    $beforeBase64 = [Convert]::ToBase64String($marketplaceBeforeFailure)
    $afterBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($marketplacePath))
    if ($beforeBase64 -ne $afterBase64) {
        throw 'Failed post-switch action did not restore the marketplace file exactly.'
    }
    Write-Output 'Transactional install rollback: OK'
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}
