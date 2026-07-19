param(
    [ValidateSet('summary','list','split','quiet','settings','notifications')][string]$Mode = 'list',
    [ValidateRange(1,12)][int]$TaskCount = 5,
    [string]$TestOutputRoot = '',
    [string]$ExecutablePath = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($TestOutputRoot)) {
    $TestOutputRoot = Join-Path $env:TEMP 'CodexMonitorHudMacHostTests'
}
elseif (-not [IO.Path]::IsPathRooted($TestOutputRoot)) {
    $TestOutputRoot = Join-Path $root $TestOutputRoot
}
$TestOutputRoot = [IO.Path]::GetFullPath($TestOutputRoot)
$dotnet = Join-Path $root 'private/toolchain/dotnet/dotnet.exe'
$app = Join-Path $root 'src-dotnet/CodexMonitorHud.Mac/bin/Release/net10.0/CodexMonitorHud.dll'
if ([string]::IsNullOrWhiteSpace($ExecutablePath) -and -not (Test-Path -LiteralPath $app)) { throw 'Build CodexMonitorHud.Mac before running the isolated host test.' }
if (-not [string]::IsNullOrWhiteSpace($ExecutablePath) -and -not (Test-Path -LiteralPath $ExecutablePath)) { throw "Mac host executable is missing: $ExecutablePath" }

$scenarioRoot = Join-Path $TestOutputRoot ("{0}-{1}-{2}" -f $Mode,$TaskCount,[Guid]::NewGuid().ToString('N'))
$homeRoot = Join-Path $scenarioRoot 'home'
$stateRoot = Join-Path $scenarioRoot 'state'
$sessionsRoot = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $homeRoot '.codex') 'sessions') '2026') '07') '19'
$indexPath = Join-Path $homeRoot '.codex\session_index.jsonl'
$smokePath = Join-Path $scenarioRoot 'smoke.json'
New-Item -ItemType Directory -Force -Path $sessionsRoot,$stateRoot | Out-Null

$settings = Get-Content -LiteralPath (Join-Path $root 'config.default.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$settings.multiTask.displayMode = if ($Mode -in @('quiet','settings','notifications')) { 'list' } else { $Mode }
if ($Mode -eq 'quiet') {
    $settings.behavior.idleIndicator.enabled = $true
    $settings.behavior.idleIndicator.afterMinutes = 0.01
    $settings.behavior.idleIndicator.layout = 'horizontal'
}
if ($Mode -eq 'notifications') {
    $settings.agentNotifications.enabled = $true
}
[IO.File]::WriteAllText((Join-Path $stateRoot 'settings.json'),($settings | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))

$indexLines = New-Object Collections.Generic.List[string]
for ($number = 1; $number -le $TaskCount; $number++) {
    $sessionId = 'synthetic-mac-{0:d2}' -f $number
    $sessionPath = Join-Path $sessionsRoot ($sessionId + '.jsonl')
    $records = @(
        (@{ timestamp='2026-07-19T04:00:00Z'; type='session_meta'; payload=@{ id=$sessionId; cwd="/Users/synthetic/portable-$number"; originator='Codex Desktop'; source='vscode' } } | ConvertTo-Json -Compress -Depth 8),
        (@{ timestamp='2026-07-19T04:00:01Z'; type='turn_context'; payload=@{ cwd="/Users/synthetic/portable-$number"; model='gpt-test' } } | ConvertTo-Json -Compress -Depth 8),
        (@{ timestamp='2026-07-19T04:00:02Z'; type='event_msg'; payload=@{ type='task_started'; turn_id="turn-$number" } } | ConvertTo-Json -Compress -Depth 8),
        (@{ timestamp=(Get-Date).ToUniversalTime().ToString('O'); type='event_msg'; payload=@{ type='token_count'; info=@{ last_token_usage=@{ input_tokens=1000; cached_input_tokens=600; output_tokens=120; reasoning_output_tokens=20; total_tokens=1120 }; total_token_usage=@{ input_tokens=1000; cached_input_tokens=600; output_tokens=120; total_tokens=(1000*$number+120) }; model_context_window=200000 } } } | ConvertTo-Json -Compress -Depth 12)
    )
    [IO.File]::WriteAllText($sessionPath,($records -join "`n") + "`n",(New-Object Text.UTF8Encoding($false)))
    $indexLines.Add((@{ id=$sessionId; thread_name="Synthetic Mac task $number"; updated_at=(Get-Date).ToUniversalTime().ToString('O') } | ConvertTo-Json -Compress))
}
[IO.File]::WriteAllText($indexPath,($indexLines -join "`n") + "`n",(New-Object Text.UTF8Encoding($false)))
if ($Mode -eq 'notifications') {
    $notificationsRoot = Join-Path $stateRoot 'notifications'
    New-Item -ItemType Directory -Force -Path $notificationsRoot | Out-Null
    $notice = @{ source='codex-mcp'; task_number=1; message='Synthetic Mac attention notice' } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $notificationsRoot 'notice.json'),$notice,(New-Object Text.UTF8Encoding($false)))
}

