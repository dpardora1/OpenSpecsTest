<#
.SYNOPSIS
    Quality gate of the repository: the same checks locally and in CI (skill dotnet-quality-gate).

.DESCRIPTION
    Steps (each one PASS / FAIL / SKIP), in this order:
      1. customizations  Agents, skills, prompts, instructions (frontmatter) and workflows (YAML, github-script, Actions
                         pinned by SHA): scripts/lib/validate-customizations.cjs (needs the OpenSpec CLI installed).
      2. powershell      Syntax of every script in scripts/ and tests/.
      3. openspec        openspec validate --all --strict.
      4. dotnet          Only when a solution (*.slnx / *.sln) exists at the root: restore, build -warnaserror,
                         format --verify-no-changes, test with coverage (Cobertura) and TRX (Microsoft.Testing.Platform).
      5. coverage        Line coverage of the C# files under src/ added, modified or renamed against -Base
                         (>= -CoverageThreshold %). Changed files with executable code but no coverage data FAIL.
      6. traceability    Only with -Change: every scenario of the change has a passing test (scripts/traceability.ps1).
                         Once a solution exists, the evidence must be TRX (executed tests).
      7. pester          Tests of the process scripts (tests/scripts, Pester >= 5.5), LAST and in a separate process.

    Integrity of the evidence (F5 review): code from the branch (builds, product tests, Pester tests) runs without
    credential variables; test results go to a fresh random folder created right before `dotnet test`; scenarios and
    changed files are read from the commit (HEAD), not from a working tree that tests could modify; Pester runs last.

    Writes a Markdown summary to stdout, to -OutFile and, in GitHub Actions, to the job summary.
    Exit code: 0 = no step failed · 1 = at least one step failed.

.EXAMPLE
    ./scripts/quality-gate.ps1
    ./scripts/quality-gate.ps1 -Change add-create-booking
    ./scripts/quality-gate.ps1 -Steps customizations,pester
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')][string]$Change,
    [ValidatePattern('^[A-Za-z0-9._/-]+$')][string]$Base = 'origin/main',
    [ValidateRange(0, 100)][int]$CoverageThreshold = 80,
    [ValidateSet('customizations', 'powershell', 'openspec', 'dotnet', 'coverage', 'traceability', 'pester')][string[]]$Steps,
    [string]$ResultsDir,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel 2>$null) ?? (Get-Location).Path
Set-Location $root
Import-Module (Join-Path $PSScriptRoot 'lib/SddQuality.psm1') -Force
if (-not $ResultsDir) { $ResultsDir = Join-Path ([IO.Path]::GetTempPath()) "sdd-quality-gate-$([Guid]::NewGuid().ToString('N').Substring(0, 8))" }
New-Item -ItemType Directory -Force $ResultsDir | Out-Null
$allSteps = 'customizations', 'powershell', 'openspec', 'dotnet', 'coverage', 'traceability', 'pester'
if (-not $Steps) { $Steps = $allSteps }
$headSha = git rev-parse HEAD

$results = [System.Collections.Generic.List[object]]::new()
$details = [System.Collections.Generic.List[string]]::new()

function Invoke-Step([string]$name, [scriptblock]$body) {
    if ($name -notin $Steps) { return }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $r = & $body } catch { $r = @{ status = 'FAIL'; detail = $_.Exception.Message } }
    $results.Add([pscustomobject]@{ step = $name; status = $r.status; detail = $r.detail; seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1) })
    Write-Host ("[{0}] {1} — {2}" -f $r.status, $name, $r.detail)
}

