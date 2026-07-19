param(
    [string]$TestOutputRoot
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outputRoot = if ([string]::IsNullOrWhiteSpace($TestOutputRoot)) { Join-Path $root '.test-output' } else { $TestOutputRoot }
$testRoot = Join-Path $outputRoot 'behavior-isolated'
$expectedRoot = [IO.Path]::GetFullPath($outputRoot)
$resolvedTarget = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTarget.StartsWith($expectedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to reset a behavior-test folder outside .test-output.' }
if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }

$localAppData = Join-Path $testRoot 'localapp'
$profileRoot = Join-Path $testRoot 'profile'
$sessionRoot = Join-Path $profileRoot ('.codex\sessions\{0}\{1}\{2}' -f (Get-Date).ToString('yyyy'),(Get-Date).ToString('MM'),(Get-Date).ToString('dd'))
$stateRoot = Join-Path $localAppData 'CodexMonitorHUD'
$sessionIndexPath = Join-Path $profileRoot '.codex\session_index.jsonl'
$runtimeLog = Join-Path $outputRoot 'runtime.log'
New-Item -ItemType Directory -Force -Path $sessionRoot,$stateRoot | Out-Null
if (Test-Path -LiteralPath $runtimeLog) { Remove-Item -LiteralPath $runtimeLog -Force }
$encoding = New-Object Text.UTF8Encoding($false)

$now = [DateTimeOffset]::Now
$sessionId = 'synthetic-behavior-1'
$sessionPath = Join-Path $sessionRoot 'synthetic-behavior-1.jsonl'
$records = @(
    ([ordered]@{timestamp=$now.AddMinutes(-1).ToString('O');type='session_meta';payload=[ordered]@{id=$sessionId;cwd='C:\Synthetic\behavior-workspace';originator='Codex Desktop';source='vscode'}} | ConvertTo-Json -Compress -Depth 5),
    ([ordered]@{timestamp=$now.AddMinutes(-1).ToString('O');type='turn_context';payload=[ordered]@{cwd='C:\Synthetic\behavior-workspace';model='gpt-test'}} | ConvertTo-Json -Compress -Depth 4),
    ([ordered]@{timestamp=$now.AddMinutes(-1).ToString('O');type='event_msg';payload=[ordered]@{type='task_started';turn_id='turn-behavior'}} | ConvertTo-Json -Compress -Depth 4),
    ([ordered]@{timestamp=$now.AddMinutes(-1).ToString('O');type='event_msg';payload=[ordered]@{type='token_count';info=[ordered]@{last_token_usage=[ordered]@{input_tokens=1000;cached_input_tokens=700;output_tokens=100;reasoning_output_tokens=20;total_tokens=1100};total_token_usage=[ordered]@{total_tokens=1100};model_context_window=200000}}} | ConvertTo-Json -Compress -Depth 8)
)
[IO.File]::WriteAllLines($sessionPath,[string[]]$records,$encoding)
[IO.File]::WriteAllText($sessionIndexPath,(([ordered]@{id=$sessionId;thread_name='Synthetic behavior task';updated_at=$now.ToString('O')} | ConvertTo-Json -Compress)+[Environment]::NewLine),$encoding)

$config = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'config.default.json') | ConvertFrom-Json
$config.language = 'en'
$config.activeWindowMinutes = 60
$config.multiTask.displayMode = 'split'
$config.multiTask.maxSplitBubbles = 1
$config.statusTiming.activeSeconds = 1
$config.statusTiming.idleSeconds = 1
$config.behavior.idleIndicator.enabled = $true
$config.behavior.idleIndicator.afterMinutes = 0.03
$config.behavior.idleIndicator.layout = 'horizontal'
$config.behavior.idleIndicator.taskStyle = 'bar'
$config.behavior.idleIndicator.includeTaskBubbles = $true
$config.fields.context = $true
$config.behavior.contextAlerts.enabled = $true
[IO.File]::WriteAllText((Join-Path $stateRoot 'settings.json'),($config | ConvertTo-Json -Depth 10),$encoding)

