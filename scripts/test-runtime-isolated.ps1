param(
    [ValidateSet('list','split')][string]$Mode = 'list',
    [ValidateSet('legacy','compiled')][string]$HostMode = 'legacy',
    # Five additional synthetic files exercise internal, delayed-metadata and terminal filtering.
    # Keep the fixture at or below the production 64-file discovery cap.
    [ValidateRange(1,59)][int]$TaskCount = 10,
    [ValidateRange(0,5)][int]$ChurnCycles = 0,
    [string]$TestOutputRoot,
    [string]$MetricsPath
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outputRoot = if ([string]::IsNullOrWhiteSpace($TestOutputRoot)) { Join-Path $root '.test-output' } else { $TestOutputRoot }
$testRoot = Join-Path $outputRoot ('isolated-runtime-' + $HostMode)
$expectedRoot = [IO.Path]::GetFullPath($outputRoot)
$resolvedTarget = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTarget.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to reset a runtime-test folder outside .test-output.'
}
if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }

$localAppData = Join-Path $testRoot 'localapp'
$profileRoot = Join-Path $testRoot 'profile'
$sessionRoot = Join-Path (Join-Path (Join-Path (Join-Path $profileRoot '.codex') 'sessions') (Get-Date).ToString('yyyy')) ((Get-Date).ToString('MM'))
$sessionRoot = Join-Path $sessionRoot ((Get-Date).ToString('dd'))
$stateRoot = Join-Path $localAppData 'CodexMonitorHUD'
$runtimeLog = if ($HostMode -eq 'compiled') { Join-Path $stateRoot 'runtime-v220.log' } else { Join-Path $outputRoot 'runtime.log' }
if (Test-Path -LiteralPath $runtimeLog) { Remove-Item -LiteralPath $runtimeLog -Force }
$sessionIndexPath = Join-Path (Join-Path $profileRoot '.codex') 'session_index.jsonl'
New-Item -ItemType Directory -Force -Path $sessionRoot, $stateRoot | Out-Null

