param(
    [ValidateSet('list','split')][string]$Mode = 'list',
    [string]$TestOutputRoot
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outputRoot = if ([string]::IsNullOrWhiteSpace($TestOutputRoot)) { Join-Path $root '.test-output' } else { $TestOutputRoot }
$testRoot = Join-Path $outputRoot ('terminal-exit-' + $Mode)
$profileRoot = Join-Path $testRoot 'profile'
$localAppData = Join-Path $testRoot 'localapp'
$stateRoot = Join-Path $localAppData 'CodexMonitorHUD'
$sessionRoot = Join-Path $profileRoot ('.codex\sessions\' + (Get-Date).ToString('yyyy\MM\dd'))
$sessionIndexPath = Join-Path $profileRoot '.codex\session_index.jsonl'
$runtimeLog = Join-Path $outputRoot 'runtime.log'
$encoding = New-Object Text.UTF8Encoding($false)

if (Test-Path -LiteralPath $testRoot) {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $allowed = [IO.Path]::GetFullPath($outputRoot)
    if (-not $resolved.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe terminal-exit test root.' }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $sessionRoot,$stateRoot | Out-Null
Remove-Item -LiteralPath $runtimeLog -Force -ErrorAction SilentlyContinue

$now = [DateTimeOffset]::Now
$sessionId = 'synthetic-terminal-exit-' + $Mode
$workspace = 'terminal-exit-' + $Mode
$sessionPath = Join-Path $sessionRoot 'synthetic-terminal-exit.jsonl'
$records = @(
    ([ordered]@{ timestamp=$now.AddSeconds(-4).ToString('O'); type='session_meta'; payload=[ordered]@{ id=$sessionId; cwd=('C:\Synthetic\' + $workspace); originator='Codex Desktop'; source='vscode' } } | ConvertTo-Json -Compress -Depth 6),
    ([ordered]@{ timestamp=$now.AddSeconds(-3).ToString('O'); type='turn_context'; payload=[ordered]@{ cwd=('C:\Synthetic\' + $workspace); model='gpt-5' } } | ConvertTo-Json -Compress -Depth 5),
    ([ordered]@{ timestamp=$now.AddSeconds(-2).ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_started'; turn_id='turn-terminal-exit' } } | ConvertTo-Json -Compress -Depth 4),
    ([ordered]@{ timestamp=$now.AddSeconds(-1).ToString('O'); type='event_msg'; payload=[ordered]@{ type='token_count'; info=[ordered]@{ last_token_usage=[ordered]@{ input_tokens=1200; cached_input_tokens=800; output_tokens=160; reasoning_output_tokens=20; total_tokens=1380 }; total_token_usage=[ordered]@{ total_tokens=1380 }; model_context_window=200000 } } } | ConvertTo-Json -Compress -Depth 8),
    ([ordered]@{ timestamp=$now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_complete'; turn_id='turn-terminal-exit'; last_agent_message='Synthetic completion.' } } | ConvertTo-Json -Compress -Depth 4)
)
[IO.File]::WriteAllLines($sessionPath,[string[]]$records,$encoding)
$indexEntry = [ordered]@{ id=$sessionId; thread_name='Synthetic terminal exit'; updated_at=$now.ToString('O') } | ConvertTo-Json -Compress
[IO.File]::WriteAllText($sessionIndexPath,($indexEntry+[Environment]::NewLine),$encoding)

$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
$config.language = 'en'
$config.activeWindowMinutes = 60
$config.multiTask.displayMode = $Mode
$config.multiTask.maxSplitBubbles = 2
$config.statusTiming.terminalHoldSeconds = 0
$config.statusTiming.terminalExitMode = 'beacon'
$config.attention.onCompleted = $false
$config.attention.onAbortedOrError = $false
$config.attention.onSettled = $false
$config.attention.dotEnabled = $false
$config.attention.summaryMode = 'off'
$config.attention.listMode = 'off'
$config.attention.taskBubbleMode = 'off'
[IO.File]::WriteAllText((Join-Path $stateRoot 'settings.json'),($config | ConvertTo-Json -Depth 10),$encoding)

$savedLocalAppData = $env:LOCALAPPDATA
$savedUserProfile = $env:USERPROFILE
$savedHome = $env:HOME
$savedModuleAnalysisCache = $env:PSModuleAnalysisCachePath
$savedDebugPath = $env:CODEX_MONITOR_HUD_DEBUG_PATH
$process = $null
try {
    $env:LOCALAPPDATA = $localAppData
    $env:USERPROFILE = $profileRoot
    $env:HOME = $profileRoot
    $env:PSModuleAnalysisCachePath = Join-Path $testRoot 'ModuleAnalysisCache'
    $env:CODEX_MONITOR_HUD_DEBUG_PATH = $runtimeLog
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'src\CodexMonitorHUD.ps1'),
        '-InstanceId',('isolated-terminal-exit-' + $Mode),'-DebugLog'
    ) -PassThru -WindowStyle Hidden

    $heartbeat = Join-Path $stateRoot 'hud.heartbeat'
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $heartbeat) -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) { Start-Sleep -Milliseconds 200; $process.Refresh() }
    if (-not (Test-Path -LiteralPath $heartbeat)) { throw 'Terminal-exit HUD did not reach heartbeat.' }

    $registryPath = Join-Path $stateRoot 'task-registry.json'
    $surfaceName = if ($Mode -eq 'split') { 'bubble' } else { 'list' }
    $surfacePattern = 'Terminal exit surface: ' + $surfaceName + ' ' + [regex]::Escape($workspace)
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    $logText = ''
    while ($logText -notmatch $surfacePattern -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
        Start-Sleep -Milliseconds 200
        if (Test-Path -LiteralPath $runtimeLog) { $logText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog }
        $process.Refresh()
    }
    if ($logText -notmatch $surfacePattern) { throw "Targeted $Mode terminal-exit surface did not start." }
    $duringRegistry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
    if (@($duringRegistry.tasks | Where-Object { [string]$_.workspace -eq $workspace }).Count -ne 1) { throw 'Completed task disappeared before its terminal-exit animation finished.' }

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ($logText -notmatch ('Terminal exit completed: ' + [regex]::Escape($workspace)) -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
        Start-Sleep -Milliseconds 200
        $logText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog
        $process.Refresh()
    }
    if ($logText -notmatch ('Terminal exit completed: ' + [regex]::Escape($workspace))) { throw 'Terminal-exit animation did not reach its bounded completion.' }

    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 200
        $afterRegistry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
        $remaining = @($afterRegistry.tasks | Where-Object { [string]$_.workspace -eq $workspace }).Count
    } while ($remaining -ne 0 -and [DateTime]::UtcNow -lt $deadline)
    if ($remaining -ne 0) { throw 'Completed task remained visible after bounded terminal exit.' }
    if ($logText -match 'Dispatcher error:|HUD Loaded error:') { throw 'Terminal-exit runtime log contains a WPF error.' }

    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'),[DateTime]::UtcNow.ToString('O'),$encoding)
    if (-not $process.WaitForExit(10000)) { throw 'Terminal-exit HUD did not stop through exit.signal.' }
    if ($process.ExitCode -ne 0) { throw ('Terminal-exit HUD exit code: ' + $process.ExitCode) }
    Write-Output ('Isolated terminal exit: OK ({0}, beacon, targeted and bounded)' -f $Mode)
} finally {
    if ($null -ne $process -and -not $process.HasExited) { try { $process.Kill() } catch { } }
    $env:LOCALAPPDATA = $savedLocalAppData
    $env:USERPROFILE = $savedUserProfile
    $env:HOME = $savedHome
    $env:PSModuleAnalysisCachePath = $savedModuleAnalysisCache
    $env:CODEX_MONITOR_HUD_DEBUG_PATH = $savedDebugPath
}
