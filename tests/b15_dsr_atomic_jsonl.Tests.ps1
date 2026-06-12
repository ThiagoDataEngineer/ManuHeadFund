# B15 fix 2026-05-20 PM6+380min.
# Migracao dsr_global pra append-only JSONL pra eliminar race condition.
# Add-DsrTrial agora pode ser chamado por 9+ gates concurrentes sem clobber.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_dsr_global.ps1")

Describe "B15 DSR append-only JSONL race-safe" {
    BeforeEach {
        $script:trialPath = Join-Path $env:TEMP "b15_trials_$([guid]::NewGuid()).jsonl"
    }
    AfterEach {
        Remove-Item $trialPath -Force -ErrorAction SilentlyContinue
    }

    It "Add-DsrTrial escreve 1 linha JSONL valida" {
        Add-DsrTrial -Path $trialPath -GateName "obs_to_c" -Market "BTCUSDT" | Out-Null
        $line = Get-Content $trialPath -Encoding UTF8
        $obj = $line | ConvertFrom-Json
        $obj.gate    | Should Be "obs_to_c"
        $obj.market  | Should Be "BTCUSDT"
        $obj.ts      | Should Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
    }

    It "Multiplos trials = multiplas linhas (sem clobber)" {
        Add-DsrTrial -Path $trialPath -GateName "obs_to_c" -Market "BTC" | Out-Null
        Add-DsrTrial -Path $trialPath -GateName "funding" -Market "ETH" | Out-Null
        Add-DsrTrial -Path $trialPath -GateName "concentration" -Market "SOL" | Out-Null
        @(Get-Content $trialPath).Count | Should Be 3
    }

    It "Get-DsrTrials retorna total agregado" {
        Add-DsrTrial -Path $trialPath -GateName "obs_to_c" -Market "BTC" | Out-Null
        Add-DsrTrial -Path $trialPath -GateName "obs_to_c" -Market "ETH" | Out-Null
        Add-DsrTrial -Path $trialPath -GateName "funding" -Market "SOL" | Out-Null
        (Get-DsrTrials -Path $trialPath) | Should Be 3
    }

    It "Get-DsrTrials -GateName filtra por gate" {
        Add-DsrTrial -Path $trialPath -GateName "obs_to_c" -Market "BTC" | Out-Null
        Add-DsrTrial -Path $trialPath -GateName "obs_to_c" -Market "ETH" | Out-Null
        Add-DsrTrial -Path $trialPath -GateName "funding" -Market "SOL" | Out-Null
        (Get-DsrTrials -Path $trialPath -GateName "obs_to_c") | Should Be 2
        (Get-DsrTrials -Path $trialPath -GateName "funding")  | Should Be 1
        (Get-DsrTrials -Path $trialPath -GateName "nada")     | Should Be 0
    }

    It "race simulada: 10 chamadas em sequencia = 10 linhas (sem perda)" {
        for ($i = 1; $i -le 10; $i++) {
            Add-DsrTrial -Path $trialPath -GateName "g$i" -Market "M$i" | Out-Null
        }
        @(Get-Content $trialPath).Count | Should Be 10
    }

    It "arquivo inexistente: Get-DsrTrials retorna 0 sem erro" {
        $noPath = Join-Path $env:TEMP "b15_missing_$([guid]::NewGuid()).jsonl"
        (Get-DsrTrials -Path $noPath) | Should Be 0
    }
}
