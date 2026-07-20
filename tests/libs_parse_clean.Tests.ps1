# libs_parse_clean.Tests.ps1 — Regressao 2026-07-09 (Pester 3.4)
# Classe de bug #1 do projeto: parse error em UMA lib mata o dot-source inteiro
# (funcoes somem em silencio -> daemons quebram em runtime).
# Caso real: lib_trailing.ps1:494 parentese extra -> 14 erros -> trailing morto,
# Show-TrailingStatus inexistente, todo ciclo scan_master falhando.

$root = Split-Path $PSScriptRoot -Parent

Describe "Todas as libs parseiam limpo (PS 5.1 compatible)" {

    $libFiles = @(Get-ChildItem -Path (Join-Path $root "agents") -Filter "lib_*.ps1" -File |
        Where-Object { $_.Name -notmatch "backup" })

    foreach ($lib in $libFiles) {
        It "agents/$($lib.Name) parseia sem erros" {
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($lib.FullName, [ref]$null, [ref]$errs) | Out-Null
            if ($errs.Count -gt 0) {
                Write-Host "  PARSE FAIL $($lib.Name) L$($errs[0].Extent.StartLineNumber): $($errs[0].Message)"
            }
            $errs.Count | Should Be 0
        }
    }
}

Describe "Scripts criticos parseiam limpo" {

    $critical = @(
        "scripts\scan_master.ps1",
        "scripts\reconcile_closed_trades.ps1",
        "scripts\populate_trade_history.ps1",
        "scripts\capital_snapshot_runner.ps1",
        "agents\gem_executor.ps1",
        "agents\config.ps1"
    )

    foreach ($rel in $critical) {
        $full = Join-Path $root $rel
        if (-not (Test-Path $full)) { continue }
        It "$rel parseia sem erros" {
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$errs) | Out-Null
            if ($errs.Count -gt 0) {
                Write-Host "  PARSE FAIL $rel L$($errs[0].Extent.StartLineNumber): $($errs[0].Message)"
            }
            $errs.Count | Should Be 0
        }
    }
}
