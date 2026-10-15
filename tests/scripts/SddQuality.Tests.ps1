#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Tests for scripts/lib/SddQuality.psm1 and scripts/traceability.ps1 (fixtures only, no dotnet or git needed).
#   Invoke-Pester ./tests/scripts

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../scripts/lib/SddQuality.psm1') -Force
    $script:Traceability = Join-Path $PSScriptRoot '../../scripts/traceability.ps1'

    function New-Trx([string]$path, [object[]]$tests) {
        # $tests: @{ name; outcome; traits = @('cap/slug', ...) }
        New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
        $defs = foreach ($t in $tests) {
            $props = ($t.traits | ForEach-Object { "<Property><Key>Scenario</Key><Value>$_</Value></Property>" }) -join ''
            "<UnitTest name=`"$($t.name)`" id=`"$($t.name)-id`"><Properties>$props</Properties><TestMethod className=`"X`" name=`"$($t.name)`" /></UnitTest>"
        }
        $results = foreach ($t in $tests) { if ($t.outcome) { "<UnitTestResult testId=`"$($t.name)-id`" testName=`"$($t.name)`" outcome=`"$($t.outcome)`" />" } }
        @"
<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">
  <Results>$($results -join '')</Results>
  <TestDefinitions>$($defs -join '')</TestDefinitions>
</TestRun>
"@ | Set-Content $path -Encoding utf8
    }

    function New-Cobertura([string]$path, [string]$filename, [hashtable]$hits) {
        $lines = ($hits.GetEnumerator() | Sort-Object Name | ForEach-Object { "<line number=`"$($_.Name)`" hits=`"$($_.Value)`" />" }) -join ''
        "<?xml version=`"1.0`"?><coverage><packages><package><classes><class name=`"C`" filename=`"$filename`"><lines>$lines</lines></class></classes></package></packages></coverage>" |
            Set-Content $path -Encoding utf8
    }

    function New-SpecFile([string]$path, [string]$content) {
        New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
        $content | Set-Content $path -Encoding utf8
    }

    $script:DeltaSpec = @'
## ADDED Requirements

### Requirement: Reservar
The system SHALL book.

#### Scenario: Reserva de una franja libre
- **WHEN** a
- **THEN** b

## MODIFIED Requirements

### Requirement: Cancelar
#### Scenario: Cancelación con 24 h de antelación
- **WHEN** a
- **THEN** b

## REMOVED Requirements

### Requirement: Antigua
#### Scenario: Escenario eliminado
- **WHEN** a
- **THEN** b
'@
}

Describe 'ConvertTo-ScenarioSlug' {
    It 'lowercases, strips accents and joins words with dashes' {
        ConvertTo-ScenarioSlug 'Reserva solapada rechazada' | Should -Be 'reserva-solapada-rechazada'
        ConvertTo-ScenarioSlug 'Cancelación ¿gratis? (24 h)' | Should -Be 'cancelacion-gratis-24-h'
        ConvertTo-ScenarioSlug '  Ñandú: más allá  ' | Should -Be 'nandu-mas-alla'
    }
}

Describe 'Get-ChangeScenarios' {
    It 'returns ADDED and MODIFIED scenarios and ignores REMOVED ones' {
        New-SpecFile "$TestDrive/c1/specs/bookings/spec.md" $script:DeltaSpec
        $s = @(Get-ChangeScenarios -SpecsDir "$TestDrive/c1/specs")
        $s.trait | Should -Be @('bookings/reserva-de-una-franja-libre', 'bookings/cancelacion-con-24-h-de-antelacion')
    }

    It 'returns every scenario of current specs with -AllSections' {
        New-SpecFile "$TestDrive/main/specs/courts/spec.md" "## Requirements`n`n### Requirement: Listar`n#### Scenario: Listar pistas`n- **WHEN** a`n- **THEN** b"
        @(Get-ChangeScenarios -SpecsDir "$TestDrive/main/specs" -AllSections).trait | Should -Be @('courts/listar-pistas')
    }

    It 'returns nothing when the folder does not exist' {
        @(Get-ChangeScenarios -SpecsDir "$TestDrive/missing").Count | Should -Be 0
    }
}

