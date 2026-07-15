param(
    [ValidateSet('list','split')][string]$Mode = 'list',
    # Three additional synthetic files exercise internal and terminal filtering.
    # Keep the fixture at or below the production 64-file discovery cap.
    [ValidateRange(1,61)][int]$TaskCount = 10,
    [ValidateRange(0,5)][int]$ChurnCycles = 0
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $root '.test-output\isolated-runtime'
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $root '.test-output'))
$resolvedTarget = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTarget.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to reset a runtime-test folder outside .test-output.'
}
if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
$runtimeLog = Join-Path $root '.test-output\runtime.log'
if (Test-Path -LiteralPath $runtimeLog) { Remove-Item -LiteralPath $runtimeLog -Force }

$localAppData = Join-Path $testRoot 'localapp'
$profileRoot = Join-Path $testRoot 'profile'
$sessionRoot = Join-Path (Join-Path (Join-Path (Join-Path $profileRoot '.codex') 'sessions') (Get-Date).ToString('yyyy')) ((Get-Date).ToString('MM'))
$sessionRoot = Join-Path $sessionRoot ((Get-Date).ToString('dd'))
$stateRoot = Join-Path $localAppData 'CodexMonitorHUD'
$sessionIndexPath = Join-Path (Join-Path $profileRoot '.codex') 'session_index.jsonl'
New-Item -ItemType Directory -Force -Path $sessionRoot, $stateRoot | Out-Null