$savedLocalAppData=$env:LOCALAPPDATA;$savedUserProfile=$env:USERPROFILE;$savedHome=$env:HOME;$savedModuleAnalysisCache=$env:PSModuleAnalysisCachePath;$savedDebugPath=$env:CODEX_MONITOR_HUD_DEBUG_PATH
$process = $null
try {
    $env:LOCALAPPDATA=$localAppData;$env:USERPROFILE=$profileRoot;$env:HOME=$profileRoot;$env:PSModuleAnalysisCachePath=Join-Path $testRoot 'ModuleAnalysisCache';$env:CODEX_MONITOR_HUD_DEBUG_PATH=$runtimeLog
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'src\CodexMonitorHUD.ps1'),'-InstanceId','behavior-isolated','-DebugLog') -PassThru -WindowStyle Hidden
    $heartbeat = Join-Path $stateRoot 'hud.heartbeat'
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $heartbeat) -and [DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) { Start-Sleep -Milliseconds 200;$process.Refresh() }
    if (-not (Test-Path -LiteralPath $heartbeat)) { throw 'Behavior HUD did not reach heartbeat.' }

    $collapseDeadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 250
        $logText = if(Test-Path -LiteralPath $runtimeLog){Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog}else{''}
    } while (($logText -notmatch 'Main quiet indicator: collapsed' -or $logText -notmatch 'Task quiet indicator: #[0-9]+ collapsed') -and [DateTime]::UtcNow -lt $collapseDeadline)
    if ($logText -notmatch 'Main quiet indicator: collapsed' -or $logText -notmatch 'Task quiet indicator: #[0-9]+ collapsed') { throw 'Main HUD or independent bubble did not retract to its status light.' }
    if ($logText -notmatch 'Quiet task indicators: layout=horizontal style=bar tasks=1 statuses=1:idle') { throw 'Numbered horizontal quiet-task bars did not render.' }

    $completed = [ordered]@{timestamp=[DateTimeOffset]::Now.ToString('O');type='event_msg';payload=[ordered]@{type='task_complete';turn_id='turn-behavior';last_agent_message='Synthetic completion.'}} | ConvertTo-Json -Compress -Depth 4
    [IO.File]::AppendAllText($sessionPath,([Environment]::NewLine+$completed),$encoding)
    $terminalDeadline = [DateTime]::UtcNow.AddSeconds(14)
    do {
        Start-Sleep -Milliseconds 300
        $logText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog
    } while ($logText -notmatch 'Quiet task indicators: layout=horizontal style=bar tasks=1 statuses=1:completed' -and [DateTime]::UtcNow -lt $terminalDeadline)
    if ($logText -notmatch 'Quiet task indicators: layout=horizontal style=bar tasks=1 statuses=1:completed') { throw 'Completed task did not remain visible in the quiet-task row.' }
    $lastCollapsedIndex = $logText.LastIndexOf('Main quiet indicator: collapsed')
    $lastExpandedIndex = $logText.LastIndexOf('Main quiet indicator: expanded')
    if ($lastExpandedIndex -gt $lastCollapsedIndex) { throw 'Completion unexpectedly expanded the numbered quiet-task row.' }
    $lastBubbleCollapsedIndex = $logText.LastIndexOf('Task quiet indicator: #1 collapsed')
    $lastBubbleExpandedIndex = $logText.LastIndexOf('Task quiet indicator: #1 expanded')
    if ($lastBubbleExpandedIndex -gt $lastBubbleCollapsedIndex) { throw 'Completion unexpectedly expanded the quiet independent task bubble.' }

    $resumed = [ordered]@{timestamp=[DateTimeOffset]::Now.ToString('O');type='event_msg';payload=[ordered]@{type='task_started';turn_id='turn-behavior-2'}} | ConvertTo-Json -Compress -Depth 4
    [IO.File]::AppendAllText($sessionPath,([Environment]::NewLine+$resumed),$encoding)

    foreach ($contextInput in @(152000,182000,196000)) {
        $usage = [ordered]@{timestamp=[DateTimeOffset]::Now.ToString('O');type='event_msg';payload=[ordered]@{type='token_count';info=[ordered]@{last_token_usage=[ordered]@{input_tokens=$contextInput;cached_input_tokens=70000;output_tokens=120;reasoning_output_tokens=20;total_tokens=($contextInput+120)};total_token_usage=[ordered]@{total_tokens=($contextInput+120)};model_context_window=200000}}} | ConvertTo-Json -Compress -Depth 8
        [IO.File]::AppendAllText($sessionPath,([Environment]::NewLine+$usage),$encoding)
        Start-Sleep -Milliseconds 1500
    }
    Start-Sleep -Seconds 2
    $logText = Get-Content -Raw -Encoding UTF8 -LiteralPath $runtimeLog
    if ($logText -notmatch 'Main quiet indicator: expanded' -or $logText -notmatch 'Task quiet indicator: #[0-9]+ expanded') { throw 'Synthetic task activity did not expand the quiet indicators.' }
    if (([regex]::Matches($logText,'Context alert: behavior-workspace .* level=')).Count -ne 3) { throw 'Behavior runtime did not emit three staged context alerts.' }
    foreach($level in 1..3){if($logText -notmatch ('Context visual alert: level='+$level)){throw "Behavior runtime did not render context visual level $level."}}
    if ($logText -match 'Dispatcher error:|HUD Loaded error:') { throw 'Behavior runtime log contains a HUD error.' }

    [IO.File]::WriteAllText((Join-Path $stateRoot 'exit.signal'),[DateTime]::UtcNow.ToString('O'),$encoding)
    if (-not $process.WaitForExit(10000) -or $process.ExitCode -ne 0) { throw 'Behavior HUD did not exit cleanly.' }
    Write-Output 'Isolated behavior runtime: OK (numbered quiet-task bars, terminal retention, activity expansion, three context stages)'
} finally {
    if ($null -ne $process -and -not $process.HasExited) { try{$process.Kill()}catch{} }
    $env:LOCALAPPDATA=$savedLocalAppData;$env:USERPROFILE=$savedUserProfile;$env:HOME=$savedHome;$env:PSModuleAnalysisCachePath=$savedModuleAnalysisCache;$env:CODEX_MONITOR_HUD_DEBUG_PATH=$savedDebugPath
}
