$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_alpha_wire.ps1")

function _TmpCsv {
    return (Join-Path $env:TEMP ("alphawire_" + $PID + "_" + (Get-Random) + ".csv"))
}

Describe "Test-AlphaColumnExists" {
    It "Arquivo inexistente: retorna false" {
        Test-AlphaColumnExists -CsvPath "C:\__nonexistent__\xx.csv" | Should Be $false
    }

    It "Header sem alpha_vs_btc: false" {
        $f = _TmpCsv
        try {
            "id,timestamp,pnl" | Out-File $f -Encoding UTF8
            Test-AlphaColumnExists -CsvPath $f | Should Be $false
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Header com alpha_vs_btc: true" {
        $f = _TmpCsv
        try {
            "id,timestamp,pnl,alpha_vs_btc" | Out-File $f -Encoding UTF8
            Test-AlphaColumnExists -CsvPath $f | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Header com BOM no inicio: detecta correctamente" {
        $f = _TmpCsv
        try {
            $bom = [char]0xFEFF
            "${bom}id,timestamp,pnl,alpha_vs_btc" | Out-File $f -Encoding UTF8
            Test-AlphaColumnExists -CsvPath $f | Should Be $true
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Add-AlphaColumnToCsv" {
    It "Arquivo inexistente: returns migrated=false / reason file_not_found" {
        $r = Add-AlphaColumnToCsv -CsvPath "C:\__nope__\x.csv"
        $r.migrated | Should Be $false
        $r.reason | Should Be "file_not_found"
    }

    It "Coluna ja existe: no-op (already_exists)" {
        $f = _TmpCsv
        try {
            "id,pnl,alpha_vs_btc`n1,5.0,1.2" | Out-File $f -Encoding UTF8
            $r = Add-AlphaColumnToCsv -CsvPath $f
            $r.migrated | Should Be $false
            $r.reason | Should Be "already_exists"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "Migra com sucesso: adiciona coluna + backup + rows updated" {
        $f = _TmpCsv
        try {
            "id,pnl`n1,5.0`n2,-2.0`n3,7.5" | Out-File $f -Encoding UTF8
            $r = Add-AlphaColumnToCsv -CsvPath $f
            $r.migrated | Should Be $true
            $r.rows_updated | Should Be 3
            (Test-Path $r.backup_path) | Should Be $true
            $newHeader = (Get-Content $f -Encoding UTF8)[0]
            $newHeader | Should Match "alpha_vs_btc"
            # All data rows have trailing comma now
            $rows = @(Get-Content $f -Encoding UTF8)[1..3]
            foreach ($row in $rows) {
                $row | Should Match ","
            }
            # Cleanup backup
            if (Test-Path $r.backup_path) { Remove-Item $r.backup_path -Force }
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Update-TradeWithAlpha" {
    It "Arquivo inexistente: updated=false / file_not_found" {
        $r = Update-TradeWithAlpha -CsvPath "C:\__nope__\x.csv" -TradeId "T1" -AlphaVsBtc 1.0
        $r.updated | Should Be $false
        $r.reason | Should Be "file_not_found"
    }

    It "Coluna ausente: updated=false / column_missing" {
        $f = _TmpCsv
        try {
            "id,pnl`n1,5.0" | Out-File $f -Encoding UTF8
            $r = Update-TradeWithAlpha -CsvPath $f -TradeId "1" -AlphaVsBtc 1.0
            $r.updated | Should Be $false
            $r.reason | Should Match "column_missing"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "TradeId nao encontrado: updated=false" {
        $f = _TmpCsv
        try {
            "id,pnl,alpha_vs_btc`n1,5.0," | Out-File $f -Encoding UTF8
            $r = Update-TradeWithAlpha -CsvPath $f -TradeId "999" -AlphaVsBtc 1.5
            $r.updated | Should Be $false
            $r.reason | Should Be "trade_id_not_found"
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "TradeId encontrado: atualiza alpha (valor numerico)" {
        $f = _TmpCsv
        try {
            "id,pnl,alpha_vs_btc`n1,5.0,`n2,-2.0," | Out-File $f -Encoding UTF8
            $r = Update-TradeWithAlpha -CsvPath $f -TradeId "1" -AlphaVsBtc 2.34
            $r.updated | Should Be $true
            $content = @(Get-Content $f -Encoding UTF8)
            $content[1] | Should Match "2.34"
            $content[2] | Should Match ",-2.0,"  # row 2 nao mudou (sem alpha)
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }

    It "AlphaVsBtc null: escreve vazio (fail-soft)" {
        $f = _TmpCsv
        try {
            "id,pnl,alpha_vs_btc`n1,5.0," | Out-File $f -Encoding UTF8
            $r = Update-TradeWithAlpha -CsvPath $f -TradeId "1" -AlphaVsBtc $null
            $r.updated | Should Be $true
            # Empty alpha column persisted as just trailing comma
            $row1 = (@(Get-Content $f -Encoding UTF8))[1]
            ($row1 -split ",").Count | Should Be 3
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Property: migration idempotente" {
    It "Run 2x: 2a vez no-op (already_exists)" {
        $f = _TmpCsv
        try {
            "id,pnl`n1,5.0" | Out-File $f -Encoding UTF8
            $r1 = Add-AlphaColumnToCsv -CsvPath $f
            $r2 = Add-AlphaColumnToCsv -CsvPath $f
            $r1.migrated | Should Be $true
            $r2.migrated | Should Be $false
            $r2.reason | Should Be "already_exists"
            if (Test-Path $r1.backup_path) { Remove-Item $r1.backup_path -Force }
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}

Describe "Property: row count preservation" {
    It "Migration preserva count exato de rows (incluindo header)" {
        $f = _TmpCsv
        try {
            # Build 10 rows
            $content = "id,pnl"
            for ($i = 1; $i -le 10; $i++) { $content += "`n$i,$($i*0.5)" }
            $content | Out-File $f -Encoding UTF8
            $beforeCount = (@(Get-Content $f -Encoding UTF8)).Count
            $r = Add-AlphaColumnToCsv -CsvPath $f
            $afterCount = (@(Get-Content $f -Encoding UTF8)).Count
            $afterCount | Should Be $beforeCount
            if (Test-Path $r.backup_path) { Remove-Item $r.backup_path -Force }
        } finally { if (Test-Path $f) { Remove-Item $f -Force } }
    }
}
