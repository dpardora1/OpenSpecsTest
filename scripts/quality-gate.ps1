<#
.SYNOPSIS
    Quality gate of the repository: the same checks locally and in CI (skill dotnet-quality-gate).

.DESCRIPTION
    Steps (each one PASS / FAIL / SKIP):
      1. customizations  Agents, skills, prompts, instructions (frontmatter) and workflows (YAML, github-script, Actions
                         pinned by SHA): scripts/lib/validate-customizations.cjs (needs the OpenSpec CLI installed).
      2. powershell      Syntax of every script in scripts/ and tests/.
      3. pester          Tests of the process scripts (tests/scripts, Pester >= 5.5).
      4. openspec        openspec validate --all --strict.
      5. dotnet          Only when a solution (*.slnx / *.sln) exists at the root: restore, build -warnaserror,
                         format --verify-no-changes, test with coverage (Cobertura) and TRX (Microsoft.Testing.Platform).
      6. coverage        Line coverage of the C# files under src/ changed against -Base (>= -CoverageThreshold %).
      7. traceability    Only with -Change: every scenario of the change has a passing test (scripts/traceability.ps1).

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
    [ValidateSet('customizations', 'powershell', 'pester', 'openspec', 'dotnet', 'coverage', 'traceability')][string[]]$Steps,
    [string]$ResultsDir,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$root = (git rev-parse --show-toplevel 2>$null) ?? (Get-Location).Path
Set-Location $root
Import-Module (Join-Path $PSScriptRoot 'lib/SddQuality.psm1') -Force
if (-not $ResultsDir) { $ResultsDir = Join-Path ([IO.Path]::GetTempPath()) "sdd-quality-gate-$([Guid]::NewGuid().ToString('N').Substring(0, 8))" }
New-Item -ItemType Directory -Force $ResultsDir | Out-Null
$allSteps = 'customizations', 'powershell', 'pester', 'openspec', 'dotnet', 'coverage', 'traceability'
if (-not $Steps) { $Steps = $allSteps }

$results = [System.Collections.Generic.List[object]]::new()
$details = [System.Collections.Generic.List[string]]::new()

function Invoke-Step([string]$name, [scriptblock]$body) {
    if ($name -notin $Steps) { return }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try { $r = & $body } catch { $r = @{ status = 'FAIL'; detail = $_.Exception.Message } }
    $results.Add([pscustomobject]@{ step = $name; status = $r.status; detail = $r.detail; seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1) })
    Write-Host ("[{0}] {1} — {2}" -f $r.status, $name, $r.detail)
}

function Invoke-Native([string]$label, [scriptblock]$command) {
    $output = & $command 2>&1 | Out-String
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
    $npmRoot = (npm root -g 2>$null)
    $env:NODE_PATH = Join-Path $npmRoot '@fission-ai/openspec/node_modules'
    if (-not (Test-Path (Join-Path $env:NODE_PATH 'yaml'))) { return @{ status = 'FAIL'; detail = 'OpenSpec CLI not installed globally (npm install -g @fission-ai/openspec@1.14.2)' } }
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
Invoke-Step 'pester' {
    if (-not (Test-Path 'tests/scripts')) { return @{ status = 'SKIP'; detail = 'no tests/scripts' } }
    $pester = Get-Module -ListAvailable Pester | Where-Object Version -ge ([version]'5.5.0') | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester) { return @{ status = 'FAIL'; detail = 'Pester >= 5.5 not installed (Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser)' } }
    Import-Module $pester -Force
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = 'tests/scripts'; $cfg.Run.PassThru = $true; $cfg.Output.Verbosity = 'None'
    $cfg.TestResult.Enabled = $true; $cfg.TestResult.OutputPath = Join-Path $ResultsDir 'pester.xml'
    $r = Invoke-Pester -Configuration $cfg
    if ($r.FailedCount -gt 0) {
        $details.Add("#### ❌ pester`n`n" + (($r.Failed | ForEach-Object { "- $($_.ExpandedPath): $($_.ErrorRecord.Exception.Message)" }) -join "`n"))
        @{ status = 'FAIL'; detail = "$($r.FailedCount)/$($r.TotalCount) failed" }
    }
    else { @{ status = 'PASS'; detail = "$($r.PassedCount)/$($r.TotalCount) passed" } }
}

