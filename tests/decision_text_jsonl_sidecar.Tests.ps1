# JSONL sidecar para texto livre (D3 2026-05-20 PM6+).
# CSV continua sendo SSoT pra tabular; JSONL sidecar guarda texto livre (reason/alerta/notes)
# linkado por (ts, market). Mentor pode escrever , " \n sem corromper nada.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_observation_logger.ps1")

Describe "D3 JSONL sidecar - texto livre sem corruption" {
    BeforeEach {
        $script:tmpRoot = Join-Path $env:TEMP "d3_sidecar_$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    }
    AfterEach {
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Add-DecisionText - append-only" {
        It "cria arquivo + escreve 1 linha JSONL valida" {
            $path = Join-Path $tmpRoot "decisions_text.jsonl"
            Add-DecisionText -Path $path -Market "BTCUSDT" -Reason "test"
            Test-Path $path | Should Be $true
            $line = Get-Content $path -Encoding UTF8
            $obj = $line | ConvertFrom-Json
            $obj.market | Should Be "BTCUSDT"
            $obj.reason | Should Be "test"
        }

        It "multiplas linhas = multiplas entradas JSONL" {
            $path = Join-Path $tmpRoot "decisions_text.jsonl"
            Add-DecisionText -Path $path -Market "BTC" -Reason "1"
            Add-DecisionText -Path $path -Market "ETH" -Reason "2"
            Add-DecisionText -Path $path -Market "SOL" -Reason "3"
            @(Get-Content $path).Count | Should Be 3
        }

        It "preserva virgula + aspas + newline na reason" {
            $path = Join-Path $tmpRoot "decisions_text.jsonl"
            $reason = "Druckenmiller, ""preserve capital"" first`nreturns follow"
            Add-DecisionText -Path $path -Market "BTC" -Reason $reason
            $line = Get-Content $path -Encoding UTF8 -Raw
            $obj = $line.Trim() | ConvertFrom-Json
            $obj.reason | Should Be $reason
        }

        It "campos opcionais (alerta/notes/mesa/mentor) ficam no JSON" {
            $path = Join-Path $tmpRoot "decisions_text.jsonl"
            Add-DecisionText -Path $path -Market "BTC" -Reason "r" -Alerta "alert!" -Notes "n" `
                             -MesaConsensus "FORTE" -MentorDecision "APROVAR"
            $obj = Get-Content $path | ConvertFrom-Json
            $obj.alerta | Should Be "alert!"
            $obj.notes  | Should Be "n"
            $obj.mesa_consensus | Should Be "FORTE"
            $obj.mentor_decision | Should Be "APROVAR"
        }

        It "ts em ISO-8601 UTC" {
            $path = Join-Path $tmpRoot "decisions_text.jsonl"
            Add-DecisionText -Path $path -Market "BTC" -Reason "r"
            $obj = Get-Content $path | ConvertFrom-Json
            $obj.ts | Should Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
        }

        It "valores null nao quebram parser (omitidos do JSON)" {
            $path = Join-Path $tmpRoot "decisions_text.jsonl"
            Add-DecisionText -Path $path -Market "BTC" -Reason "r" -Alerta $null -Notes ""
            { Get-Content $path | ConvertFrom-Json } | Should Not Throw
        }
    }

    Context "Integracao Add-Decision -> sidecar automatico" {
        It "Add-Decision com -TextSidecar grava JSONL paralelo" {
            $csv = Join-Path $tmpRoot "decisions.csv"
            $jsonl = Join-Path $tmpRoot "decisions_text.jsonl"
            $reason = "Razao complexa, com virgulas, ""aspas"" e tudo"
            Add-Decision -DecFile $csv -TextSidecarFile $jsonl `
                         -Market "BTC" -Decision "ABORTAR" -Reason $reason
            Test-Path $csv   | Should Be $true
            Test-Path $jsonl | Should Be $true
            $obj = Get-Content $jsonl | ConvertFrom-Json
            $obj.reason | Should Be $reason
        }
    }
}