Describe 'Get-TrxScenarioResults' {
    It 'reads every Scenario trait of every test with its outcome' {
        New-Trx "$TestDrive/r.trx" @(
            @{ name = 'T1'; outcome = 'Passed'; traits = @('bookings/a') },
            @{ name = 'T2'; outcome = 'Failed'; traits = @('bookings/b', 'bookings/c') },
            @{ name = 'T3'; outcome = $null; traits = @('bookings/d') })
        $r = @(Get-TrxScenarioResults -TrxFiles "$TestDrive/r.trx")
        $r.Count | Should -Be 4
        ($r | Where-Object trait -eq 'bookings/a').outcome | Should -Be 'Passed'
        ($r | Where-Object trait -eq 'bookings/c').outcome | Should -Be 'Failed'
        ($r | Where-Object trait -eq 'bookings/d').outcome | Should -Be 'NotExecuted'
    }
}

Describe 'Get-TraceabilityReport' {
    BeforeAll {
        $script:Scenarios = @(
            [pscustomobject]@{ capability = 'bookings'; title = 'A'; trait = 'bookings/a' },
            [pscustomobject]@{ capability = 'bookings'; title = 'B'; trait = 'bookings/b' },
            [pscustomobject]@{ capability = 'bookings'; title = 'C'; trait = 'bookings/c' })
    }

    It 'marks scenarios as passed, failed (any traced test failing) or missing using TRX evidence' {
        $trx = @(
            [pscustomobject]@{ trait = 'bookings/a'; test = 'T1'; outcome = 'Passed' },
            [pscustomobject]@{ trait = 'bookings/b'; test = 'T2'; outcome = 'Passed' },
            [pscustomobject]@{ trait = 'bookings/b'; test = 'T3'; outcome = 'Failed' })
        $r = Get-TraceabilityReport -Scenarios $script:Scenarios -TrxResults $trx -HasTrx
        ($r.rows | Where-Object trait -eq 'bookings/a').status | Should -Be 'passed'
        ($r.rows | Where-Object trait -eq 'bookings/b').status | Should -Be 'failed'
        ($r.rows | Where-Object trait -eq 'bookings/c').status | Should -Be 'missing'
        $r.failures | Should -Be 2
    }

    It 'treats a test that did not run as a failure when TRX evidence exists' {
        $trx = @([pscustomobject]@{ trait = 'bookings/a'; test = 'T1'; outcome = 'NotExecuted' })
        $r = Get-TraceabilityReport -Scenarios @($script:Scenarios[0]) -TrxResults $trx -HasTrx
        $r.rows[0].status | Should -Be 'failed'
    }

    It 'uses source traits as "not executed" (not a failure) when there is no TRX' {
        $src = @([pscustomobject]@{ trait = 'bookings/a'; file = 'x.cs'; line = 3 })
        $r = Get-TraceabilityReport -Scenarios @($script:Scenarios[0]) -SourceTraits $src
        $r.rows[0].status | Should -Be 'not-executed'
        $r.failures | Should -Be 0
    }

    It 'reports orphan traits of the same capability unless they belong to the current specs' {
        $trx = @(
            [pscustomobject]@{ trait = 'bookings/a'; test = 'T1'; outcome = 'Passed' },
            [pscustomobject]@{ trait = 'bookings/typo'; test = 'T2'; outcome = 'Passed' },
            [pscustomobject]@{ trait = 'bookings/existing'; test = 'T3'; outcome = 'Passed' },
            [pscustomobject]@{ trait = 'courts/other'; test = 'T4'; outcome = 'Passed' })
        $r = Get-TraceabilityReport -Scenarios @($script:Scenarios[0]) -TrxResults $trx -KnownTraits @('bookings/existing') -HasTrx
        $r.orphans | Should -Be @('bookings/typo')
    }
}

