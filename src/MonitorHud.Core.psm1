Set-StrictMode -Version Latest

function Get-HudPaths {
    param([Parameter(Mandatory = $true)][string]$PluginRoot)
    $stateRoot = Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD'
    [pscustomobject]@{
        PluginRoot = $PluginRoot
        SessionsRoot = Join-Path $HOME '.codex\sessions'
        StateRoot = $stateRoot
        ConfigPath = Join-Path $stateRoot 'settings.json'
        DefaultConfigPath = Join-Path $PluginRoot 'config.default.json'
        LocaleRoot = Join-Path $PluginRoot 'locales'
    }
}

function Merge-HudConfig {
    param($Default, $Saved)
    if ($null -eq $Saved) { return $Default }
    foreach ($property in $Saved.PSObject.Properties) {
        $defaultProperty = $Default.PSObject.Properties[$property.Name]
        if ($null -eq $defaultProperty) { continue }
        if ($null -ne $property.Value -and $property.Value -is [pscustomobject] -and $defaultProperty.Value -is [pscustomobject]) {
            $Default.($property.Name) = Merge-HudConfig $defaultProperty.Value $property.Value
        } else {
            $Default.($property.Name) = $property.Value
        }
    }
    return $Default
}

function Get-HudThemes {
    param([Parameter(Mandatory = $true)][string]$PluginRoot)
    $themeRoots = @(
        [pscustomobject]@{ Path = Join-Path $PluginRoot 'themes'; Kind = 'built-in' },
        [pscustomobject]@{ Path = Join-Path (Join-Path $env:LOCALAPPDATA 'CodexMonitorHUD') 'themes'; Kind = 'user' }
    )
    $byId = [ordered]@{}
    foreach ($root in $themeRoots) {
        if (-not (Test-Path -LiteralPath $root.Path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $root.Path -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue) {
            try {
                $theme = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace([string]$theme.id) -or $null -eq $theme.settings) { continue }
                $theme | Add-Member -NotePropertyName SourcePath -NotePropertyValue $file.FullName -Force
                $theme | Add-Member -NotePropertyName SourceKind -NotePropertyValue ([string]$root.Kind) -Force
                # User themes are scanned last so a locally customized copy can
                # intentionally replace the visible preset with the same id.
                $byId[[string]$theme.id] = $theme
            } catch { }
        }
    }
    return @($byId.Values | Sort-Object @{ Expression = { if ($null -ne $_.PSObject.Properties['order']) { [int]$_.order } else { 999 } } }, id)
}

