# Spike F5 · `dotnet test` con Microsoft.Testing.Platform: cobertura, TRX y traits

- **Fecha:** 2026-10-15
- **SDK:** .NET 10.0.204 · Windows · paquetes NuGet en su última versión
- **Resultado:** ✅ Validado con una solución desechable (`.slnx` + `classlib` + proyecto de tests xUnit v3) y con el quality gate completo sobre un repo git de prueba con un change OpenSpec simulado

## Configuración mínima (para el change C0 `bootstrap-solution`)

`global.json`:

```json
{
  "sdk": { "version": "10.0.204", "rollForward": "latestFeature" },
  "test": { "runner": "Microsoft.Testing.Platform" }
}
```

Proyecto de tests (con Central Package Management, las versiones van en `Directory.Packages.props`):

```xml
<PropertyGroup>
  <OutputType>Exe</OutputType>
  <IsTestProject>true</IsTestProject>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="xunit.v3.mtp-v2" />
  <PackageReference Include="Microsoft.Testing.Extensions.CodeCoverage" />
  <PackageReference Include="Microsoft.Testing.Extensions.TrxReport" />
</ItemGroup>
```

## Comandos verificados

| Objetivo | Comando | Resultado |
|---|---|---|
| Tests + cobertura + TRX | `dotnet test --solution <sln> --no-build --results-directory <dir> --coverage --coverage-output-format cobertura --report-trx` | `<guid>.cobertura.xml` + `<Proyecto>_net10.0_x64.trx` |
| Tests de un escenario | `dotnet test --filter-trait "Scenario=<cap>/<slug>"` | Solo los tests con ese trait |
| Formato | `dotnet format <sln> --verify-no-changes --no-restore` | Exit 2 con la lista de ficheros si hay diferencias |

## Hallazgos que condicionan el diseño

1. **El TRX incluye los traits de xUnit v3** (`<Properties><Property><Key>Scenario</Key><Value>…</Value>`) junto al resultado de cada test. La trazabilidad sale de lo que **se ejecutó**, no de interpretar código fuente: `scripts/traceability.ps1` lee el TRX.
2. **Cobertura en Cobertura** con rutas absolutas por clase y líneas con `hits`: `scripts/lib/SddQuality.psm1` calcula la cobertura de los ficheros cambiados combinando varios informes.
3. `dotnet test` en modo MTP no admite las opciones de VSTest (`--collect`, `--logger`). Se usan las de MTP (`--coverage`, `--report-trx`).
4. Los saltos de línea dependen de `.editorconfig` (`end_of_line`): `dotnet format` los trata como errores de formato. C0 debe fijarlos junto a `.gitattributes`.

## Prueba de extremo a extremo del quality gate

Repo de prueba con un change `add-multiply` (2 escenarios ADDED + 1 REMOVED):

| Caso | Resultado del gate |
|---|---|
| Fichero nuevo con 1 de 5 líneas cubiertas y 1 escenario sin test | ❌ `coverage` 20 % < 80 % · ❌ `traceability` (escenario "Cuadrado de un número" sin test) |
| Código mal formateado | ❌ `dotnet` (`dotnet format` falla) |
| Ambos escenarios con test y fichero cubierto al 100 % | ✅ `dotnet`, `coverage` 100 %, `traceability` desde TRX; el escenario REMOVED no exige test |