# 4 ---------------------------------------------------------------------------------------------------
Invoke-Step 'openspec' {
    if (-not (Get-Command openspec -ErrorAction SilentlyContinue)) { return @{ status = 'FAIL'; detail = 'OpenSpec CLI not installed' } }
    if (Invoke-Native 'openspec' { openspec validate --all --strict --no-color }) { @{ status = 'PASS'; detail = (($script:LastNativeOutput -split "`r?`n" | Where-Object { $_ -match 'Totals|No items' } | Select-Object -Last 1) ?? 'valid').Trim() } }
    else { @{ status = 'FAIL'; detail = 'invalid specs or changes (see details)' } }
}

# 5 ---------------------------------------------------------------------------------------------------
$solution = Get-ChildItem $root -File | Where-Object Extension -in '.slnx', '.sln' | Select-Object -First 1
$testResults = Join-Path $ResultsDir 'TestResults'
$dotnetRan = $false
Invoke-Step 'dotnet' {
    if (-not $solution) { return @{ status = 'SKIP'; detail = 'no .NET solution yet (created by change C0)' } }
    foreach ($s in @(
            @{ label = 'dotnet restore'; cmd = { dotnet restore $solution.FullName } },
            @{ label = 'dotnet build'; cmd = { dotnet build $solution.FullName --no-restore -warnaserror } },
            @{ label = 'dotnet format'; cmd = { dotnet format $solution.FullName --verify-no-changes --no-restore } },
            @{ label = 'dotnet test'; cmd = { dotnet test --solution $solution.FullName --no-build --results-directory $testResults --coverage --coverage-output-format cobertura --report-trx } })) {
        if (-not (Invoke-Native $s.label $s.cmd)) { return @{ status = 'FAIL'; detail = "$($s.label) failed (see details)" } }
    }
    $script:dotnetRan = $true
    $summary = ($script:LastNativeOutput -split "`r?`n" | Where-Object { $_ -match '^\s*(total|correcto|succeeded|passed|error|failed)\s*:' }) -join ' · '
    @{ status = 'PASS'; detail = "build without warnings, format OK, tests: $($summary -replace '\s+', ' ')" }
}

# 6 ---------------------------------------------------------------------------------------------------
Invoke-Step 'coverage' {
    if (-not $dotnetRan) { return @{ status = 'SKIP'; detail = 'requires the dotnet step' } }
    $changed = @(git diff --name-only --diff-filter=AM "$Base...HEAD" -- 'src/*.cs' 'src/**/*.cs' 2>$null | Where-Object { $_ -notmatch '/Migrations/|\.Designer\.cs$|\.g\.cs$' })
    if ($changed.Count -eq 0) { return @{ status = 'SKIP'; detail = "no C# source changes against $Base" } }
    $reports = @(Get-ChildItem $testResults -Recurse -Filter *.cobertura.xml -ErrorAction SilentlyContinue | ForEach-Object FullName)
    if (-not $reports) { return @{ status = 'FAIL'; detail = 'no Cobertura report produced (Microsoft.Testing.Extensions.CodeCoverage missing?)' } }
    $cov = Get-ChangedFilesCoverage -CoberturaFiles $reports -ChangedFiles $changed -Root $root
    $table = @('| Fichero | Líneas cubiertas | % |', '|---|---|---|') + @($cov.files | ForEach-Object { "| ``$($_.file)`` | $($_.covered)/$($_.valid) | $($_.rate) |" })
    $details.Add("#### Cobertura de ficheros cambiados`n`n" + ($table -join "`n"))
    if ($null -eq $cov.rate) { return @{ status = 'SKIP'; detail = 'changed files have no coverable lines' } }
    if ($cov.rate -lt $CoverageThreshold) { @{ status = 'FAIL'; detail = "$($cov.rate)% < $CoverageThreshold% on $($cov.files.Count) changed file(s)" } }
    else { @{ status = 'PASS'; detail = "$($cov.rate)% >= $CoverageThreshold% on $($cov.files.Count) changed file(s)" } }
}

# 7 ---------------------------------------------------------------------------------------------------
Invoke-Step 'traceability' {
    if (-not $Change) { return @{ status = 'SKIP'; detail = 'no -Change given' } }
    $out = & (Join-Path $PSScriptRoot 'traceability.ps1') -Change $Change -ResultsDir $(if ($dotnetRan) { $testResults }) -Root $root 2>&1 | Out-String
    $ok = $LASTEXITCODE -eq 0
    $details.Add($out.Trim())
    if ($ok) { @{ status = 'PASS'; detail = "all scenarios of $Change traced$(if (-not $dotnetRan) { ' (source only, not executed)' })" } }
    else { @{ status = 'FAIL'; detail = "scenarios without passing tests in $Change (see details)" } }
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