function Get-HudPricingCatalog {
    param([Parameter(Mandatory = $true)][string]$PluginRoot, [string]$ConfiguredPath = '')
    $path = [string]$ConfiguredPath
    $kind = 'custom'
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $path = [Environment]::ExpandEnvironmentVariables($path.Trim())
        if ($path.StartsWith('~\')) { $path = Join-Path $HOME $path.Substring(2) }
    } else {
        $path = Join-Path $PluginRoot 'pricing.default.json'
        $kind = 'built-in'
    }
    $catalog = [pscustomobject]@{ Loaded=$false; Path=$path; Kind=$kind; Models=@{}; Aliases=@{}; Source=$null; Error='' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $catalog.Error='not_found'; return $catalog }
    try {
        $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
        $modelsNode = if ($null -ne $raw.PSObject.Properties['models']) { $raw.models } else { $raw }
        foreach ($property in $modelsNode.PSObject.Properties) {
            if ($property.Name.StartsWith('_') -or $null -eq $property.Value) { continue }
            $rates = $property.Value
            foreach ($required in @('input_per_million','output_per_million')) {
                if ($null -eq $rates.PSObject.Properties[$required]) { throw "missing $required for $($property.Name)" }
            }
            $inputRate=[double]$rates.input_per_million
            $cachedRate=if($null -ne $rates.PSObject.Properties['cached_input_per_million']){[double]$rates.cached_input_per_million}else{$inputRate}
            $outputRate=[double]$rates.output_per_million
            if($inputRate -lt 0 -or $cachedRate -lt 0 -or $outputRate -lt 0){throw "negative rate for $($property.Name)"}
            $catalog.Models[$property.Name]=[pscustomobject]@{Input=$inputRate;Cached=$cachedRate;Output=$outputRate;Estimated=($null -ne $rates.PSObject.Properties['estimated'] -and [bool]$rates.estimated)}
        }
        if ($null -ne $raw.PSObject.Properties['aliases']) {
            foreach ($alias in $raw.aliases.PSObject.Properties) { if (-not [string]::IsNullOrWhiteSpace([string]$alias.Value)) { $catalog.Aliases[$alias.Name]=[string]$alias.Value } }
        }
        if ($null -ne $raw.PSObject.Properties['_source']) { $catalog.Source=$raw._source }
        $catalog.Loaded=$catalog.Models.Count -gt 0
    } catch { $catalog.Error=$_.Exception.Message }
    return $catalog
}

function Get-HudCostEstimate {
    param([Parameter(Mandatory = $true)]$Snapshot, [Parameter(Mandatory = $true)]$Catalog)
    if (-not [bool]$Catalog.Loaded) { return $null }
    $model=[string]$Snapshot.Model
    $pricedAs=$model
    if (-not $Catalog.Models.ContainsKey($pricedAs) -and $Catalog.Aliases.ContainsKey($model)) { $pricedAs=[string]$Catalog.Aliases[$model] }
    if (-not $Catalog.Models.ContainsKey($pricedAs)) { return $null }
    $rates=$Catalog.Models[$pricedAs]
    $input=if($null -ne $Snapshot.PSObject.Properties['TaskInput']){[double]$Snapshot.TaskInput}else{[double]$Snapshot.Input}
    $cached=if($null -ne $Snapshot.PSObject.Properties['TaskCached']){[double]$Snapshot.TaskCached}else{[double]$Snapshot.Cached}
    $output=if($null -ne $Snapshot.PSObject.Properties['TaskOutput']){[double]$Snapshot.TaskOutput}else{[double]$Snapshot.Output}
    $uncached=[Math]::Max(0,$input-$cached)
    [pscustomobject]@{ CostUsd=(($uncached*$rates.Input)+($cached*$rates.Cached)+($output*$rates.Output))/1000000.0; PricedAs=$pricedAs; Estimated=[bool]$rates.Estimated }
}

function Format-HudCost {
    param($Value)
    if ($null -eq $Value) { return '--' }
    $cost=[double]$Value
    $format=if($cost -lt 0.01){'0.0000'}elseif($cost -lt 1){'0.000'}else{'0.00'}
    return ('~${0}' -f $cost.ToString($format,[Globalization.CultureInfo]::InvariantCulture))
}

function Get-HudConfig {
    param([Parameter(Mandatory = $true)]$Paths)
    $default = Get-Content -Raw -Encoding UTF8 -LiteralPath $Paths.DefaultConfigPath | ConvertFrom-Json
    $result = $default
    if (Test-Path -LiteralPath $Paths.ConfigPath) {
        try {
            $saved = Get-Content -Raw -Encoding UTF8 -LiteralPath $Paths.ConfigPath | ConvertFrom-Json
            $hadMultiTask = $null -ne $saved.PSObject.Properties['multiTask']
            $legacyTaskFields = if ($hadMultiTask -and $null -ne $saved.multiTask.PSObject.Properties['taskFields']) { $saved.multiTask.taskFields } else { $null }
            $hadBubbleFields = $hadMultiTask -and $null -ne $saved.multiTask.PSObject.Properties['bubbleFields']
            $result = Merge-HudConfig $default $saved
            if (-not $hadMultiTask) { $result.monitorScope = 'aggregate' }
            if (-not $hadBubbleFields -and $null -ne $legacyTaskFields) {
                foreach ($field in @('model','callTotal','taskTotal','updated')) {
                    if ($null -ne $legacyTaskFields.PSObject.Properties[$field]) { $result.multiTask.bubbleFields.$field = [bool]$legacyTaskFields.$field }
                }
            }
        } catch { $result = $default }
    }
    if (@('summary','list','split') -notcontains [string]$result.multiTask.displayMode) { $result.multiTask.displayMode = 'summary' }
    if (@('rows','cards','rail') -notcontains [string]$result.multiTask.listStyle) { $result.multiTask.listStyle = 'rows' }
    if (@('compact','balanced','relaxed') -notcontains [string]$result.multiTask.listDensity) { $result.multiTask.listDensity = 'compact' }
    if (@('hover','always','hidden') -notcontains [string]$result.multiTask.nameMode) { $result.multiTask.nameMode = 'hover' }
    $result.multiTask.maxSplitBubbles = [Math]::Max(1, [Math]::Min(12, [int]$result.multiTask.maxSplitBubbles))
    $result.multiTask.numberCooldownSeconds = [Math]::Max(0, [Math]::Min(3600, [int]$result.multiTask.numberCooldownSeconds))
    foreach ($modeProperty in @('summaryMode','listMode','taskBubbleMode')) {
        $legacyMode = [string]$result.attention.$modeProperty
        if ($legacyMode -eq 'dot') {
            $result.attention.$modeProperty = 'off'
            $result.attention.dotEnabled = $true
        } elseif ($legacyMode -eq 'bubble') {
            $result.attention.$modeProperty = 'breathe'
        } elseif (@('off','halo','breathe','flow','focus') -notcontains $legacyMode) {
            $result.attention.$modeProperty = if ($modeProperty -eq 'summaryMode') { 'halo' } else { 'flow' }
        }
    }
    if (@('soft','heartbeat','beacon') -notcontains [string]$result.attention.dotPattern) { $result.attention.dotPattern = 'heartbeat' }
    if (@('subtle','balanced','bright') -notcontains [string]$result.attention.dotBrightness) { $result.attention.dotBrightness = 'balanced' }
    if (@('slow','normal','fast') -notcontains [string]$result.attention.dotSpeed) { $result.attention.dotSpeed = 'normal' }
    $result.attention.dotEnabled = [bool]$result.attention.dotEnabled
    $result.attention.dotBreathing = [bool]$result.attention.dotBreathing
    $result.attention.durationSeconds = [Math]::Max(2, [Math]::Min(15, [int]$result.attention.durationSeconds))
    if ($null -eq $result.attention.PSObject.Properties['completionGraceSeconds']) {
        $result.attention | Add-Member -NotePropertyName completionGraceSeconds -NotePropertyValue 8
    }
    $result.attention.completionGraceSeconds = [Math]::Max(0, [Math]::Min(30, [int]$result.attention.completionGraceSeconds))
    if (@('text','expressive') -notcontains [string]$result.agentNotifications.permission) { $result.agentNotifications.permission='text' }
    if (@('halo','breathe','flow','focus') -notcontains [string]$result.agentNotifications.mode) { $result.agentNotifications.mode='focus' }
    if (@('violet','aqua','amber','custom') -notcontains [string]$result.agentNotifications.glowPreset) { $result.agentNotifications.glowPreset='violet' }
    if (@('subtle','balanced','strong') -notcontains [string]$result.agentNotifications.intensity) { $result.agentNotifications.intensity='balanced' }
    $result.agentNotifications.enabled=[bool]$result.agentNotifications.enabled
    $result.agentNotifications.durationSeconds=[Math]::Max(4,[Math]::Min(60,[int]$result.agentNotifications.durationSeconds))
    try { [void][Windows.Media.ColorConverter]::ConvertFromString([string]$result.agentNotifications.color) } catch { $result.agentNotifications.color='#FF7C3AED' }
    if (@('uniform','layered','focus') -notcontains [string]$result.transparencyMode) { $result.transparencyMode = 'uniform' }
    $result.opacity = [Math]::Max(0.15, [Math]::Min(1.0, [double]$result.opacity))
    if (@('solid','gradient','image') -notcontains [string]$result.themeStyle.surface) { $result.themeStyle.surface = 'solid' }
    if (@('uniform','uniformToFill','fill','none') -notcontains [string]$result.themeStyle.imageStretch) { $result.themeStyle.imageStretch = 'uniformToFill' }
    if (@('none','soft','deep') -notcontains [string]$result.themeStyle.shadow) { $result.themeStyle.shadow = 'soft' }
    $result.themeStyle.gradientAngle = (($result.themeStyle.gradientAngle % 360) + 360) % 360
    $result.themeStyle.imageOpacity = [Math]::Max(0.05, [Math]::Min(1.0, [double]$result.themeStyle.imageOpacity))
    $result.themeStyle.borderWidth = [Math]::Max(0, [Math]::Min(4.0, [double]$result.themeStyle.borderWidth))
    $result.themeStyle.statusDotSize = [Math]::Max(5.0, [Math]::Min(18.0, [double]$result.themeStyle.statusDotSize))
    if ([string]::IsNullOrWhiteSpace([string]$result.themeStyle.fontFamily)) { $result.themeStyle.fontFamily = 'Segoe UI Variable Text, Microsoft YaHei UI' }
    $result.statusTiming.terminalHoldSeconds = [Math]::Max(5, [Math]::Min(300, [int]$result.statusTiming.terminalHoldSeconds))
    $result.pricing.path = [string]$result.pricing.path
    return $result
}

function Save-HudConfig {
    param([Parameter(Mandatory = $true)]$Paths, [Parameter(Mandatory = $true)]$Config)
    New-Item -ItemType Directory -Force -Path $Paths.StateRoot | Out-Null
    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Paths.ConfigPath -Encoding UTF8
}

function New-HudTaskNumberPool {
    param([int]$MaximumReleased = 512)
    [pscustomobject]@{
        NextNumber = 1
        MaximumReleased = [Math]::Max(32, $MaximumReleased)
        Released = New-Object 'System.Collections.Generic.Queue[object]'
        ReleasedSet = @{}
    }
}

function Get-HudTaskNumber {
    param(
        [Parameter(Mandatory = $true)]$Pool,
        [DateTimeOffset]$Now = [DateTimeOffset]::Now
    )
    if ($Pool.Released.Count -gt 0 -and $Pool.Released.Peek().AvailableAt -le $Now) {
        $candidate = $Pool.Released.Dequeue()
        $Pool.ReleasedSet.Remove([int]$candidate.Number)
        return [int]$candidate.Number
    }
    $number = [int]$Pool.NextNumber
    $Pool.NextNumber = $number + 1
    return $number
}

function Add-HudReleasedTaskNumber {
    param(
        [Parameter(Mandatory = $true)]$Pool,
        [int]$Number,
        [int]$CooldownSeconds = 120,
        [DateTimeOffset]$Now = [DateTimeOffset]::Now
    )
    if ($Number -le 0) { return }
    if ($Pool.ReleasedSet.ContainsKey($Number) -or $Pool.Released.Count -ge [int]$Pool.MaximumReleased) { return }
    $candidate = [pscustomobject]@{
        Number = $Number
        AvailableAt = $Now.AddSeconds([Math]::Max(0, $CooldownSeconds))
    }
    $Pool.Released.Enqueue($candidate)
    $Pool.ReleasedSet[$Number] = $true
}

function Get-HudLocale {
    param([Parameter(Mandatory = $true)]$Paths, [Parameter(Mandatory = $true)][string]$Language)
    $path = Join-Path $Paths.LocaleRoot ($Language + '.json')
    if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $Paths.LocaleRoot 'en.json' }
    Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json
}