$encoding = New-Object Text.UTF8Encoding($false)
function Write-SyntheticTask {
    param([int]$Index, [string]$Prefix, [switch]$Internal, [switch]$AlreadyCompleted, [switch]$PaddedMetadata, [switch]$OmitMetadata, [switch]$LongTail)
    $now = [DateTimeOffset]::Now
    $sessionId = ('synthetic-{0}-{1}' -f $Prefix,$Index)
    $meta = [ordered]@{
        timestamp = $now.AddMinutes(-2).ToString('O')
        type = 'session_meta'
        payload = [ordered]@{ id=$sessionId; cwd=('C:\Synthetic\workspace-{0:d2}' -f $index); originator = 'Codex Desktop'; source = $(if($Internal){[ordered]@{subagent=[ordered]@{other='guardian'}}}else{'vscode'}) }
    } | ConvertTo-Json -Compress -Depth 6
    $context = [ordered]@{
        timestamp = $now.AddSeconds(-$index).ToString('O')
        type = 'turn_context'
        payload = [ordered]@{ cwd = ('C:\Synthetic\workspace-{0:d2}' -f $index); model = 'gpt-test' }
    } | ConvertTo-Json -Compress -Depth 6
    $started = [ordered]@{
        timestamp = $now.AddMilliseconds(-$index * 110).ToString('O')
        type = 'event_msg'
        payload = [ordered]@{ type = 'task_started'; turn_id = ('turn-{0}' -f $index) }
    } | ConvertTo-Json -Compress -Depth 4
    $usage = [ordered]@{
        timestamp = $now.AddMilliseconds(-$index * 100).ToString('O')
        type = 'event_msg'
        payload = [ordered]@{
            type = 'token_count'
            info = [ordered]@{
                last_token_usage = [ordered]@{
                    input_tokens = 1000 + $index
                    cached_input_tokens = 700
                    output_tokens = 100 + $index
                    reasoning_output_tokens = 20
                    total_tokens = 1120 + ($index * 2)
                }
                total_token_usage = [ordered]@{ total_tokens = 10000 + ($index * 100) }
                model_context_window = 200000
            }
            rate_limits = [ordered]@{
                secondary = [ordered]@{ used_percent = 25; window_minutes = 10080; resets_at = 0 }
            }
        }
    } | ConvertTo-Json -Compress -Depth 8
    $path = Join-Path $sessionRoot ('{0}-{1:d4}.jsonl' -f $Prefix,$index)
    $records = @($meta, $context, $started, $usage)
    if ($Internal -or $PaddedMetadata) {
        # Match Codex files where operational records precede session_meta.
        # The title lookup and visible-task filter must use the same bound.
        $padding = foreach ($paddingIndex in 1..16) {
            [ordered]@{ timestamp=$now.AddMilliseconds(-500-$paddingIndex).ToString('O'); type='event_msg'; payload=[ordered]@{ type='internal_progress' } } | ConvertTo-Json -Compress -Depth 4
        }
        $records = @($padding) + $records
    }
    if ($LongTail) {
        # Push turn_context beyond Get-LatestHudSnapshot's 2,000-line tail.
        # Initialize-SessionFile must recover the project leaf from session_meta.cwd.
        $tailPadding = foreach ($paddingIndex in 1..2100) {
            [ordered]@{ timestamp=$now.AddMilliseconds(-400-$paddingIndex).ToString('O'); type='event_msg'; payload=[ordered]@{ type='internal_progress' } } | ConvertTo-Json -Compress -Depth 4
        }
        $metaIndex = if ($PaddedMetadata) { 16 } else { 0 }
        $prefixRecords = @($records | Select-Object -First ($metaIndex + 2))
        $suffixRecords = @($records | Select-Object -Skip ($metaIndex + 2))
        $records = @($prefixRecords) + @($tailPadding) + @($suffixRecords)
    }
    if ($OmitMetadata) { $records = @($context, $started, $usage) }
    if ($AlreadyCompleted) {
        $records += ([ordered]@{
            timestamp = $now.AddMinutes(-2).AddSeconds(10).ToString('O')
            type = 'event_msg'
            payload = [ordered]@{ type='task_complete'; turn_id=('turn-{0}' -f $index); last_agent_message='Already completed.' }
        } | ConvertTo-Json -Compress -Depth 4)
    }
    [IO.File]::WriteAllLines($path, [string[]]$records, $encoding)
    $indexEntry = [ordered]@{ id=$sessionId; thread_name=('Synthetic conversation {0}' -f $Index); updated_at=$now.ToString('O') } | ConvertTo-Json -Compress
    [IO.File]::AppendAllText($sessionIndexPath,($indexEntry+[Environment]::NewLine),$encoding)
    return $path
}
function Start-IsolatedHost {
    param([string]$FilePath, [string[]]$Arguments)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = (($Arguments | ForEach-Object { '"' + ([string]$_).Replace('"','\"') + '"' }) -join ' ')
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $hostProcess = New-Object Diagnostics.Process
    $hostProcess.StartInfo = $info
    [void]$hostProcess.Start()
    return $hostProcess
}
for ($index = 1; $index -le $TaskCount; $index++) { [void](Write-SyntheticTask $index 'synthetic' -PaddedMetadata:($index -eq 1) -LongTail:($index -eq 1)) }
[void](Write-SyntheticTask 9001 'internal' -Internal)
[void](Write-SyntheticTask 9002 'internal' -Internal)
[void](Write-SyntheticTask 9003 'completed' -AlreadyCompleted)
$lateInternalPath = Write-SyntheticTask 9004 'late-internal' -Internal -OmitMetadata
$lateUserPath = Write-SyntheticTask 9005 'late-user' -OmitMetadata

$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
$config.language = 'en'
$config.activeWindowMinutes = 60
$config.multiTask.displayMode = $Mode
$config.multiTask.maxSplitBubbles = 6
$config.agentNotifications.enabled = $true
$config.agentNotifications.permission = 'expressive'
# Keep the pre-existing completed fixture stable while the test measures
# token-only rendering; completion retention is covered separately below.
$config.statusTiming.terminalHoldSeconds = 600
# The delayed-identity regressions add a few seconds before the token burst.
# Keep active-state transitions outside that animation-specific assertion.
$config.statusTiming.activeSeconds = 60
[IO.File]::WriteAllText((Join-Path $stateRoot 'settings.json'), ($config | ConvertTo-Json -Depth 8), $encoding)