$process = $null
try {
    $arguments = @(
        '--plugin-root', ('"{0}"' -f $root),
        '--test-home', ('"{0}"' -f $homeRoot),
        '--test-state-root', ('"{0}"' -f $stateRoot),
        '--smoke-output', ('"{0}"' -f $smokePath)
    )
    if ($Mode -eq 'settings') { $arguments += @('--open-settings','--smoke-settings-update') }
    $processFile = $dotnet
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { $arguments = @(('"{0}"' -f $app)) + $arguments }
    else { $processFile = $ExecutablePath }
    $startParameters = @{ FilePath = $processFile; ArgumentList = $arguments; PassThru = $true }
    if ($IsWindows -or $null -eq (Get-Variable IsWindows -ErrorAction SilentlyContinue)) { $startParameters.WindowStyle = 'Hidden' }
    $process = Start-Process @startParameters
    $ready = $false
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        if (Test-Path -LiteralPath $smokePath) { $ready = $true; break }
        if ($process.HasExited) { break }
        Start-Sleep -Milliseconds 250
        $process.Refresh()
    }
    if (-not $ready) {
        throw "Avalonia Mac host smoke output was not produced; exited=$($process.HasExited); code=$(if($process.HasExited){$process.ExitCode}else{'running'})"
    }
    $smoke = Get-Content -LiteralPath $smokePath -Encoding UTF8 -Raw | ConvertFrom-Json
    if ([int]$smoke.visible_tasks -ne $TaskCount) { throw "Expected $TaskCount visible tasks, found $($smoke.visible_tasks)." }
    $expectedMode = if ($Mode -in @('quiet','settings','notifications')) { 'list' } else { $Mode }
    if ([string]$smoke.display_mode -ne $expectedMode) { throw "Expected mode $expectedMode, found $($smoke.display_mode)." }
    if ([string]$smoke.heartbeat -ne 'present' -or [string]$smoke.registry -ne 'present') { throw 'Heartbeat or registry evidence is missing.' }
    if ($Mode -eq 'quiet' -and -not [bool]$smoke.quiet) { throw 'Quiet projection did not activate.' }
    if ($Mode -eq 'settings' -and [math]::Abs([double]$smoke.settings_opacity - 0.88) -gt 0.001) { throw 'Settings update did not persist and reload.' }
    if ($Mode -eq 'notifications' -and [int]$smoke.active_notices -lt 1) { throw 'Synthetic notification was not accepted by the visible task.' }
    if (-not $process.WaitForExit(10000)) { throw 'Avalonia Mac host did not exit after smoke completion.' }
    if ($process.ExitCode -ne 0) { throw "Avalonia Mac host exited with code $($process.ExitCode)." }
    Write-Output "Avalonia Mac host isolated smoke: OK ($TaskCount synthetic tasks, $Mode)"
} finally {
    if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
}