function Get-LatestHudSessionFile {
    param([Parameter(Mandatory = $true)][string]$SessionsRoot)
    if (-not (Test-Path -LiteralPath $SessionsRoot)) { return $null }
    # Session folders are grouped by the thread's creation date, not the date
    # it was resumed. A task reopened days later keeps writing to its original
    # folder, so date-folder shortcuts silently lose real concurrent work.
    $files = Get-ChildItem -LiteralPath $SessionsRoot -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue
    $files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Get-ActiveHudSessionFiles {
    param(
        [Parameter(Mandatory = $true)][string]$SessionsRoot,
        [int]$ActiveWindowMinutes = 30,
        [int]$MaximumFiles = 64
    )
    if (-not (Test-Path -LiteralPath $SessionsRoot)) { return @() }
    $cutoff = [DateTime]::UtcNow.AddMinutes(-[Math]::Max(1, $ActiveWindowMinutes))
    $files = New-Object System.Collections.ArrayList
    foreach ($file in Get-ChildItem -LiteralPath $SessionsRoot -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue) {
        if ($file.LastWriteTimeUtc -ge $cutoff) { [void]$files.Add($file) }
    }
    if ($files.Count -eq 0) {
        $latest = Get-LatestHudSessionFile $SessionsRoot
        if ($null -ne $latest) { return @($latest) }
        return @()
    }
    return @($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First ([Math]::Max(1, $MaximumFiles)))
}

function Convert-HudRecord {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    try { $record = $Line | ConvertFrom-Json } catch { return $null }
    if ($record.type -eq 'turn_context') {
        $workspace = ''
        if ($null -ne $record.payload.PSObject.Properties['cwd']) {
            try {
                $cwd = [string]$record.payload.cwd
                if (-not [string]::IsNullOrWhiteSpace($cwd)) {
                    $trimmed = $cwd.TrimEnd([char[]]@('\','/'))
                    $workspace = [IO.Path]::GetFileName($trimmed)
                    if ([string]::IsNullOrWhiteSpace($workspace)) { $workspace = $trimmed }
                }
            } catch { $workspace = '' }
        }
        return [pscustomobject]@{
            Kind = 'context'
            Model = [string]$record.payload.model
            Workspace = $workspace
        }
    }
    if ($record.type -eq 'event_msg' -and @('task_started','task_complete','turn_aborted') -contains [string]$record.payload.type) {
        try { $eventTimestamp = [DateTimeOffset]::Parse($record.timestamp).ToLocalTime() } catch { $eventTimestamp = [DateTimeOffset]::Now }
        $kind = switch ([string]$record.payload.type) {
            'task_started' { 'started' }
            'task_complete' {
                # Codex emits task_complete for a turn boundary, including a
                # small number of internal/silent stops with no visible final
                # message. Those are lifecycle data, not a user-facing reason
                # to demand attention.
                $visibleMessage = if ($null -ne $record.payload.PSObject.Properties['last_agent_message']) { [string]$record.payload.last_agent_message } else { '' }
                if ([string]::IsNullOrWhiteSpace($visibleMessage)) { 'completed_silent' }
                else { 'completed' }
            }
            'turn_aborted' { 'aborted' }
        }
        $turnId = if ($null -ne $record.payload.PSObject.Properties['turn_id']) { [string]$record.payload.turn_id } else { '' }
        return [pscustomobject]@{
            Kind = $kind
            Timestamp = $eventTimestamp
            TurnId = $turnId
        }
    }
    if ($record.type -ne 'event_msg' -or $record.payload.type -ne 'token_count') { return $null }
    try { $timestamp = [DateTimeOffset]::Parse($record.timestamp).ToLocalTime() } catch { return $null }
    $weeklyRemaining = $null
    $fiveHourRemaining = $null
    if ($null -ne $record.payload.PSObject.Properties['rate_limits']) {
        $rateLimits = $record.payload.rate_limits
        foreach ($windowName in @('primary','secondary')) {
            if ($null -eq $rateLimits -or $null -eq $rateLimits.PSObject.Properties[$windowName]) { continue }
            $rateWindow = $rateLimits.$windowName
            if ($null -eq $rateWindow -or $null -eq $rateWindow.PSObject.Properties['used_percent'] -or $null -eq $rateWindow.PSObject.Properties['window_minutes']) { continue }
            try {
                $usedPercent = [double]$rateWindow.used_percent
                $windowMinutes = [int]$rateWindow.window_minutes
                $remainingPercent = [Math]::Max(0, [Math]::Min(100, [Math]::Round(100.0 - $usedPercent, 1)))
                if ($windowMinutes -ge 10080) { $weeklyRemaining = $remainingPercent }
                elseif ($windowMinutes -ge 240 -and $windowMinutes -le 360) { $fiveHourRemaining = $remainingPercent }
            } catch { }
        }
    }
    $hasAllowance = $null -ne $weeklyRemaining -or $null -ne $fiveHourRemaining
    $last = $record.payload.info.last_token_usage
    $total = $record.payload.info.total_token_usage
    if ($null -eq $last -or $null -eq $total) {
        if (-not $hasAllowance) { return $null }
        return [pscustomobject]@{
            Kind = 'allowance'
            Timestamp = $timestamp
            AllowanceTimestamp = $timestamp
            WeeklyRemainingPercent = $weeklyRemaining
            FiveHourRemainingPercent = $fiveHourRemaining
        }
    }
    $input = [Int64]$last.input_tokens
    $cached = [Int64]$last.cached_input_tokens
    $output = [Int64]$last.output_tokens
    $taskInput = if ($null -ne $total.PSObject.Properties['input_tokens']) { [Int64]$total.input_tokens } else { $input }
    $taskCached = if ($null -ne $total.PSObject.Properties['cached_input_tokens']) { [Int64]$total.cached_input_tokens } else { $cached }
    $taskOutput = if ($null -ne $total.PSObject.Properties['output_tokens']) { [Int64]$total.output_tokens } else { $output }
    if ($input -eq 0 -and $output -eq 0) {
        if (-not $hasAllowance) { return $null }
        return [pscustomobject]@{
            Kind = 'allowance'
            Timestamp = $timestamp
            AllowanceTimestamp = $timestamp
            WeeklyRemainingPercent = $weeklyRemaining
            FiveHourRemainingPercent = $fiveHourRemaining
        }
    }
    $window = [Int64]$record.payload.info.model_context_window
    $contextPercent = if ($window -gt 0) { [Math]::Min(100, [Math]::Round(($input * 100.0) / $window, 1)) } else { 0 }
    [pscustomobject]@{
        Kind = 'usage'
        Timestamp = $timestamp
        Input = $input
        Cached = $cached
        Uncached = [Math]::Max([Int64]0, $input - $cached)
        Output = $output
        Reasoning = [Int64]$last.reasoning_output_tokens
        TaskInput = $taskInput
        TaskCached = $taskCached
        TaskUncached = [Math]::Max([Int64]0, $taskInput - $taskCached)
        TaskOutput = $taskOutput
        CallTotal = $input + $output
        TaskTotal = [Int64]$total.total_tokens
        ContextPercent = $contextPercent
        ContextWindow = $window
        Model = ''
        AllowanceTimestamp = if ($hasAllowance) { $timestamp } else { $null }
        WeeklyRemainingPercent = $weeklyRemaining
        FiveHourRemainingPercent = $fiveHourRemaining
    }
}

function Split-HudJsonLines {
    param([string]$PendingText = '', [string]$Text = '')
    $combined = [string]$PendingText + [string]$Text
    if ([string]::IsNullOrEmpty($combined)) {
        return [pscustomobject]@{ CompleteLines = @(); PendingText = '' }
    }
    $parts = $combined -split "`n", -1
    $complete = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt ($parts.Count - 1); $i++) { [void]$complete.Add($parts[$i].TrimEnd("`r")) }
    $pending = ''
    if (-not $combined.EndsWith("`n")) {
        $candidate = $parts[-1].TrimEnd("`r")
        try {
            $parsed = $candidate | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $parsed) { [void]$complete.Add($candidate) } else { $pending = $parts[-1] }
        } catch { $pending = $parts[-1] }
    }
    return [pscustomobject]@{ CompleteLines = @($complete); PendingText = $pending }
}

function Get-LatestHudSnapshot {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File, [int]$Tail = 2000)
    # Read a bounded UTF-8 byte window directly. Windows PowerShell 5.1's
    # Get-Content -Tail can both decode non-ASCII JSON incorrectly and omit a
    # final non-newline-terminated record, which loses task_complete events.
    $stream = New-Object IO.FileStream($File.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $window = [Math]::Min([Int64](8MB),$stream.Length)
        $startsMidFile = ($window -lt $stream.Length)
        [void]$stream.Seek(-$window,[IO.SeekOrigin]::End)
        $buffer = New-Object byte[] $window
        $read = $stream.Read($buffer,0,[int]$window)
        $tailText = [Text.Encoding]::UTF8.GetString($buffer,0,$read)
        $parts = @($tailText -split "`n" | ForEach-Object { [string]$_.TrimEnd("`r") })
        if ($startsMidFile -and $parts.Count -gt 0) { $parts = @($parts | Select-Object -Skip 1) }
        $lines = @($parts | Select-Object -Last ([Math]::Max(1,$Tail)))
    } finally { $stream.Dispose() }
    $usage = $null
    $allowance = $null
    $model = ''
    $workspace = ''
    $lifecycleSeen = $false
    $terminalStatus = ''
    $terminalTimestamp = $null
    $terminalSilent = $false
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $item = Convert-HudRecord $lines[$i]
        if ($null -eq $item) { continue }
        if (-not $lifecycleSeen -and @('started','completed','completed_silent','aborted') -contains [string]$item.Kind) {
            $lifecycleSeen = $true
            if (@('completed','completed_silent','aborted') -contains [string]$item.Kind) {
                $terminalStatus = if ($item.Kind -eq 'completed_silent') { 'completed' } else { [string]$item.Kind }
                $terminalTimestamp = $item.Timestamp
                $terminalSilent = ($item.Kind -eq 'completed_silent')
            }
        }
        if (($item.Kind -eq 'usage' -or $item.Kind -eq 'allowance') -and $null -eq $allowance) {
            if (($null -ne $item.PSObject.Properties['WeeklyRemainingPercent'] -and $null -ne $item.WeeklyRemainingPercent) -or
                ($null -ne $item.PSObject.Properties['FiveHourRemainingPercent'] -and $null -ne $item.FiveHourRemainingPercent)) {
                $allowance = $item
            }
        }
        if ($item.Kind -eq 'usage' -and $null -eq $usage) { $usage = $item }
        if ($item.Kind -eq 'context') {
            if ([string]::IsNullOrWhiteSpace($model)) { $model = $item.Model }
            if ([string]::IsNullOrWhiteSpace($workspace) -and $null -ne $item.PSObject.Properties['Workspace']) { $workspace = [string]$item.Workspace }
        }
        if ($lifecycleSeen -and $null -ne $usage -and $null -ne $allowance -and -not [string]::IsNullOrWhiteSpace($model) -and -not [string]::IsNullOrWhiteSpace($workspace)) { break }
    }
    if ($null -ne $usage) {
        $usage.Model = $model
        $usage | Add-Member -NotePropertyName Workspace -NotePropertyValue $workspace -Force
        $usage | Add-Member -NotePropertyName TerminalStatus -NotePropertyValue $terminalStatus -Force
        $usage | Add-Member -NotePropertyName TerminalTimestamp -NotePropertyValue $terminalTimestamp -Force
        $usage | Add-Member -NotePropertyName TerminalSilent -NotePropertyValue $terminalSilent -Force
        if ($null -ne $allowance) {
            $usage.AllowanceTimestamp = $allowance.AllowanceTimestamp
            $usage.WeeklyRemainingPercent = $allowance.WeeklyRemainingPercent
            $usage.FiveHourRemainingPercent = $allowance.FiveHourRemainingPercent
        }
    }
    return $usage
}

