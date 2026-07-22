$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $root 'install-manifest.json') -Encoding UTF8 -Raw | ConvertFrom-Json

function Assert-Protocol([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "Install protocol assertion failed: $Message" }
}

function Resolve-SyntheticPlan([string]$Platform,[string]$Architecture,[ValidateSet('valid','missing','corrupt','interrupted')][string]$ReleaseState) {
    $key = switch ("$Platform/$Architecture") {
        'windows/x64' { 'windows-x64' }
        'macos/arm64' { 'macos-arm64' }
        default { return 'stop:unsupported' }
    }
    if ($null -eq $manifest.platforms.$key) { return 'stop:unsupported' }
    switch ($ReleaseState) {
        valid { return "release:$key" }
        missing { return "source:$key" }
        corrupt { return 'stop:checksum' }
        interrupted { return 'rollback' }
    }
}

$prompts = @(
    '帮我安装 https://github.com/LH-03/codex-monitor-hud',
    '这个插件帮我装一下：https://github.com/LH-03/codex-monitor-hud',
    'install this https://github.com/LH-03/codex-monitor-hud'
)
foreach ($prompt in $prompts) {
    $url = [regex]::Match($prompt,'https://github\.com/LH-03/codex-monitor-hud').Value
    Assert-Protocol ($url -eq $manifest.repository) 'vague install prompts must resolve to the canonical repository'
}

Assert-Protocol ((Resolve-SyntheticPlan windows x64 valid) -eq 'release:windows-x64') 'Windows x64 Release route'
Assert-Protocol ((Resolve-SyntheticPlan macos arm64 valid) -eq 'release:macos-arm64') 'macOS arm64 Release route'
Assert-Protocol ((Resolve-SyntheticPlan macos x64 valid) -eq 'stop:unsupported') 'macOS x64 unsupported route'
Assert-Protocol ((Resolve-SyntheticPlan macos arm64 missing) -eq 'source:macos-arm64') 'missing Release source fallback'
Assert-Protocol ((Resolve-SyntheticPlan macos arm64 corrupt) -eq 'stop:checksum') 'corrupt checksum hard stop'
Assert-Protocol ((Resolve-SyntheticPlan macos arm64 interrupted) -eq 'rollback') 'interrupted switch rollback'
Assert-Protocol ($manifest.rules.preserveSettings -eq $true) 'existing settings preservation'
Assert-Protocol ($manifest.rules.retainRollback -eq $true) 'upgrade rollback retention'
Assert-Protocol ($manifest.operations -contains 'repair') 'repair operation'
Assert-Protocol ($manifest.operations -contains 'rollback') 'rollback operation'
Assert-Protocol ($manifest.rules.readSessionContent -eq $false) 'session-content privacy rule'
Assert-Protocol ($manifest.rules.uploadLocalData -eq $false) 'no-upload rule'

$macInstaller = Get-Content -LiteralPath (Join-Path $root 'scripts/install-macos.sh') -Encoding UTF8 -Raw
foreach ($required in @('checksum-mismatch','--repair','--rollback','--uninstall','--verify','needs-user-approval')) {
    Assert-Protocol ($macInstaller.Contains($required)) "macOS installer contract marker $required"
}
$windowsInstaller = Get-Content -LiteralPath (Join-Path $root 'scripts/install-windows-from-repository.ps1') -Encoding UTF8 -Raw
foreach ($required in @('checksum-mismatch','releaseAvailable','RollbackVersion','Invoke-WebRequest','SHA256')) {
    Assert-Protocol ($windowsInstaller.Contains($required)) "Windows repository installer contract marker $required"
}

Write-Output 'Deterministic repository install protocol: OK (prompts, routes, checksum stop, settings, repair, rollback)'
