Set-StrictMode -Version Latest

function Get-HudPaths {
    param([Parameter(Mandatory = $true)][string]$PluginRoot)
    $stateRoot = Join-Path $env:LOCALAPPDATA 'CodexTokenHUD'
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
    $themeRoot = Join-Path $PluginRoot 'themes'
    if (-not (Test-Path -LiteralPath $themeRoot)) { return @() }
    $themes = @()
    foreach ($file in Get-ChildItem -LiteralPath $themeRoot -File -Filter '*.json' -ErrorAction SilentlyContinue) {
        try {
            $theme = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace([string]$theme.id) -or $null -eq $theme.settings) { continue }
            $theme | Add-Member -NotePropertyName SourcePath -NotePropertyValue $file.FullName -Force
            $themes += $theme
        } catch { }
    }
    return @($themes | Sort-Object @{ Expression = { if ($null -ne $_.order) { [int]$_.order } else { 999 } } }, id)
}

function Get-HudConfig {
    param([Parameter(Mandatory = $true)]$Paths)
    $default = Get-Content -Raw -Encoding UTF8 -LiteralPath $Paths.DefaultConfigPath | ConvertFrom-Json
    if (-not (Test-Path -LiteralPath $Paths.ConfigPath)) { return $default }
    try {
        $saved = Get-Content -Raw -Encoding UTF8 -LiteralPath $Paths.ConfigPath | ConvertFrom-Json
        return Merge-HudConfig $default $saved
    } catch {
        return $default
    }
}

function Save-HudConfig {
    param([Parameter(Mandatory = $true)]$Paths, [Parameter(Mandatory = $true)]$Config)
    New-Item -ItemType Directory -Force -Path $Paths.StateRoot | Out-Null
    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Paths.ConfigPath -Encoding UTF8
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
    $files = @()
    foreach ($date in @((Get-Date), (Get-Date).AddDays(-1))) {
        $folder = Join-Path $SessionsRoot $date.ToString('yyyy\MM\dd')
        if (Test-Path -LiteralPath $folder) {
            $files += Get-ChildItem -LiteralPath $folder -File -Filter '*.jsonl' -ErrorAction SilentlyContinue
        }
    }
    if ($files.Count -eq 0) {
        $files = Get-ChildItem -LiteralPath $SessionsRoot -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue
    }
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
    foreach ($date in @((Get-Date), (Get-Date).AddDays(-1))) {
        $folder = Join-Path $SessionsRoot $date.ToString('yyyy\MM\dd')
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $folder -File -Filter '*.jsonl' -ErrorAction SilentlyContinue) {
            if ($file.LastWriteTimeUtc -ge $cutoff) { [void]$files.Add($file) }
        }
    }
    if ($files.Count -eq 0) {
        $latest = Get-LatestHudSessionFile $SessionsRoot
        if ($null -ne $latest) { return @($latest) }
        return @()
    }
    return @($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First ([Math]::Max(1, $MaximumFiles)))
}

