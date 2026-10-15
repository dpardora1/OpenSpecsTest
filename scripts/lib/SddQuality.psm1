# Pure helpers shared by scripts/quality-gate.ps1 and scripts/traceability.ps1.
# No side effects (no network, no git, no writes): everything here is covered by tests/scripts/SddQuality.Tests.ps1.

function ConvertTo-ScenarioSlug {
    <# Scenario title -> trait slug: lowercase, no accents, non-alphanumerics -> '-' (skill spec-traceability). #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Title)
    $n = ($Title.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLowerInvariant()
    ($n -replace '[^a-z0-9]+', '-').Trim('-')
}

function Get-ChangeScenarios {
    <#
    Reads the scenarios a change must trace to tests: every "#### Scenario:" under "## ADDED Requirements" or
    "## MODIFIED Requirements" of each delta spec (specs/<capability>/spec.md). REMOVED/RENAMED sections need no tests.
    With -AllSections, returns every scenario (used for the current specs in openspec/specs, which have no delta headers).
    Returns objects { capability, title, slug, trait, file, line }.
    #>
    param([Parameter(Mandatory)][string]$SpecsDir, [switch]$AllSections)
    if (-not (Test-Path $SpecsDir)) { return @() }
    foreach ($spec in Get-ChildItem $SpecsDir -Recurse -Filter spec.md) {
        $capability = $spec.Directory.Name
        $section = ''
        $lineNo = 0
        foreach ($line in Get-Content $spec.FullName) {
            $lineNo++
            if ($line -match '^##\s+(ADDED|MODIFIED|REMOVED|RENAMED)\s+Requirements') { $section = $Matches[1]; continue }
            if ($line -match '^##\s+' -and $line -notmatch '^###') { $section = ''; continue }
            if ($line -match '^####\s+Scenario:\s*(.+?)\s*$' -and ($AllSections -or $section -in 'ADDED', 'MODIFIED')) {
                $title = $Matches[1]
                $slug = ConvertTo-ScenarioSlug $title
                [pscustomobject]@{ capability = $capability; title = $title; slug = $slug; trait = "$capability/$slug"; file = $spec.FullName; line = $lineNo }
            }
        }
    }
}

function Get-TrxScenarioResults {
    <#
    Parses TRX files (Microsoft.Testing.Platform --report-trx) and returns one object per (test, Scenario trait):
    { trait, test, outcome }. xUnit v3 traits are written as <Properties><Property><Key>Scenario</Key><Value>…</Value>.
    #>
    param([string[]]$TrxFiles)
    $ns = @{ t = 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010' }
    foreach ($file in $TrxFiles) {
        [xml]$trx = Get-Content $file -Raw
        $outcomes = @{}
        foreach ($r in (Select-Xml -Xml $trx -XPath '//t:UnitTestResult' -Namespace $ns)) { $outcomes[$r.Node.testId] = $r.Node.outcome }
        foreach ($u in (Select-Xml -Xml $trx -XPath '//t:UnitTest' -Namespace $ns)) {
            $node = $u.Node
            $props = Select-Xml -Xml $node -XPath './t:Properties/t:Property' -Namespace $ns
            foreach ($p in $props) {
                if ($p.Node.Key -eq 'Scenario') {
                    [pscustomobject]@{ trait = $p.Node.Value.Trim(); test = $node.name; outcome = ($outcomes[$node.id] ?? 'NotExecuted') }
                }
            }
        }
    }
}

function Get-SourceScenarioTraits {
    <# Fallback when no TRX exists: finds [Trait("Scenario", "<trait>")] in C# test sources. Returns { trait, file, line }. #>
    param([Parameter(Mandatory)][string]$TestsDir)
    if (-not (Test-Path $TestsDir)) { return @() }
    foreach ($hit in (Get-ChildItem $TestsDir -Recurse -Filter *.cs | Select-String -AllMatches -Pattern '\[\s*Trait\s*\(\s*"Scenario"\s*,\s*"([^"]+)"\s*\)|\bTrait\s*\(\s*"Scenario"\s*,\s*"([^"]+)"\s*\)')) {
        foreach ($m in $hit.Matches) { [pscustomobject]@{ trait = ($m.Groups[1].Value + $m.Groups[2].Value).Trim(); file = $hit.Path; line = $hit.LineNumber } }
    }
}

function Get-TraceabilityReport {
    <#
    Joins scenarios with test evidence. With TRX results, a scenario passes only if >= 1 test with its trait ran and
    every such test passed. Without TRX, it passes if a traced test exists in the sources (marked as not executed).
    Orphans: traits of the change's capabilities that match neither the change nor -KnownTraits (current specs).
    Returns { rows, failures, orphans }.
    #>
    param([object[]]$Scenarios, [object[]]$TrxResults, [object[]]$SourceTraits, [string[]]$KnownTraits, [switch]$HasTrx)
    $rows = foreach ($s in $Scenarios) {
        if ($HasTrx) {
            $tests = @($TrxResults | Where-Object trait -eq $s.trait)
            $failed = @($tests | Where-Object outcome -ne 'Passed')
            $status = if ($tests.Count -eq 0) { 'missing' } elseif ($failed.Count) { 'failed' } else { 'passed' }
            [pscustomobject]@{ trait = $s.trait; title = $s.title; status = $status; tests = @($tests | ForEach-Object { "$($_.test) ($($_.outcome))" }) }
        }
        else {
            $found = @($SourceTraits | Where-Object trait -eq $s.trait)
            [pscustomobject]@{ trait = $s.trait; title = $s.title; status = $(if ($found.Count) { 'not-executed' } else { 'missing' }); tests = @($found | ForEach-Object { "$([IO.Path]::GetFileName($_.file)):$($_.line)" }) }
        }
    }
    $rows = @($rows)
    $capabilities = @($Scenarios.capability | Select-Object -Unique)
    $known = @($Scenarios.trait) + @($KnownTraits)
    $evidence = if ($HasTrx) { $TrxResults } else { $SourceTraits }
    $orphans = @($evidence | Where-Object { ($_.trait -split '/')[0] -in $capabilities -and $_.trait -notin $known } | Select-Object -ExpandProperty trait -Unique)
    [pscustomobject]@{ rows = $rows; failures = @($rows | Where-Object { $_.status -in 'missing', 'failed' }).Count; orphans = $orphans }
}

function Test-CSharpHasExecutableCode {
    <#
    For changed files that appear in no coverage report. A file is "declarations only" (nothing to execute) ONLY when its
    WHOLE content is recognized as using directives, namespaces, attributes, interfaces/enums without bodies, delegates
    and positional records; any remaining content (statements, classes, initializers, unknown shapes) counts as
    executable (L-007).
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $true }
    $code = (Get-Content $Path -Raw) -replace '(?s)/\*.*?\*/', '' -replace '//[^\r\n]*', '' -replace '@?"(?:[^"\\]|\\.)*"', '""'
    # Any member body (methods, accessors, lambdas, default interface methods) is executable.
    if ($code -match '\)\s*(\{|=>)' -or $code -match '\b(get|set|init|add|remove)\s*(\{|=>)' -or $code -match '=>') { return $true }
    $braces = '\{(?>[^{}]+|\{(?<d>)|\}(?<-d>))*(?(d)(?!))\}'
    $modifiers = '(?:(?:public|internal|private|protected|partial|file|sealed|readonly)\s+)*'
    $rest = $code
    $rest = $rest -replace '\[[^\[\]]*(\[[^\[\]]*\][^\[\]]*)*\]', ' '                                   # attributes
    $rest = $rest -replace '(?m)^\s*(global\s+)?using\s+[^;()]+;', ' '                                   # using directives
    $rest = $rest -replace "$modifiers(interface|enum)\s+\w+(\s*<[^>]*>)?(\s*:\s*[^{]+)?\s*$braces", ' '  # interfaces / enums
    $rest = $rest -replace "${modifiers}record(\s+(class|struct))?\s+\w+(\s*<[^>]*>)?\s*\([^)]*\)(\s*:\s*[^;{]+)?\s*;", ' '  # positional records
    $rest = $rest -replace "${modifiers}delegate\s+[^;{]+;", ' '                                          # delegates
    $rest = $rest -replace '(?m)^\s*namespace\s+[\w.]+\s*;', ' '                                         # file-scoped namespace
    while ($rest -match 'namespace\s+[\w.]+\s*\{\s*\}') { $rest = $rest -replace 'namespace\s+[\w.]+\s*\{\s*\}', ' ' }  # emptied block namespaces
    $rest.Trim().Length -gt 0
}

function Get-ChangedFilesCoverage {
    <#
    Line coverage of the changed source files, merged across Cobertura reports (several test projects can cover the
    same file: a line counts as covered if any report hits it). Paths are compared as repo-relative, '/'-separated.
    Changed files that appear in no report are returned in `missing` (never silently ignored).
    Returns { files: [{ file, covered, valid, rate }], missing: [file], covered, valid, rate } (rate = $null when nothing measured).
    #>
    param([string[]]$CoberturaFiles, [string[]]$ChangedFiles, [Parameter(Mandatory)][string]$Root)
    $norm = { param($p) ($p -replace '\\', '/').TrimStart('./') }
    $rootNorm = (& $norm ([IO.Path]::GetFullPath($Root))).TrimEnd('/') + '/'
    $wanted = @{}
    foreach ($f in $ChangedFiles) { $wanted[(& $norm $f).ToLowerInvariant()] = $true }
    $lines = @{}   # file -> @{ lineNumber -> covered(bool) }
    foreach ($report in $CoberturaFiles) {
        [xml]$xml = Get-Content $report -Raw
        $sources = @($xml.coverage.sources.source | Where-Object { $_ })
        foreach ($class in $xml.SelectNodes('//class')) {
            $path = & $norm $class.filename
            if (-not [IO.Path]::IsPathRooted($class.filename) -and $sources.Count) { $path = & $norm (Join-Path $sources[0] $class.filename) }
            $rel = if ($path.ToLowerInvariant().StartsWith($rootNorm.ToLowerInvariant())) { $path.Substring($rootNorm.Length) } else { $path }
            if (-not $wanted.ContainsKey($rel.ToLowerInvariant())) { continue }
            if (-not $lines.ContainsKey($rel)) { $lines[$rel] = @{} }
            foreach ($l in $class.SelectNodes('./lines/line')) {
                $n = [int]$l.number
                $hit = [int]$l.hits -gt 0
                $lines[$rel][$n] = [bool]($lines[$rel][$n] -or $hit)
            }
        }
    }
    $files = foreach ($k in ($lines.Keys | Sort-Object)) {
        $valid = $lines[$k].Count
        $covered = @($lines[$k].Values | Where-Object { $_ }).Count
        [pscustomobject]@{ file = $k; covered = $covered; valid = $valid; rate = $(if ($valid) { [Math]::Round(100 * $covered / $valid, 1) } else { $null }) }
    }
    $files = @($files)
    $measured = @($files | ForEach-Object { $_.file.ToLowerInvariant() })
    $missing = @($ChangedFiles | ForEach-Object { & $norm $_ } | Where-Object { $_.ToLowerInvariant() -notin $measured } | Sort-Object -Unique)
    $totalValid = ($files | Measure-Object valid -Sum).Sum ?? 0
    $totalCovered = ($files | Measure-Object covered -Sum).Sum ?? 0
    [pscustomobject]@{ files = $files; missing = $missing; covered = $totalCovered; valid = $totalValid; rate = $(if ($totalValid) { [Math]::Round(100 * $totalCovered / $totalValid, 1) } else { $null }) }
}

Export-ModuleMember -Function ConvertTo-ScenarioSlug, Get-ChangeScenarios, Get-TrxScenarioResults, Get-SourceScenarioTraits, Get-TraceabilityReport, Test-CSharpHasExecutableCode, Get-ChangedFilesCoverage
