param(
    [ValidateRange(3,59)][int]$TaskCount = 12,
    [ValidateRange(0,5)][int]$ChurnCycles = 1,
    [string]$TestOutputRoot,
    [string]$ExistingMetricsRoot
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outputRoot = if ([string]::IsNullOrWhiteSpace($TestOutputRoot)) {
    Join-Path $root '.test-output\performance'
} else {
    $TestOutputRoot
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$results = New-Object System.Collections.Generic.List[object]
foreach ($mode in @('list','split')) {
    foreach ($hostMode in @('legacy','compiled')) {
        $metricsPath = if ([string]::IsNullOrWhiteSpace($ExistingMetricsRoot)) {
            Join-Path $outputRoot ($hostMode + '-' + $mode + '.json')
        } else {
            Join-Path ([IO.Path]::GetFullPath($ExistingMetricsRoot)) ($hostMode + '-' + $mode + '.json')
        }
        if ([string]::IsNullOrWhiteSpace($ExistingMetricsRoot)) {
            & (Join-Path $PSScriptRoot 'test-runtime-isolated.ps1') `
                -Mode $mode `
                -HostMode $hostMode `
                -TaskCount $TaskCount `
                -ChurnCycles $ChurnCycles `
                -TestOutputRoot $outputRoot `
                -MetricsPath $metricsPath
        }
        if (-not (Test-Path -LiteralPath $metricsPath)) { throw "Performance metrics are missing: $metricsPath" }
        $metric = Get-Content -Raw -Encoding UTF8 -LiteralPath $metricsPath | ConvertFrom-Json
        if ([string]$metric.host_mode -ne $hostMode -or [string]$metric.display_mode -ne $mode -or [int]$metric.task_count -ne $TaskCount -or [int]$metric.churn_cycles -ne $ChurnCycles) {
            throw "Performance metrics do not match the requested fixture: $metricsPath"
        }
        $results.Add($metric)
    }
}

$comparisons = foreach ($mode in @('list','split')) {
    $legacy = @($results | Where-Object { $_.host_mode -eq 'legacy' -and $_.display_mode -eq $mode })[0]
    $compiled = @($results | Where-Object { $_.host_mode -eq 'compiled' -and $_.display_mode -eq $mode })[0]
    [pscustomobject][ordered]@{
        display_mode = $mode
        legacy_private_mb = [Math]::Round($legacy.peak_private_memory_bytes / 1MB, 1)
        compiled_private_mb = [Math]::Round($compiled.peak_private_memory_bytes / 1MB, 1)
        private_ratio = [Math]::Round($compiled.peak_private_memory_bytes / [double]$legacy.peak_private_memory_bytes, 3)
        legacy_working_set_mb = [Math]::Round($legacy.peak_working_set_bytes / 1MB, 1)
        compiled_working_set_mb = [Math]::Round($compiled.peak_working_set_bytes / 1MB, 1)
        working_set_ratio = [Math]::Round($compiled.peak_working_set_bytes / [double]$legacy.peak_working_set_bytes, 3)
        legacy_cpu_ms = [Math]::Round([double]$legacy.final_cpu_ms, 1)
        compiled_cpu_ms = [Math]::Round([double]$compiled.final_cpu_ms, 1)
        cpu_ratio = [Math]::Round([double]$compiled.final_cpu_ms / [Math]::Max(1, [double]$legacy.final_cpu_ms), 3)
    }
}

$comparisonPath = Join-Path $outputRoot 'comparison.json'
$encoding = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($comparisonPath, (@($comparisons) | ConvertTo-Json -Depth 5), $encoding)

foreach ($comparison in $comparisons) {
    if ($comparison.private_ratio -gt 1.10) {
        throw "Compiled $($comparison.display_mode) peak private memory regressed by more than 10%. See $comparisonPath"
    }
    if ($comparison.working_set_ratio -gt 1.10) {
        throw "Compiled $($comparison.display_mode) peak working set regressed by more than 10%. See $comparisonPath"
    }
}
$aggregatePrivateRatio = ($comparisons | Measure-Object -Property private_ratio -Average).Average
$aggregateCpuRatio = ($comparisons | Measure-Object -Property cpu_ratio -Average).Average
if ($aggregatePrivateRatio -ge 0.95 -and $aggregateCpuRatio -ge 0.90) {
    throw "Compiled host did not demonstrate a material aggregate memory or CPU improvement. See $comparisonPath"
}

$comparisons | Format-Table -AutoSize
Write-Output ('Runtime performance comparison: OK (' + $comparisonPath + ')')