Describe 'Get-ChangedFilesCoverage' {
    It 'measures only changed files and merges hits across reports' {
        $root = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory -Force $root | Out-Null
        New-Cobertura "$TestDrive/a.cobertura.xml" (Join-Path $root 'src/App/Booking.cs') @{ 1 = 1; 2 = 0; 3 = 0; 4 = 0 }
        New-Cobertura "$TestDrive/b.cobertura.xml" (Join-Path $root 'src/App/Booking.cs') @{ 1 = 0; 2 = 3; 3 = 0; 4 = 0 }
        New-Cobertura "$TestDrive/c.cobertura.xml" (Join-Path $root 'src/App/Unchanged.cs') @{ 1 = 0 }
        $cov = Get-ChangedFilesCoverage -CoberturaFiles "$TestDrive/a.cobertura.xml", "$TestDrive/b.cobertura.xml", "$TestDrive/c.cobertura.xml" -ChangedFiles 'src/App/Booking.cs' -Root $root
        $cov.files.Count | Should -Be 1
        $cov.covered | Should -Be 2
        $cov.valid | Should -Be 4
        $cov.rate | Should -Be 50
    }

    It 'returns a null rate when no changed file appears in the reports' {
        New-Cobertura "$TestDrive/d.cobertura.xml" '/repo/src/Other.cs' @{ 1 = 1 }
        $cov = Get-ChangedFilesCoverage -CoberturaFiles "$TestDrive/d.cobertura.xml" -ChangedFiles 'src/New.cs' -Root '/repo'
        $cov.rate | Should -BeNullOrEmpty
    }

    It 'lists changed files absent from every report instead of ignoring them' {
        $root = Join-Path $TestDrive 'repo2'
        New-Cobertura "$TestDrive/e.cobertura.xml" (Join-Path $root 'src/Covered.cs') @{ 1 = 1 }
        $cov = Get-ChangedFilesCoverage -CoberturaFiles "$TestDrive/e.cobertura.xml" -ChangedFiles 'src/Covered.cs', 'src/NotInstrumented.cs' -Root $root
        $cov.rate | Should -Be 100
        $cov.missing | Should -Be @('src/NotInstrumented.cs')
    }
}

