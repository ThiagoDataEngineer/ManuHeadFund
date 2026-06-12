# B3 upstream fix 2026-05-20 PM6+: garante que campos texto (Notes, alerta, reason)
# preservam virgulas via RFC4180 quoting ao inves do hack ,->; antigo.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_ladder_tracker.ps1")
. (Join-Path $projectRoot "agents\lib_observation_logger.ps1")

Describe "B3 RFC4180 quoting end-to-end" {
    Context "_LadderTracker-CsvField helper" {
        It "passthrough texto sem virgula" {
            (_LadderTracker-CsvField "simples") | Should Be "simples"
        }
        It "envolve em aspas duplas quando ha virgula" {
            (_LadderTracker-CsvField "Druckenmiller, preserve capital first") | Should Be '"Druckenmiller, preserve capital first"'
        }
        It "duplica aspas internas RFC4180" {
            (_LadderTracker-CsvField 'tem "aspas" dentro, e virgula') | Should Be '"tem ""aspas"" dentro, e virgula"'
        }
        It "null/empty vira string vazia" {
            (_LadderTracker-CsvField $null) | Should Be ""
        }
        It "newline forca quoting" {
            $out = _LadderTracker-CsvField "linha1`nlinha2"
            ($out.StartsWith('"') -and $out.EndsWith('"')) | Should Be $true
        }
    }
    Context "ConvertTo-CsvField (observation logger)" {
        It "preserva virgula em texto" {
            (ConvertTo-CsvField "a, b, c") | Should Be '"a, b, c"'
        }
        It "Import-Csv roundtrip recupera texto original com virgulas" {
            $tmp = Join-Path $env:TEMP "b3_roundtrip_$([guid]::NewGuid()).csv"
            try {
                "ts,reason" | Out-File $tmp -Encoding utf8
                $reason = "Druckenmiller, preserve capital first, returns follow"
                $row = "2026-05-20T00:00:00Z," + (ConvertTo-CsvField $reason)
                Add-Content -Path $tmp -Value $row -Encoding utf8
                $rows = Import-Csv $tmp
                $rows[0].reason | Should Be $reason
            } finally {
                Remove-Item $tmp -ErrorAction SilentlyContinue
            }
        }
    }
}
