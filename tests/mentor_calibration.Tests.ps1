# mentor_calibration.Tests.ps1 -- C.5
# Get-MentorCalibration agrega reflections + decisions.csv -> win_rate por
# (veredicto_5tier, provider). Detecta overconfidence drift.

$ErrorActionPreference = "Stop"
$tmpDir = Join-Path $env:TEMP "calib_tests_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

. "$PSScriptRoot\..\agents\lib_decision_reflection.ps1"
. "$PSScriptRoot\..\agents\lib_mentor_calibration.ps1"

function Reset-Refl {
    $p = Join-Path $tmpDir "refl.jsonl"
    if (Test-Path $p) { Remove-Item $p -Force }
    return $p
}

function Seed {
    param($Path, $Market, $Tier5, $Provider, $PnlPct, [string]$Veredicto="EXECUTAR")
    $tid = "$Market-$Tier5-$(Get-Random)"
    $entry = [ordered]@{
        trade_id = $tid; market = $Market; entry_date_utc = "2026-05-01"
        mentor_veredicto = $Veredicto; mentor_confidence = 75
        veredicto_5tier = $Tier5; provider_used = $Provider
        mesa_sinal = "LONG"; tier = "A"; status = "pending"
        added_at = (Get-Date).ToString("o")
    }
    Add-Content -Path $Path -Value (($entry | ConvertTo-Json -Compress)) -Encoding UTF8
    $exit = [ordered]@{
        trade_id = $tid; status = "resolved"; exit_date_utc = "2026-05-05"
        pnl_pct = [math]::Round($PnlPct,2); alpha_vs_btc = $null; holding_days = 4
        reflection = "x"; resolved_at = (Get-Date).ToString("o")
    }
    Add-Content -Path $Path -Value (($exit | ConvertTo-Json -Compress)) -Encoding UTF8
}

Describe "Get-MentorCalibration" {

    It "retorna empty stats quando ledger vazio" {
        $p = Reset-Refl
        $c = Get-MentorCalibration -ReflectionsPath $p
        $c.total_resolved | Should Be 0
    }

    It "agrupa por veredicto_5tier e computa win_rate" {
        $p = Reset-Refl
        Seed $p "RENDERUSDT" "EXECUTAR" "anthropic_sonnet" 3.0
        Seed $p "INJUSDT" "EXECUTAR" "anthropic_sonnet" 2.0
        Seed $p "DEXTUSDT" "EXECUTAR" "anthropic_sonnet" -1.5
        $c = Get-MentorCalibration -ReflectionsPath $p
        $c.total_resolved | Should Be 3
        $exec = $c.by_veredicto | Where-Object { $_.veredicto_5tier -eq "EXECUTAR" }
        $exec.n | Should Be 3
        $exec.win_rate_pct | Should Be 66.67
    }

    It "agrupa por provider tambem" {
        $p = Reset-Refl
        Seed $p "A1" "EXECUTAR" "anthropic_sonnet" 2.0
        Seed $p "A2" "EXECUTAR" "anthropic_sonnet" 3.0
        Seed $p "B1" "EXECUTAR" "groq_llama70b" -1.0
        $c = Get-MentorCalibration -ReflectionsPath $p
        $anth = $c.by_provider | Where-Object { $_.provider -eq "anthropic_sonnet" }
        $anth.n | Should Be 2
        $anth.win_rate_pct | Should Be 100.0
        $groq = $c.by_provider | Where-Object { $_.provider -eq "groq_llama70b" }
        $groq.win_rate_pct | Should Be 0.0
    }

    It "avg_pnl_pct por veredicto" {
        $p = Reset-Refl
        Seed $p "A" "EXECUTAR" "anthropic_sonnet" 3.0
        Seed $p "B" "EXECUTAR" "anthropic_sonnet" 5.0
        Seed $p "C" "EXECUTAR" "anthropic_sonnet" -2.0
        $c = Get-MentorCalibration -ReflectionsPath $p
        $exec = $c.by_veredicto | Where-Object { $_.veredicto_5tier -eq "EXECUTAR" }
        $exec.avg_pnl_pct | Should Be 2.0
    }
}

Describe "Format-CalibrationReport" {

    It "produz texto legivel com header e rows" {
        $p = Reset-Refl
        Seed $p "A" "EXECUTAR" "anthropic_sonnet" 3.0
        $c = Get-MentorCalibration -ReflectionsPath $p
        $rep = Format-CalibrationReport -Calibration $c
        $rep | Should Match "MENTOR CALIBRATION"
        $rep | Should Match "EXECUTAR"
        $rep | Should Match "anthropic_sonnet"
    }
}

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