function Convert-HudRecord {
    param([Parameter(Mandatory = $true)][string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    try { $record = $Line | ConvertFrom-Json } catch { return $null }
    if ($record.type -eq 'turn_context') {
        return [pscustomobject]@{
            Kind = 'context'
            Model = [string]$record.payload.model
        }
    }
    if ($record.type -ne 'event_msg' -or $record.payload.type -ne 'token_count') { return $null }
    $last = $record.payload.info.last_token_usage
    $total = $record.payload.info.total_token_usage
    if ($null -eq $last -or $null -eq $total) { return $null }
    $input = [Int64]$last.input_tokens
    $cached = [Int64]$last.cached_input_tokens
    $output = [Int64]$last.output_tokens
    if ($input -eq 0 -and $output -eq 0) { return $null }
    $window = [Int64]$record.payload.info.model_context_window
    $contextPercent = if ($window -gt 0) { [Math]::Min(100, [Math]::Round(($input * 100.0) / $window, 1)) } else { 0 }
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
    [pscustomobject]@{
        Kind = 'usage'
        Timestamp = [DateTimeOffset]::Parse($record.timestamp).ToLocalTime()
        Input = $input
        Cached = $cached
        Uncached = [Math]::Max([Int64]0, $input - $cached)
        Output = $output
        Reasoning = [Int64]$last.reasoning_output_tokens
        CallTotal = $input + $output
        TaskTotal = [Int64]$total.total_tokens
        ContextPercent = $contextPercent
        ContextWindow = $window
        Model = ''
        WeeklyRemainingPercent = $weeklyRemaining
        FiveHourRemainingPercent = $fiveHourRemaining
    }
}

function Get-LatestHudSnapshot {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File, [int]$Tail = 2000)
    $lines = @(Get-Content -LiteralPath $File.FullName -Tail $Tail -ErrorAction Stop)
    $usage = $null
    $model = ''
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $item = Convert-HudRecord $lines[$i]
        if ($null -eq $item) { continue }
        if ($item.Kind -eq 'usage' -and $null -eq $usage) { $usage = $item }
        if ($item.Kind -eq 'context' -and [string]::IsNullOrWhiteSpace($model)) { $model = $item.Model }
        if ($null -ne $usage -and -not [string]::IsNullOrWhiteSpace($model)) { break }
    }
    if ($null -ne $usage) { $usage.Model = $model }
    return $usage
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
    $rateSource = $valid | Where-Object {
        ($null -ne $_.PSObject.Properties['WeeklyRemainingPercent'] -and $null -ne $_.WeeklyRemainingPercent) -or
        ($null -ne $_.PSObject.Properties['FiveHourRemainingPercent'] -and $null -ne $_.FiveHourRemainingPercent)
    } | Sort-Object Timestamp -Descending | Select-Object -First 1
    [pscustomobject]@{
        Timestamp = ($valid | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
        Input = [Int64](($valid | Measure-Object Input -Sum).Sum)
        Cached = [Int64](($valid | Measure-Object Cached -Sum).Sum)
        Uncached = [Int64](($valid | Measure-Object Uncached -Sum).Sum)
        Output = [Int64](($valid | Measure-Object Output -Sum).Sum)
        Reasoning = [Int64](($valid | Measure-Object Reasoning -Sum).Sum)
        CallTotal = [Int64](($valid | Measure-Object CallTotal -Sum).Sum)
        TaskTotal = [Int64](($valid | Measure-Object TaskTotal -Sum).Sum)
        ContextPercent = [double](($valid | Measure-Object ContextPercent -Maximum).Maximum)
        ContextWindow = [Int64](($valid | Measure-Object ContextWindow -Sum).Sum)
        Model = $summary
        ActiveTasks = $valid.Count
        WeeklyRemainingPercent = if ($null -ne $rateSource -and $null -ne $rateSource.PSObject.Properties['WeeklyRemainingPercent']) { $rateSource.WeeklyRemainingPercent } else { $null }
        FiveHourRemainingPercent = if ($null -ne $rateSource -and $null -ne $rateSource.PSObject.Properties['FiveHourRemainingPercent']) { $rateSource.FiveHourRemainingPercent } else { $null }
    }
}

function Test-HudAccounting {
    param([Parameter(Mandatory = $true)]$Snapshot)
    (($Snapshot.Cached + $Snapshot.Uncached) -eq $Snapshot.Input) -and (($Snapshot.Input + $Snapshot.Output) -eq $Snapshot.CallTotal)
}

Export-ModuleMember -Function Get-HudPaths, Get-HudConfig, Save-HudConfig, Get-HudLocale, Get-HudThemes, Get-LatestHudSessionFile, Get-ActiveHudSessionFiles, Convert-HudRecord, Get-LatestHudSnapshot, Format-HudNumber, Get-HudMetrics, Merge-HudSnapshots, Test-HudAccounting