function Get-LatestHudAllowanceSnapshot {
    param([Parameter(Mandatory = $true)][object[]]$Snapshots)
    return $Snapshots | Where-Object {
        ($null -ne $_ -and $null -ne $_.PSObject.Properties['WeeklyRemainingPercent'] -and $null -ne $_.WeeklyRemainingPercent) -or
        ($null -ne $_ -and $null -ne $_.PSObject.Properties['FiveHourRemainingPercent'] -and $null -ne $_.FiveHourRemainingPercent)
    } | Sort-Object @{ Expression = {
        if ($null -ne $_.PSObject.Properties['AllowanceTimestamp'] -and $null -ne $_.AllowanceTimestamp) { $_.AllowanceTimestamp }
        else { $_.Timestamp }
    }; Descending = $true } | Select-Object -First 1
}

function Format-HudNumber {
    param([Int64]$Value, [string]$Mode = 'exact')
    if ($Mode -eq 'exact' -or ($Mode -eq 'auto' -and [Math]::Abs($Value) -lt 1000000)) {
        return $Value.ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('en-US'))
    }
    $abs = [Math]::Abs([double]$Value)
    if ($abs -ge 1000000000) { return ('{0:0.#}B' -f ($Value / 1000000000.0)) }
    if ($abs -ge 1000000) { return ('{0:0.#}M' -f ($Value / 1000000.0)) }
    if ($abs -ge 1000) { return ('{0:0.#}K' -f ($Value / 1000.0)) }
    return [string]$Value
}