# Code from the branch must not see credentials (bot token, git auth header, Actions runtime tokens).
$credentialVars = @('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN', 'ACTIONS_RUNTIME_TOKEN', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN', 'ACTIONS_ID_TOKEN_REQUEST_URL') +
@(Get-ChildItem Env: | Where-Object Name -match '^GIT_CONFIG_(COUNT|KEY_\d+|VALUE_\d+)$' | ForEach-Object Name)
function Invoke-WithoutCredentials([scriptblock]$body) {
    $saved = @{}
    foreach ($v in $credentialVars) { $saved[$v] = [Environment]::GetEnvironmentVariable($v); Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
    try { & $body } finally { foreach ($k in $saved.Keys) { if ($null -ne $saved[$k]) { Set-Item "Env:$k" $saved[$k] } } }
}

function Invoke-Native([string]$label, [scriptblock]$command) {
    $output = Invoke-WithoutCredentials { & $command 2>&1 | Out-String }
    $script:LastNativeOutput = $output
    if ($LASTEXITCODE -ne 0) {
        $tail = ($output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 25) -join "`n"
        $details.Add("#### ❌ $label`n`n``````text`n$tail`n``````")
        return $false
    }
    return $true
}

# 1 ---------------------------------------------------------------------------------------------------
Invoke-Step 'customizations' {
    # Resolve the global npm root from a neutral folder: a .npmrc in the repository must not redirect it.
    Push-Location ([IO.Path]::GetTempPath())
    try { $npmRoot = (npm root -g 2>$null) } finally { Pop-Location }
    $env:NODE_PATH = @((Join-Path $npmRoot '@fission-ai/openspec/node_modules'), $npmRoot) -join [IO.Path]::PathSeparator
    if (-not (($env:NODE_PATH -split [IO.Path]::PathSeparator) | Where-Object { Test-Path (Join-Path $_ 'yaml') })) { return @{ status = 'FAIL'; detail = 'OpenSpec CLI not installed globally (npm install -g @fission-ai/openspec@1.14.2)' } }
    if (Invoke-Native 'customizations' { node (Join-Path $PSScriptRoot 'lib/validate-customizations.cjs') $root }) {
        @{ status = 'PASS'; detail = ($script:LastNativeOutput -split "`r?`n" | Where-Object { $_ -match '^customization files' } | Select-Object -Last 1) }
    }
    else { @{ status = 'FAIL'; detail = 'invalid customization files or workflows (see details)' } }
}

# 2 ---------------------------------------------------------------------------------------------------
Invoke-Step 'powershell' {
    $files = @(Get-ChildItem scripts, tests -Recurse -Filter *.ps*1 -ErrorAction SilentlyContinue)
    $errors = foreach ($f in $files) {
        $e = $null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e)
        foreach ($x in $e) { "$([IO.Path]::GetRelativePath($root, $f.FullName)):$($x.Extent.StartLineNumber) $($x.Message)" }
    }
    if ($errors) { $details.Add("#### ❌ powershell`n`n" + (($errors | ForEach-Object { "- $_" }) -join "`n")); @{ status = 'FAIL'; detail = "$(@($errors).Count) syntax error(s)" } }
    else { @{ status = 'PASS'; detail = "$($files.Count) script(s)" } }
}

# 3 ---------------------------------------------------------------------------------------------------
Invoke-Step 'openspec' {
    if (-not (Get-Command openspec -ErrorAction SilentlyContinue)) { return @{ status = 'FAIL'; detail = 'OpenSpec CLI not installed' } }
    if (Invoke-Native 'openspec' { openspec validate --all --strict --no-color }) { @{ status = 'PASS'; detail = (($script:LastNativeOutput -split "`r?`n" | Where-Object { $_ -match 'Totals|No items' } | Select-Object -Last 1) ?? 'valid').Trim() } }
    else { @{ status = 'FAIL'; detail = 'invalid specs or changes (see details)' } }
}

# 4 ---------------------------------------------------------------------------------------------------
$solution = Get-ChildItem $root -File | Where-Object Extension -in '.slnx', '.sln' | Select-Object -First 1
$testResults = $null
$dotnetRan = $false
Invoke-Step 'dotnet' {
    if (-not $solution) { return @{ status = 'SKIP'; detail = 'no .NET solution yet (created by change C0)' } }
    foreach ($s in @(
            @{ label = 'dotnet restore'; cmd = { dotnet restore $solution.FullName } },
            @{ label = 'dotnet build'; cmd = { dotnet build $solution.FullName --no-restore -warnaserror } },
            @{ label = 'dotnet format'; cmd = { dotnet format $solution.FullName --verify-no-changes --no-restore } })) {
        if (-not (Invoke-Native $s.label $s.cmd)) { return @{ status = 'FAIL'; detail = "$($s.label) failed (see details)" } }
    }
    # Fresh, unpredictable results folder created right before running the tests: no pre-planted TRX/Cobertura counts.
    $script:testResults = Join-Path $ResultsDir "TestResults-$([Guid]::NewGuid().ToString('N'))"
    if (-not (Invoke-Native 'dotnet test' { dotnet test --solution $solution.FullName --no-build --results-directory $script:testResults --coverage --coverage-output-format cobertura --report-trx })) {
        return @{ status = 'FAIL'; detail = 'dotnet test failed (see details)' }
    }
    $script:dotnetRan = $true
    $summary = ($script:LastNativeOutput -split "`r?`n" | Where-Object { $_ -match '^\s*(total|correcto|succeeded|passed|error|failed)\s*:' }) -join ' · '
    @{ status = 'PASS'; detail = "build without warnings, format OK, tests: $($summary -replace '\s+', ' ')" }
}

# 5 ---------------------------------------------------------------------------------------------------
Invoke-Step 'coverage' {
    if (-not $dotnetRan) { return @{ status = 'SKIP'; detail = 'requires the dotnet step' } }
    $changed = @(git diff --name-only --diff-filter=AMR "$Base...$headSha" -- ':(icase)src/*.cs' ':(icase)src/**/*.cs' 2>$null | Where-Object { $_ -notmatch '/Migrations/|\.Designer\.cs$|\.g\.cs$' })
    if ($changed.Count -eq 0) { return @{ status = 'SKIP'; detail = "no C# source changes against $Base" } }
    $reports = @(Get-ChildItem $testResults -Recurse -Filter *.cobertura.xml -ErrorAction SilentlyContinue | ForEach-Object FullName)
    if (-not $reports) { return @{ status = 'FAIL'; detail = 'no Cobertura report produced (Microsoft.Testing.Extensions.CodeCoverage missing?)' } }
    $cov = Get-ChangedFilesCoverage -CoberturaFiles $reports -ChangedFiles $changed -Root $root
    # Changed files absent from every report fail unless the COMMITTED content only has declarations (nothing to execute).
    $snapshot = Join-Path $ResultsDir 'head-snapshot'
    $uncovered = @($cov.missing | Where-Object {
            $copy = Join-Path $snapshot $_
            New-Item -ItemType Directory -Force (Split-Path $copy) | Out-Null
            git show "${headSha}:$_" 2>$null | Set-Content $copy -Encoding utf8
            Test-CSharpHasExecutableCode $copy
        })
    $declOnly = @($cov.missing | Where-Object { $_ -notin $uncovered })
    $table = @('| Fichero | Líneas cubiertas | % |', '|---|---|---|') +
    @($cov.files | ForEach-Object { "| ``$($_.file)`` | $($_.covered)/$($_.valid) | $($_.rate) |" }) +
    @($uncovered | ForEach-Object { "| ``$_`` | ❌ sin datos de cobertura (ningún test lo ejecuta) | 0 |" }) +
    @($declOnly | ForEach-Object { "| ``$_`` | solo declaraciones (nada que ejecutar) | — |" })
    $details.Add("#### Cobertura de ficheros cambiados`n`n" + ($table -join "`n"))
    if ($uncovered.Count) { return @{ status = 'FAIL'; detail = "$($uncovered.Count) changed file(s) with executable code but no coverage data" } }
    if ($null -eq $cov.rate) { return @{ status = 'SKIP'; detail = 'changed files only contain declarations' } }
    if ($cov.rate -lt $CoverageThreshold) { @{ status = 'FAIL'; detail = "$($cov.rate)% < $CoverageThreshold% on $($cov.files.Count) changed file(s)" } }
    else { @{ status = 'PASS'; detail = "$($cov.rate)% >= $CoverageThreshold% on $($cov.files.Count) changed file(s)" } }
}

# 6 ---------------------------------------------------------------------------------------------------
Invoke-Step 'traceability' {
    if (-not $Change) { return @{ status = 'SKIP'; detail = 'no -Change given (only implementation PRs trace scenarios)' } }
    $traceArgs = @{ Change = $Change; Root = $root }
    if ($solution) {
        # Scenarios come from the commit, not from a working tree the tests could have modified; evidence must be TRX.
        $specsRoot = Join-Path $ResultsDir 'head-openspec'
        New-Item -ItemType Directory -Force $specsRoot | Out-Null
        git archive -o "$specsRoot.tar" $headSha openspec 2>$null
        if ($LASTEXITCODE -ne 0) { return @{ status = 'FAIL'; detail = 'openspec/ not found in the commit' } }
        tar -xf "$specsRoot.tar" -C $specsRoot
        $traceArgs.Root = $specsRoot
        $traceArgs.ResultsDir = $testResults
        $traceArgs.RequireTrx = $true
    }
    $out = & (Join-Path $PSScriptRoot 'traceability.ps1') @traceArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $details.Add($out.Trim())
    switch ($code) {
        0 { @{ status = 'PASS'; detail = "all scenarios of $Change traced by passing tests" } }
        3 { @{ status = 'SKIP'; detail = 'traits found in source only, tests not executed (no .NET solution)' } }
        default { @{ status = 'FAIL'; detail = "scenarios of $Change without passing tests or without TRX evidence (see details)" } }
    }
}

# 7 ---------------------------------------------------------------------------------------------------
Invoke-Step 'pester' {
    if (-not (Test-Path 'tests/scripts')) { return @{ status = 'SKIP'; detail = 'no tests/scripts' } }
    if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge ([version]'5.5.0'))) { return @{ status = 'FAIL'; detail = 'Pester >= 5.5 not installed (Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser)' } }
    # Separate process without credentials, after every other step: branch tests cannot alter earlier evidence.
    $runner = Join-Path $ResultsDir 'run-pester.ps1'
    @'