$encoding = New-Object Text.UTF8Encoding($false)
function Write-SyntheticTask {
    param([int]$Index, [string]$Prefix, [switch]$Internal, [switch]$AlreadyCompleted)
    $now = [DateTimeOffset]::Now
    $sessionId = ('synthetic-{0}-{1}' -f $Prefix,$Index)
    $meta = [ordered]@{
        timestamp = $now.AddMinutes(-2).ToString('O')
        type = 'session_meta'
        payload = [ordered]@{ id=$sessionId; originator = 'Codex Desktop'; source = $(if($Internal){[ordered]@{subagent=[ordered]@{other='guardian'}}}else{'vscode'}) }
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
for ($index = 1; $index -le $TaskCount; $index++) { [void](Write-SyntheticTask $index 'synthetic') }
[void](Write-SyntheticTask 9001 'internal' -Internal)
[void](Write-SyntheticTask 9002 'internal' -Internal)
[void](Write-SyntheticTask 9003 'completed' -AlreadyCompleted)

$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
$config.language = 'en'
$config.activeWindowMinutes = 60
$config.multiTask.displayMode = $Mode
$config.multiTask.maxSplitBubbles = 6
$config.agentNotifications.enabled = $true
$config.agentNotifications.permission = 'expressive'
[IO.File]::WriteAllText((Join-Path $stateRoot 'settings.json'), ($config | ConvertTo-Json -Depth 8), $encoding)

$savedLocalAppData = $env:LOCALAPPDATA
$savedUserProfile = $env:USERPROFILE
$savedHome = $env:HOME
$savedModuleAnalysisCache = $env:PSModuleAnalysisCachePath
$process = $null
try {
    $env:LOCALAPPDATA = $localAppData
    $env:USERPROFILE = $profileRoot
    $env:HOME = $profileRoot
    $env:PSModuleAnalysisCachePath = Join-Path $testRoot 'ModuleAnalysisCache'
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'src\CodexMonitorHUD.ps1'),
        '-InstanceId', ('isolated-runtime-v140-' + $Mode), '-DebugLog'
    ) -PassThru -WindowStyle Hidden

    $heartbeat = Join-Path $stateRoot 'hud.heartbeat'
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $heartbeat) -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
        Start-Sleep -Milliseconds 200
        $process.Refresh()
    }
    if (-not (Test-Path -LiteralPath $heartbeat)) {
        $detail = if (Test-Path -LiteralPath $runtimeLog) { Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog } else { 'No debug log.' }
        throw ('Isolated HUD did not reach its heartbeat. ' + $detail)
    }

    $registryPath = Join-Path $stateRoot 'task-registry.json'
    $registryDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $registryPath) -and [DateTime]::UtcNow -lt $registryDeadline) { Start-Sleep -Milliseconds 200 }
    $registry = Get-Content -Raw -Encoding UTF8 -LiteralPath $registryPath | ConvertFrom-Json
    $expectedInitialTaskCount = $TaskCount + 1 # The synthetic completed user task is inside the default retention period.
    if (@($registry.tasks).Count -ne $expectedInitialTaskCount) { throw ('Visible task filter expected {0} user tasks but registry contains {1}.' -f $expectedInitialTaskCount,@($registry.tasks).Count) }
    $agentTarget = @($registry.tasks | Where-Object { [string]$_.status -in @('active','listening','idle','paused') } | Sort-Object task_number | Select-Object -First 1)[0]
    if ($null -eq $agentTarget) { throw 'No active synthetic user task was available for the Codex notice test.' }

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

    $notificationRoot = Join-Path $stateRoot 'notifications'
    New-Item -ItemType Directory -Force -Path $notificationRoot | Out-Null
    $agentNotice = [ordered]@{
        version=1;created_at=[DateTimeOffset]::Now.ToString('O');source='codex-mcp';message='Synthetic mid-turn decision needs review.';task_number=[int]$agentTarget.task_number
        animation=[ordered]@{layers=@('glow','pulse','breathe','flow');color='#FF7C3AED';intensity=0.8;tempo_ms=420;cycles=3;glow_radius=34;scale=1.03;direction='right-to-left'}
    } | ConvertTo-Json -Compress -Depth 6
    [IO.File]::WriteAllText((Join-Path $notificationRoot 'notice-synthetic.json'),$agentNotice,$encoding)
    Start-Sleep -Seconds 2

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
    }

    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'), [DateTime]::UtcNow.ToString('O'), $encoding)
    if (-not $process.WaitForExit(10000)) { throw 'Isolated HUD did not exit through its own signal.' }
    if ($process.ExitCode -ne 0) { throw ('Isolated HUD exit code: ' + $process.ExitCode) }

    $logText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog
    if ($logText -notmatch 'HUD Loaded event completed\.') { throw 'HUD Loaded completion marker is missing.' }
    if ($logText -match 'Dispatcher error:|HUD Loaded error:') { throw 'Runtime log contains a HUD error.' }
    if ($logText -notmatch 'Session identity loaded: workspace-01; officialTitle=True') { throw 'Codex session-index thread title was not loaded for a user task.' }
    if ($logText -notmatch ('Agent notice accepted for task #' + [regex]::Escape([string]$agentTarget.task_number) + '; expressive=True')) { throw 'Expressive Codex notice was not accepted.' }
    if ($Mode -eq 'list') {
        if ($logText -notmatch ('Attention surface: list ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent') -or $logText -match ('Attention surface: bubble ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent')) { throw 'Codex notice escaped its single matching list item.' }
    } else {
        if ($logText -notmatch ('Attention surface: bubble ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent') -or $logText -match ('Attention surface: list ' + [regex]::Escape([string]$agentTarget.workspace) + ' .*reason=agent')) { throw 'Codex notice escaped its single matching bubble.' }
    }
    if ($terminalFiles.Count -ge 3) {
        if ($logText -notmatch ('Silent completion retained: ' + [regex]::Escape($workspaces[0]))) { throw 'Silent completion was not retained.' }
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
    Write-Output ('Isolated multi-task runtime: OK ({0} synthetic tasks, {1} mode, {2} churn cycle(s))' -f $TaskCount,$Mode,$ChurnCycles)
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        try { $process.Kill() } catch { }
    }
    $env:LOCALAPPDATA = $savedLocalAppData
    $env:USERPROFILE = $savedUserProfile
    $env:HOME = $savedHome
    $env:PSModuleAnalysisCachePath = $savedModuleAnalysisCache
}