function Get-HudMetrics {
    param([Parameter(Mandatory = $true)]$Snapshot, [Parameter(Mandatory = $true)]$Config, [Parameter(Mandatory = $true)]$Locale)
    $metrics = New-Object System.Collections.ArrayList
    $values = [ordered]@{
        input = Format-HudNumber $Snapshot.Input $Config.numberFormat
        cached = Format-HudNumber $Snapshot.Cached $Config.numberFormat
        uncached = Format-HudNumber $Snapshot.Uncached $Config.numberFormat
        output = Format-HudNumber $Snapshot.Output $Config.numberFormat
        reasoning = Format-HudNumber $Snapshot.Reasoning $Config.numberFormat
        callTotal = Format-HudNumber $Snapshot.CallTotal $Config.numberFormat
        taskTotal = Format-HudNumber $Snapshot.TaskTotal $Config.numberFormat
        context = ('{0:0.#}%' -f $Snapshot.ContextPercent)
        model = if ([string]::IsNullOrWhiteSpace($Snapshot.Model)) { '-' } else { $Snapshot.Model }
        updated = $Snapshot.Timestamp.ToString('HH:mm:ss')
        activeTasks = if ($null -ne $Snapshot.PSObject.Properties['ActiveTasks']) { Format-HudNumber ([Int64]$Snapshot.ActiveTasks) $Config.numberFormat } else { '1' }
        weeklyRemaining = if ($null -ne $Snapshot.PSObject.Properties['WeeklyRemainingPercent'] -and $null -ne $Snapshot.WeeklyRemainingPercent) { ('{0:0.#}%' -f [double]$Snapshot.WeeklyRemainingPercent) } else { '--' }
        estimatedCost = if ($null -ne $Snapshot.PSObject.Properties['EstimatedCostUsd']) { Format-HudCost $Snapshot.EstimatedCostUsd } else { '--' }
    }
    foreach ($key in $values.Keys) {
        if ([bool]$Config.fields.$key) {
            [void]$metrics.Add([pscustomobject]@{ Key = $key; Label = [string]$Locale.$key; Value = [string]$values[$key] })
        }
    }
    return @($metrics)
}