$savedLocalAppData = $env:LOCALAPPDATA
$savedUserProfile = $env:USERPROFILE
$savedHome = $env:HOME
$savedModuleAnalysisCache = $env:PSModuleAnalysisCachePath
$savedDebugPath = $env:CODEX_MONITOR_HUD_DEBUG_PATH
$savedCompiledTestHome = $env:CODEX_MONITOR_HUD_TEST_HOME
$savedCompiledTestLocalAppData = $env:CODEX_MONITOR_HUD_TEST_LOCALAPPDATA
$process = $null
$runtimeSamples = New-Object System.Collections.Generic.List[object]
$runtimeStartedAt = [DateTimeOffset]::UtcNow
function Add-RuntimeSample {
    param([string]$Label)
    if ($null -eq $process -or $process.HasExited) { return }
    $process.Refresh()
    $runtimeSamples.Add([pscustomobject][ordered]@{
        label = $Label
        elapsed_ms = [Math]::Round(([DateTimeOffset]::UtcNow - $runtimeStartedAt).TotalMilliseconds, 1)
        working_set_bytes = [long]$process.WorkingSet64
        private_memory_bytes = [long]$process.PrivateMemorySize64
        cpu_ms = [Math]::Round($process.TotalProcessorTime.TotalMilliseconds, 1)
        handles = [int]$process.HandleCount
        threads = [int]$process.Threads.Count
    })
}
try {
    $env:LOCALAPPDATA = $localAppData
    $env:USERPROFILE = $profileRoot
    $env:HOME = $profileRoot
    $env:PSModuleAnalysisCachePath = Join-Path $testRoot 'ModuleAnalysisCache'
    $env:CODEX_MONITOR_HUD_TEST_HOME = $profileRoot
    $env:CODEX_MONITOR_HUD_TEST_LOCALAPPDATA = $localAppData
    if ($HostMode -eq 'legacy') { $env:CODEX_MONITOR_HUD_DEBUG_PATH = $runtimeLog }
    if ($HostMode -eq 'compiled') {
        $compiledDotnet = Join-Path $root 'runtime\win-x64\dotnet\dotnet.exe'
        $compiledApp = Join-Path $root 'runtime\win-x64\app\CodexMonitorHud.dll'
        if (-not (Test-Path -LiteralPath $compiledDotnet) -or -not (Test-Path -LiteralPath $compiledApp)) {
            throw 'Compiled runtime is not staged. Run scripts\build-dotnet.ps1 first.'
        }
        $process = Start-IsolatedHost $compiledDotnet @(
            $compiledApp, '--plugin-root', $root, '--instance-id', ('isolated-runtime-v220-' + $Mode), '--debug-log'
        )
    } else {
        $process = Start-IsolatedHost 'powershell.exe' @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'src\CodexMonitorHUD.ps1'),
            '-InstanceId', ('isolated-runtime-v210-' + $Mode), '-DebugLog'
        )
    }

    $heartbeat = Join-Path $stateRoot 'hud.heartbeat'
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $heartbeat) -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
        Start-Sleep -Milliseconds 200
        $process.Refresh()
    }
    if (-not (Test-Path -LiteralPath $heartbeat)) {
        $detail = if (Test-Path -LiteralPath $runtimeLog) { Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog } else { 'No debug log.' }
        $process.Refresh()
        $exitDetail = if ($process.HasExited) { ' Process exit=' + $process.ExitCode + '.' } else { ' Process is still running.' }
        $stderrDetail = if ($process.HasExited) { $process.StandardError.ReadToEnd() } else { '' }
        throw ('Isolated HUD did not reach its heartbeat.' + $exitDetail + ' ' + $detail + ' ' + $stderrDetail)
    }
    Add-RuntimeSample 'heartbeat'

    $registryPath = Join-Path $stateRoot 'task-registry.json'
    $registryDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $registryPath) -and [DateTime]::UtcNow -lt $registryDeadline) { Start-Sleep -Milliseconds 200 }
    $registry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
    $expectedInitialTaskCount = $TaskCount + 1 # The synthetic completed user task is inside the default retention period.
    if (@($registry.tasks).Count -ne $expectedInitialTaskCount) { throw ('Visible task filter expected {0} user tasks but registry contains {1}.' -f $expectedInitialTaskCount,@($registry.tasks).Count) }
    $agentTarget = @($registry.tasks | Where-Object { [string]$_.status -in @('active','listening','idle','paused') } | Sort-Object task_number | Select-Object -First 1)[0]
    if ($null -eq $agentTarget) { throw 'No active synthetic user task was available for the Codex notice test.' }

    # A session file can arrive before its session_meta record. It must remain
    # hidden while unresolved and stay hidden when that record identifies it as
    # an auto-review/subagent session.
    $lateMeta = [ordered]@{
        timestamp = [DateTimeOffset]::Now.ToString('O')
        type = 'session_meta'
        payload = [ordered]@{ id='synthetic-late-internal-9004'; originator='Codex Desktop'; source=[ordered]@{subagent=[ordered]@{other='guardian'}} }
    } | ConvertTo-Json -Compress -Depth 6
    [IO.File]::AppendAllText($lateInternalPath,([Environment]::NewLine + $lateMeta + [Environment]::NewLine),$encoding)
    $identityDeadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 250
        $afterIdentityRegistry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
        $lateRows = @($afterIdentityRegistry.tasks | Where-Object { [string]$_.workspace -eq 'workspace-9004' }).Count
    } while ($lateRows -ne 0 -and [DateTime]::UtcNow -lt $identityDeadline)
    if ($lateRows -ne 0) { throw 'Late-metadata internal session briefly remained in the visible task registry.' }

    $lateUserMeta = [ordered]@{
        timestamp = [DateTimeOffset]::Now.ToString('O')
        type = 'session_meta'
        payload = [ordered]@{ id='synthetic-late-user-9005'; originator='Codex Desktop'; source='vscode' }
    } | ConvertTo-Json -Compress -Depth 6
    [IO.File]::AppendAllText($lateUserPath,([Environment]::NewLine + $lateUserMeta + [Environment]::NewLine),$encoding)
    $identityDeadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Start-Sleep -Milliseconds 250
        $afterIdentityRegistry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
        $lateUserRows = @($afterIdentityRegistry.tasks | Where-Object { [string]$_.workspace -eq 'workspace-9005' }).Count
    } while ($lateUserRows -ne 1 -and [DateTime]::UtcNow -lt $identityDeadline)
    if ($lateUserRows -ne 1) { throw 'Late-metadata user session did not appear after its identity became available.' }

    # Let the identity-resolution render settle before measuring token-only
    # update animations below.
    Start-Sleep -Seconds 2
    Start-Sleep -Milliseconds 500
    $beforeBurstLog = if (Test-Path -LiteralPath $runtimeLog) { Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog } else { '' }
    $beforeBurstAnimations = ([regex]::Matches($beforeBurstLog,'Update animation:')).Count
    $burstPath = Join-Path $sessionRoot 'synthetic-0001.jsonl'
    for ($burst = 1; $burst -le 16; $burst++) {
        $burstUsage = [ordered]@{
            timestamp=[DateTimeOffset]::Now.AddMilliseconds($burst).ToString('O');type='event_msg';payload=[ordered]@{
                type='token_count';info=[ordered]@{
                    last_token_usage=[ordered]@{input_tokens=1100+$burst;cached_input_tokens=700;output_tokens=120+$burst;reasoning_output_tokens=20;total_tokens=1240+($burst*2)}
                    total_token_usage=[ordered]@{total_tokens=12000+($burst*100)};model_context_window=200000
                }
            }
        } | ConvertTo-Json -Compress -Depth 8
        [IO.File]::AppendAllText($burstPath,([Environment]::NewLine+$burstUsage),$encoding)
    }
    Start-Sleep -Seconds 3
    $afterBurstLog = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog
    $afterBurstAnimations = ([regex]::Matches($afterBurstLog,'Update animation:')).Count
    if ($afterBurstAnimations -ne $beforeBurstAnimations) { throw 'High-frequency token refresh replayed the whole-window update animation.' }
    Add-RuntimeSample 'token-burst'

    $notificationRoot = Join-Path $stateRoot 'notifications'
    New-Item -ItemType Directory -Force -Path $notificationRoot | Out-Null
    $agentNotice = [ordered]@{
        version=1;created_at=[DateTimeOffset]::Now.ToString('O');source='codex-mcp';message='Synthetic mid-turn decision needs review.';task_number=[int]$agentTarget.task_number
        animation=[ordered]@{layers=@('glow','pulse','breathe','flow');color='#FF7C3AED';intensity=0.8;tempo_ms=420;cycles=3;glow_radius=34;scale=1.03;direction='right-to-left'}
    } | ConvertTo-Json -Compress -Depth 6
    [IO.File]::WriteAllText((Join-Path $notificationRoot 'notice-synthetic.json'),$agentNotice,$encoding)
    Start-Sleep -Seconds 2
    if ($HostMode -eq 'compiled' -and (Test-Path -LiteralPath (Join-Path $notificationRoot 'notice-synthetic.json'))) { throw 'Compiled HUD did not consume its targeted notice.' }

    $deletedIndex = $TaskCount
    $deletedWorkspace = ('workspace-{0:d2}' -f $deletedIndex)
    $deletedPath = Join-Path $sessionRoot ('synthetic-{0:d4}.jsonl' -f $deletedIndex)
    Remove-Item -LiteralPath $deletedPath -Force
    $deleteDeadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 250
        $afterDeleteRegistry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
        $deletedRows = @($afterDeleteRegistry.tasks | Where-Object { [string]$_.workspace -eq $deletedWorkspace }).Count
    } while ($deletedRows -ne 0 -and [DateTime]::UtcNow -lt $deleteDeadline)
    if ($deletedRows -ne 0) { throw 'A deleted running conversation remained in the visible task registry.' }

    $terminalFiles = @(Get-ChildItem -LiteralPath $sessionRoot -File -Filter 'synthetic-*.jsonl' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First ([Math]::Min(4,$TaskCount)))
    if ($terminalFiles.Count -ge 3) {
        $indices = @($terminalFiles | ForEach-Object { [int]([regex]::Match($_.BaseName,'(\d+)$').Groups[1].Value) })
        $workspaces = @($indices | ForEach-Object { 'workspace-{0:d2}' -f $_ })
        $silent = [ordered]@{ timestamp=[DateTimeOffset]::Now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_complete'; turn_id=('turn-{0}' -f $indices[0]); last_agent_message='' } } | ConvertTo-Json -Compress -Depth 4
        [IO.File]::AppendAllText($terminalFiles[0].FullName, ([Environment]::NewLine + $silent), $encoding)

        $cancelled = [ordered]@{ timestamp=[DateTimeOffset]::Now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_complete'; turn_id=('turn-{0}' -f $indices[1]); last_agent_message='Visible but immediately resumed.' } } | ConvertTo-Json -Compress -Depth 4
        $resumed = [ordered]@{ timestamp=[DateTimeOffset]::Now.AddMilliseconds(100).ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_started'; turn_id=('turn-{0}-resumed' -f $indices[1]) } } | ConvertTo-Json -Compress -Depth 4
        [IO.File]::AppendAllText($terminalFiles[1].FullName, ([Environment]::NewLine + $cancelled + [Environment]::NewLine + $resumed), $encoding)

        $visible = [ordered]@{ timestamp=[DateTimeOffset]::Now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='task_complete'; turn_id=('turn-{0}' -f $indices[2]); last_agent_message='Visible completion.' } } | ConvertTo-Json -Compress -Depth 4
        [IO.File]::AppendAllText($terminalFiles[2].FullName, ([Environment]::NewLine + $visible), $encoding)
        if ($terminalFiles.Count -ge 4) {
            $aborted = [ordered]@{ timestamp=[DateTimeOffset]::Now.ToString('O'); type='event_msg'; payload=[ordered]@{ type='turn_aborted'; turn_id=('turn-{0}' -f $indices[3]) } } | ConvertTo-Json -Compress -Depth 4
            [IO.File]::AppendAllText($terminalFiles[3].FullName, ([Environment]::NewLine + $aborted), $encoding)
        }
        Start-Sleep -Seconds 10
        # Folder polling can consume up to 1.5 seconds before the runtime sees
        # the record, so wait for the eight-second continuation guard itself
        # instead of racing it with a fixed ten-second process shutdown.
        $completionDeadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            $lifecycleLog = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog
            if ($lifecycleLog -match ('Attention triggered: ' + [regex]::Escape($workspaces[2]) + ' completed')) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $completionDeadline)
        $postLifecycleRegistry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
        if (@($postLifecycleRegistry.tasks | Where-Object { [string]$_.workspace -eq [string]$workspaces[0] }).Count -ne 1) { throw 'Silent completion did not remain visible during the configured retention period.' }
        if (@($postLifecycleRegistry.tasks | Where-Object { [string]$_.workspace -eq [string]$workspaces[1] }).Count -ne 1) { throw 'Immediately resumed task disappeared from the visible task set.' }
    }

    for ($cycle = 1; $cycle -le $ChurnCycles; $cycle++) {
        $currentFiles = @(Get-ChildItem -LiteralPath $sessionRoot -File -Filter '*.jsonl' | Sort-Object LastWriteTimeUtc -Descending)
        foreach ($oldFile in $currentFiles | Select-Object -Last ([Math]::Max(1,[Math]::Floor($currentFiles.Count / 2)))) {
            [IO.File]::SetLastWriteTimeUtc($oldFile.FullName, [DateTime]::UtcNow.AddHours(-2))
        }
        for ($index = 1; $index -le $TaskCount; $index++) { [void](Write-SyntheticTask (($cycle * 1000) + $index) ('churn' + $cycle)) }
        Start-Sleep -Seconds 3
        $process.Refresh()
        if ($process.HasExited) { throw ('HUD exited during churn cycle ' + $cycle) }
        Add-RuntimeSample ('churn-' + $cycle)
    }

    Add-RuntimeSample 'pre-exit'
    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'), $encoding)
    if (-not $process.WaitForExit(10000)) { throw 'Isolated HUD did not exit through its own signal.' }
    if ($process.ExitCode -ne 0) { throw ('Isolated HUD exit code: ' + $process.ExitCode) }

    $logText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog
    if ($HostMode -eq 'compiled') {
        if ($logText -notmatch 'Compiled HUD v3\.0\.0 starting\.') { throw 'Compiled HUD startup marker is missing.' }
        if ($logText -match 'Unhandled dispatcher exception:|Unhandled domain exception:|Fatal startup error:') { throw 'Compiled runtime log contains an unhandled HUD error.' }
    } else {
        if ($logText -notmatch 'HUD Loaded event completed\.') { throw 'HUD Loaded completion marker is missing.' }
        if ($logText -match 'Dispatcher error:|HUD Loaded error:') { throw 'Runtime log contains a HUD error.' }
        if ($logText -notmatch 'Session identity loaded: workspace-01; metadata=True; officialTitle=True') { throw 'Codex session-index thread title was not loaded for a user task with late header metadata.' }
        if ($logText -notmatch 'Session identity resolved: workspace-9004; internal=True; officialTitle=True') { throw 'Late-metadata internal session was not reclassified before display.' }
        if ($logText -notmatch 'Session identity resolved: workspace-9005; internal=False; officialTitle=True') { throw 'Late-metadata user session did not refresh its official title.' }
    }
    if ($logText -notmatch ('Agent notice accepted for task #' + [regex]::Escape([string]$agentTarget.task_number) + '; expressive=True')) { throw 'Expressive Codex notice was not accepted.' }
    if ($Mode -eq 'list') {
        if ($logText -notmatch ('Attention surface: list ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent') -or $logText -match ('Attention surface: bubble ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent')) { throw 'Codex notice escaped its single matching list item.' }
    } else {
        if ($logText -notmatch ('Attention surface: bubble ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent') -or $logText -match ('Attention surface: list ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent')) { throw 'Codex notice escaped its single matching bubble.' }
    }
    if ($terminalFiles.Count -ge 3 -and $HostMode -eq 'legacy') {
        if ($logText -notmatch ('Silent completion ignored: ' + [regex]::Escape($workspaces[0]))) { throw 'Silent completion was not ignored.' }
        if ($logText -match ('Attention triggered: ' + [regex]::Escape($workspaces[0]) + ' completed')) { throw 'Silent completion unexpectedly triggered attention.' }
        if ($logText -notmatch ('Pending completion canceled: ' + [regex]::Escape($workspaces[1]))) { throw 'Immediate continuation did not cancel its pending reminder.' }
        if ($logText -match ('Attention triggered: ' + [regex]::Escape($workspaces[1]) + ' completed')) { throw 'Cancelled completion still triggered attention.' }
        if ($logText -notmatch ('Attention triggered: ' + [regex]::Escape($workspaces[2]) + ' completed')) { throw 'Visible stable turn completion did not trigger attention.' }
        if ($Mode -eq 'list') {
            if ($logText -notmatch 'Attention surface: list ' -or $logText -match 'Attention surface: summary |Attention surface: bubble ') { throw 'List mode reminder escaped its matching list surface.' }
        } else {
            if ($logText -notmatch 'Attention surface: bubble ' -or $logText -match 'Attention surface: summary |Attention surface: list ') { throw 'Split mode reminder escaped its matching bubble surface.' }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($MetricsPath)) {
        $metricsDirectory = Split-Path -Parent $MetricsPath
        if (-not [string]::IsNullOrWhiteSpace($metricsDirectory)) { New-Item -ItemType Directory -Force -Path $metricsDirectory | Out-Null }
        $peakWorkingSet = [long](($runtimeSamples | Measure-Object -Property working_set_bytes -Maximum).Maximum)
        $peakPrivateMemory = [long](($runtimeSamples | Measure-Object -Property private_memory_bytes -Maximum).Maximum)
        $finalCpu = [double](($runtimeSamples | Measure-Object -Property cpu_ms -Maximum).Maximum)
        $metrics = [ordered]@{
            schema_version = 1
            host_mode = $HostMode
            display_mode = $Mode
            task_count = $TaskCount
            churn_cycles = $ChurnCycles
            duration_ms = [Math]::Round(([DateTimeOffset]::UtcNow - $runtimeStartedAt).TotalMilliseconds, 1)
            peak_working_set_bytes = $peakWorkingSet
            peak_private_memory_bytes = $peakPrivateMemory
            final_cpu_ms = $finalCpu
            samples = $runtimeSamples.ToArray()
        }
        [IO.File]::WriteAllText($MetricsPath, ($metrics | ConvertTo-Json -Depth 6), $encoding)
    }
    Write-Output ('Isolated multi-task runtime: OK ({0} synthetic tasks, {1} mode, {2} host, {3} churn cycle(s))' -f $TaskCount,$Mode,$HostMode,$ChurnCycles)
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        try { $process.Kill() } catch { }
    }
    $env:LOCALAPPDATA = $savedLocalAppData
    $env:USERPROFILE = $savedUserProfile
    $env:HOME = $savedHome
    $env:PSModuleAnalysisCachePath = $savedModuleAnalysisCache
    $env:CODEX_MONITOR_HUD_DEBUG_PATH = $savedDebugPath
    $env:CODEX_MONITOR_HUD_TEST_HOME = $savedCompiledTestHome
    $env:CODEX_MONITOR_HUD_TEST_LOCALAPPDATA = $savedCompiledTestLocalAppData
}
