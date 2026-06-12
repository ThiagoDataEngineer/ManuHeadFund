# lib_journal_csv_locale.Tests.ps1 - Pester 3.x
# RED-GREEN-REFACTOR: bug de serializacao CSV em locale PT-BR (decimais com virgula)
# Rodar: Invoke-Pester .\tests\lib_journal_csv_locale.Tests.ps1 -Verbose

# Forca cultura PT-BR no thread atual (reproduz o bug do agente)
$global:__prevCulture   = [System.Threading.Thread]::CurrentThread.CurrentCulture
$global:__prevUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
[System.Threading.Thread]::CurrentThread.CurrentCulture   = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')
[System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')

# Sanity check do ambiente: confirma que cultura PT-BR transforma 2.8469 em "2,8469"
# (se este Should Be falhar a maquina nao tem PT-BR; testes ainda devem funcionar pois
#  o codigo sob teste deve ser locale-independente)
$tmpDir  = Join-Path $env:TEMP "libjournal_locale_$(Get-Random)"
[System.IO.Directory]::CreateDirectory($tmpDir) | Out-Null

# Stub silencioso para evitar poluir saida
function Write-Host { param() }

# Redireciona o journal para tmp ANTES do dot-source
$env:JOURNAL_TEST_REDIRECT = $tmpDir
$JOURNAL_DIR  = $tmpDir
$JOURNAL_FILE = Join-Path $tmpDir "gem_signals.csv"

. "$PSScriptRoot\..\agents\lib_journal.ps1"

# Apos dot-source, sobrescreve globals do modulo
$global:JOURNAL_DIR  = $tmpDir
$global:JOURNAL_FILE = Join-Path $tmpDir "gem_signals.csv"

# Helper: monta um GemResult sintetico minimo
function New-FakeGemResult {
    param(
        [string]$Market    = "TESTUSDT",
        [double]$SpikeRatio = 2.8469,
        [double]$PctChange  = 26.47,
        [double]$VolToday   = 12345.6789,
        [double]$SizingUsd  = 100.5,
        [double]$StopPct    = 0.05,
        [double]$TargetPct  = 0.25,
        [double]$Mcap       = 1000000.0,
        [string]$Alerta     = "",
        [string]$GateFailed = "",
        [int]$Score         = 80
    )
    return [pscustomobject]@{
        market       = $Market
        score        = $Score
        mode         = "MOMENTUM"
        gates_passed = @("G1","G2","G3")
        gate_failed  = $GateFailed
        mcap_usd     = $Mcap
        alerta       = $Alerta
        vol_data     = [pscustomobject]@{
            spike_ratio      = $SpikeRatio
            spike_type       = "BULLISH"
            pct_change_today = $PctChange
            vol_today        = $VolToday
        }
        sizing       = [pscustomobject]@{
            sizing_usd = $SizingUsd
            stop_pct   = $StopPct
            target_pct = $TargetPct
        }
    }
}

# Stub para Invoke-RestMethod (evita chamada de rede dentro de Write-GemJournalEntry)
function Invoke-RestMethod { param([Parameter(ValueFromRemainingArguments=$true)]$rest) throw "no network in tests" }

function Reset-Journal {
    if (Test-Path $global:JOURNAL_FILE) { Remove-Item $global:JOURNAL_FILE -Force }
}

Describe "lib_journal CSV - locale-safe serialization (PT-BR)" {

    It "Write-GemJournalEntry serializa double 2.8469 como '2.8469' (ponto, nao virgula)" {
        Reset-Journal
        $r = New-FakeGemResult -SpikeRatio 2.8469
        Write-GemJournalEntry -GemResult $r -ScanId "T1"
        $lines = Get-Content $global:JOURNAL_FILE
        # Linha de dados (segunda linha; primeira eh header)
        $data = $lines[1]
        ($data -match "2\.8469") | Should Be $true
        ($data -match "2,8469") | Should Be $false
    }

    It "Write-GemJournalEntry com gate_failed null/vazio nao escreve 'null' nem '`$null'" {
        Reset-Journal
        $r = New-FakeGemResult -GateFailed $null
        Write-GemJournalEntry -GemResult $r -ScanId "T2"
        $data = (Get-Content $global:JOURNAL_FILE)[1]
        ($data -match "(?i)\bnull\b") | Should Be $false
        ($data -match '\$null')       | Should Be $false
    }

    It "Write-GemJournalEntry com float em locale PT-BR preserva ponto decimal em todos os campos" {
        Reset-Journal
        $r = New-FakeGemResult -SpikeRatio 1.5 -PctChange 3.14 -VolToday 99.99 -SizingUsd 50.5 -StopPct 0.075 -TargetPct 0.333
        Write-GemJournalEntry -GemResult $r -ScanId "T3"
        $data = (Get-Content $global:JOURNAL_FILE)[1]
        # Nenhum valor decimal pode aparecer com virgula
        # (separador de campo eh virgula; mas decimais foram passados com ponto)
        # Conta numero de campos: header tem 17 colunas
        $headerCount = ((Get-Content $global:JOURNAL_FILE)[0] -split ',').Count
        $dataCount   = ($data -split ',').Count
        # Se decimais virassem virgula, dataCount > headerCount
        $dataCount | Should Be $headerCount
    }

    It "Write-GemJournalEntry escapa virgula literal em string (quoting RFC 4180)" {
        Reset-Journal
        # Nota: campo 'alerta' eh pre-mangled (virgula -> ;) no caller para evitar quebrar
        # CSV em codigo legado. Para validar o quoting do _formatter_, usamos gate_failed
        # que chega bruto ate a serializacao.
        $r = New-FakeGemResult -GateFailed "G3,G4,G5"
        Write-GemJournalEntry -GemResult $r -ScanId "T4"
        $parsed = Import-Csv -Path $global:JOURNAL_FILE
        $parsed[0].gate_failed | Should Be "G3,G4,G5"
    }

    It "Write-GemJournalEntry preserva ordem das colunas (header == ordem de Values)" {
        Reset-Journal
        $r = New-FakeGemResult -Market "ORDERUSDT" -Score 77
        Write-GemJournalEntry -GemResult $r -ScanId "T5_SCAN"
        $parsed = Import-Csv -Path $global:JOURNAL_FILE
        $parsed[0].market  | Should Be "ORDERUSDT"
        $parsed[0].score   | Should Be "77"
        $parsed[0].scan_id | Should Be "T5_SCAN"
    }

    It "Round-trip: Import-Csv recupera float spike_ratio original" {
        Reset-Journal
        $r = New-FakeGemResult -SpikeRatio 2.8469
        Write-GemJournalEntry -GemResult $r -ScanId "T6"
        $parsed = Import-Csv -Path $global:JOURNAL_FILE
        # Parse explicito com InvariantCulture
        $sr = [double]::Parse($parsed[0].spike_ratio, [System.Globalization.CultureInfo]::InvariantCulture)
        [Math]::Abs($sr - 2.8469) -lt 1e-9 | Should Be $true
    }

    It "Edge: valor com aspas duplas eh escapado corretamente (RFC 4180 quote-doubling)" {
        Reset-Journal
        $r = New-FakeGemResult -Alerta 'ele disse "hello"'
        Write-GemJournalEntry -GemResult $r -ScanId "T7"
        $parsed = Import-Csv -Path $global:JOURNAL_FILE
        $parsed[0].alerta | Should Be 'ele disse "hello"'
    }

    It "Edge: valor com newline embutido eh tratado (quoted ou stripped, sem quebrar linhas)" {
        Reset-Journal
        $r = New-FakeGemResult -Alerta "linha1`nlinha2"
        Write-GemJournalEntry -GemResult $r -ScanId "T8"
        $rawLines = Get-Content $global:JOURNAL_FILE
        # Header + 1 entry => no maximo 2 linhas (se newline foi stripped)
        # ou >2 mas com quoting valido (Import-Csv ainda parseia 1 record)
        $parsed = @(Import-Csv -Path $global:JOURNAL_FILE)
        $parsed.Count | Should Be 1
        # E a entrada nao contem '$null' nem string 'null'
        ($parsed[0].alerta -match '(?i)^null$') | Should Be $false
    }
}

# Restaura cultura no fim
[System.Threading.Thread]::CurrentThread.CurrentCulture   = $global:__prevCulture
[System.Threading.Thread]::CurrentThread.CurrentUICulture = $global:__prevUiCulture