function Merge-HudSnapshots {
    param(
        [Parameter(Mandatory = $true)][object[]]$Snapshots,
        [Parameter(Mandatory = $true)]$Locale
    )
    $valid = @($Snapshots | Where-Object { $null -ne $_ })
    if ($valid.Count -eq 0) { return $null }
    if ($valid.Count -eq 1) {
        $one = $valid[0].PSObject.Copy()
        if ($null -eq $one.PSObject.Properties['ActiveTasks']) { $one | Add-Member -NotePropertyName ActiveTasks -NotePropertyValue 1 }
        return $one
    }

    $models = @($valid | ForEach-Object { [string]$_.Model } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $summary = [string]$Locale.multiTaskSummary
    $summary = $summary.Replace('{tasks}', [string]$valid.Count).Replace('{models}', [string]$models.Count)
    $rateSource = Get-LatestHudAllowanceSnapshot $valid
    [pscustomobject]@{
        Timestamp = ($valid | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        Input = [Int64](($valid | Measure-Object Input -Sum).Sum)
        Cached = [Int64](($valid | Measure-Object Cached -Sum).Sum)
        Uncached = [Int64](($valid | Measure-Object Uncached -Sum).Sum)
        Output = [Int64](($valid | Measure-Object Output -Sum).Sum)
        Reasoning = [Int64](($valid | Measure-Object Reasoning -Sum).Sum)
        TaskInput = [Int64](($valid | ForEach-Object { if($null -ne $_.PSObject.Properties['TaskInput']){$_.TaskInput}else{$_.Input} } | Measure-Object -Sum).Sum)
        TaskCached = [Int64](($valid | ForEach-Object { if($null -ne $_.PSObject.Properties['TaskCached']){$_.TaskCached}else{$_.Cached} } | Measure-Object -Sum).Sum)
        TaskUncached = [Int64](($valid | ForEach-Object { if($null -ne $_.PSObject.Properties['TaskUncached']){$_.TaskUncached}else{$_.Uncached} } | Measure-Object -Sum).Sum)
        TaskOutput = [Int64](($valid | ForEach-Object { if($null -ne $_.PSObject.Properties['TaskOutput']){$_.TaskOutput}else{$_.Output} } | Measure-Object -Sum).Sum)
        CallTotal = [Int64](($valid | Measure-Object CallTotal -Sum).Sum)
        TaskTotal = [Int64](($valid | Measure-Object TaskTotal -Sum).Sum)
        ContextPercent = [double](($valid | Measure-Object ContextPercent -Maximum).Maximum)
        ContextWindow = [Int64](($valid | Measure-Object ContextWindow -Sum).Sum)
        Model = $summary
        ActiveTasks = $valid.Count
        AllowanceTimestamp = if ($null -ne $rateSource -and $null -ne $rateSource.PSObject.Properties['AllowanceTimestamp']) { $rateSource.AllowanceTimestamp } else { $null }
        WeeklyRemainingPercent = if ($null -ne $rateSource -and $null -ne $rateSource.PSObject.Properties['WeeklyRemainingPercent']) { $rateSource.WeeklyRemainingPercent } else { $null }
        FiveHourRemainingPercent = if ($null -ne $rateSource -and $null -ne $rateSource.PSObject.Properties['FiveHourRemainingPercent']) { $rateSource.FiveHourRemainingPercent } else { $null }
        EstimatedCostUsd = if (@($valid | Where-Object { $null -eq $_.PSObject.Properties['EstimatedCostUsd'] -or $null -eq $_.EstimatedCostUsd }).Count -eq 0) { [double](($valid | Measure-Object EstimatedCostUsd -Sum).Sum) } else { $null }
    }
}

function Test-HudAccounting {
    param([Parameter(Mandatory = $true)]$Snapshot)
    (($Snapshot.Cached + $Snapshot.Uncached) -eq $Snapshot.Input) -and (($Snapshot.Input + $Snapshot.Output) -eq $Snapshot.CallTotal)
}

Export-ModuleMember -Function Get-HudPaths, Get-HudConfig, Save-HudConfig, New-HudTaskNumberPool, Get-HudTaskNumber, Add-HudReleasedTaskNumber, Get-HudLocale, Get-HudThemes, Get-HudPricingCatalog, Get-HudCostEstimate, Format-HudCost, Get-LatestHudSessionFile, Get-ActiveHudSessionFiles, Convert-HudRecord, Split-HudJsonLines, Get-LatestHudSnapshot, Get-LatestHudAllowanceSnapshot, Format-HudNumber, Get-HudMetrics, Merge-HudSnapshots, Test-HudAccounting