Describe 'Test-CSharpHasExecutableCode' {
    It 'is false for declaration-only files and true when there is something to execute' -TestCases @(
        @{ name = 'interface'; code = "namespace A;`npublic interface IRepo`n{`n    Task<int> CountAsync(CancellationToken ct);`n}"; expected = $false }
        @{ name = 'enum'; code = "namespace A;`n[Flags]`npublic enum Sport { Padel = 1, Tennis = 2 }"; expected = $false }
        @{ name = 'positional record'; code = "namespace A;`npublic sealed record CourtDto(Guid Id, string Name);"; expected = $false }
        @{ name = 'record with body'; code = "public record R(int A) { public int B => A * 2; }"; expected = $true }
        @{ name = 'method body'; code = "public class C`n{`n    public int Add(int a, int b)`n    {`n        return a + b;`n    }`n}"; expected = $true }
        @{ name = 'expression body'; code = 'public class C { public int Two() => 2; }'; expected = $true }
        @{ name = 'property accessor'; code = 'public class C { private int x; public int X { get { return x; } } }'; expected = $true }
        @{ name = 'property initializer'; code = 'public class C { public int Value { get; } = 42; }'; expected = $true }
        @{ name = 'top-level statements'; code = "var builder = WebApplication.CreateBuilder(args);`nbuilder.Build().Run();"; expected = $true }
        @{ name = 'commented code only'; code = "public interface I { }`n// public int Add(int a, int b) => a + b;"; expected = $false }
        @{ name = 'keyword inside a string'; code = "public interface I { [Obsolete(`"use new API`")] void M(); }"; expected = $false }
    ) {
        param($name, $code, $expected)
        $path = Join-Path $TestDrive "$($name -replace '\s', '-').cs"
        $code | Set-Content $path -Encoding utf8
        Test-CSharpHasExecutableCode $path | Should -Be $expected
    }
}

Describe 'traceability.ps1' {
    BeforeEach {
        $script:Repo = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force $script:Repo | Out-Null
    }

    It 'fails when the change does not exist' {
        $null = & pwsh -NoProfile -File $script:Traceability -Change 'nope' -Root $script:Repo 2>&1
        $LASTEXITCODE | Should -Be 1
    }

    It 'passes a tooling change that declares skip_specs: true' {
        New-SpecFile "$script:Repo/openspec/changes/tooling/.openspec.yaml" "schema: spec-driven`nskip_specs: true"
        $null = & pwsh -NoProfile -File $script:Traceability -Change 'tooling' -Root $script:Repo 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'finds an archived change and fails when its scenario has no passing test' {
        New-SpecFile "$script:Repo/openspec/changes/archive/2026-10-20-add-x/specs/bookings/spec.md" $script:DeltaSpec
        New-Trx "$script:Repo/results/r.trx" @(@{ name = 'T1'; outcome = 'Passed'; traits = @('bookings/reserva-de-una-franja-libre') })
        $out = & pwsh -NoProfile -File $script:Traceability -Change 'add-x' -Root $script:Repo -ResultsDir "$script:Repo/results" 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'resultados TRX'
        $out | Should -Match 'cancelacion-con-24-h-de-antelacion'
    }

    It 'passes when every scenario has a passing test' {
        New-SpecFile "$script:Repo/openspec/changes/add-x/specs/bookings/spec.md" $script:DeltaSpec
        New-Trx "$script:Repo/results/r.trx" @(
            @{ name = 'T1'; outcome = 'Passed'; traits = @('bookings/reserva-de-una-franja-libre') },
            @{ name = 'T2'; outcome = 'Passed'; traits = @('bookings/cancelacion-con-24-h-de-antelacion') })
        $null = & pwsh -NoProfile -File $script:Traceability -Change 'add-x' -Root $script:Repo -ResultsDir "$script:Repo/results" -RequireTrx 2>&1
        $LASTEXITCODE | Should -Be 0
    }

    It 'fails with -RequireTrx when the results folder has no TRX (never falls back to source code)' {
        New-SpecFile "$script:Repo/openspec/changes/add-x/specs/bookings/spec.md" $script:DeltaSpec
        New-SpecFile "$script:Repo/tests/T.cs" '[Trait("Scenario", "bookings/reserva-de-una-franja-libre")] [Trait("Scenario", "bookings/cancelacion-con-24-h-de-antelacion")]'
        New-Item -ItemType Directory -Force "$script:Repo/results" | Out-Null
        $out = & pwsh -NoProfile -File $script:Traceability -Change 'add-x' -Root $script:Repo -ResultsDir "$script:Repo/results" -RequireTrx 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'No TRX'
    }

    It 'returns 3 (not executed) when traits are only found in source code, including several traits per line' {
        New-SpecFile "$script:Repo/openspec/changes/add-x/specs/bookings/spec.md" $script:DeltaSpec
        New-SpecFile "$script:Repo/tests/T.cs" '[Fact, Trait("Scenario", "bookings/reserva-de-una-franja-libre"), Trait("Scenario", "bookings/cancelacion-con-24-h-de-antelacion")]'
        $null = & pwsh -NoProfile -File $script:Traceability -Change 'add-x' -Root $script:Repo 2>&1
        $LASTEXITCODE | Should -Be 3
    }

    It 'ignores skip_specs: true when the change has scenarios' {
        New-SpecFile "$script:Repo/openspec/changes/add-x/specs/bookings/spec.md" $script:DeltaSpec
        New-SpecFile "$script:Repo/openspec/changes/add-x/.openspec.yaml" "schema: spec-driven`nskip_specs: true"
        $out = & pwsh -NoProfile -File $script:Traceability -Change 'add-x' -Root $script:Repo 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'skip_specs: true.*se ignora'
    }
}