param([string]$Path, [string]$Out)
Import-Module Pester -MinimumVersion 5.5.0
$c = New-PesterConfiguration
$c.Run.Path = $Path; $c.Run.PassThru = $true; $c.Output.Verbosity = 'None'
$c.TestResult.Enabled = $true; $c.TestResult.OutputPath = $Out
$r = Invoke-Pester -Configuration $c
'SDD-PESTER-RESULT ' + ([pscustomobject]@{
        result = "$($r.Result)"; passed = $r.PassedCount; failed = $r.FailedCount; total = $r.TotalCount
        failedContainers = $r.FailedContainersCount; failedBlocks = $r.FailedBlocksCount
        failures = @(@($r.Failed | ForEach-Object { "$($_.ExpandedPath): $($_.ErrorRecord.Exception.Message)" }) + @($r.Containers | Where-Object Result -eq 'Failed' | ForEach-Object { "container $($_.Item): $($_.ErrorRecord.Exception.Message)" }))
    } | ConvertTo-Json -Compress)
'@ | Set-Content $runner -Encoding utf8
    $out = Invoke-WithoutCredentials { pwsh -NoProfile -File $runner -Path (Join-Path $root 'tests/scripts') -Out (Join-Path $ResultsDir 'pester.xml') 2>&1 | Out-String }
    $line = ($out -split "`r?`n" | Where-Object { $_ -like 'SDD-PESTER-RESULT *' } | Select-Object -Last 1)
    if (-not $line) { $details.Add("#### ❌ pester`n`n``````text`n$(($out -split "`r?`n" | Select-Object -Last 25) -join "`n")`n``````"); return @{ status = 'FAIL'; detail = 'Pester did not report results (see details)' } }
    $r = $line.Substring('SDD-PESTER-RESULT '.Length) | ConvertFrom-Json
    # L-007: discovery/container errors, failed blocks or a run without tests are failures, never a pass.
    if ($r.result -ne 'Passed' -or $r.failed -gt 0 -or $r.failedContainers -gt 0 -or $r.failedBlocks -gt 0 -or $r.total -eq 0) {
        $details.Add("#### ❌ pester`n`n" + ((@($r.failures) + @("result=$($r.result) failed=$($r.failed) failedContainers=$($r.failedContainers) failedBlocks=$($r.failedBlocks) total=$($r.total)") | ForEach-Object { "- $_" }) -join "`n"))
        @{ status = 'FAIL'; detail = "result $($r.result): $($r.failed) failed test(s), $($r.failedContainers) failed container(s), $($r.failedBlocks) failed block(s), $($r.total) test(s)" }
    }
    else { @{ status = 'PASS'; detail = "$($r.passed)/$($r.total) passed" } }
}

# Summary ---------------------------------------------------------------------------------------------
$icon = @{ PASS = '✅'; FAIL = '❌'; SKIP = '⏭️' }
$failed = @($results | Where-Object status -eq 'FAIL')
$md = [System.Collections.Generic.List[string]]::new()
$md.Add("## 🚦 Quality gate · $(if ($failed) { '❌ FALLA' } else { '✅ OK' })")
$md.Add('')
$changeNote = if ($Change) { ' · change `' + $Change + '`' } else { '' }
$md.Add('Commit `' + (git rev-parse --short HEAD 2>$null) + '` · base `' + $Base + '`' + $changeNote)
$md.Add('')
$md.Add('| Paso | Estado | Detalle | s |')
$md.Add('|---|---|---|---|')
foreach ($r in $results) { $md.Add("| $($r.step) | $($icon[$r.status]) $($r.status) | $($r.detail -replace '\|', '\|') | $($r.seconds) |") }
if ($details.Count) { $md.Add(''); $md.Add('<details><summary>Detalles</summary>'); $md.Add(''); $details | ForEach-Object { $md.Add($_); $md.Add('') }; $md.Add('</details>') }
$summary = $md -join "`n"
if ($OutFile) { $summary | Set-Content $OutFile -Encoding utf8 }
if ($env:GITHUB_STEP_SUMMARY) { $summary | Add-Content $env:GITHUB_STEP_SUMMARY -Encoding utf8 }
Write-Output $summary
if ($failed) { exit 1 }
exit 0
