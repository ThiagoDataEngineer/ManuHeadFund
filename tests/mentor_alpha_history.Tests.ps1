# mentor_alpha_history.Tests.ps1 -- B.4
# Get-MarketAlphaSummary le decision_reflections.jsonl, retorna stats alpha
# historico pro market. Mentor usa pra: "alt has -3pp avg alpha N=15 -> VETAR".

$ErrorActionPreference = "Stop"
$tmpDir = Join-Path $env:TEMP "alpha_hist_tests_$(Get-Random)"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

. "$PSScriptRoot\..\agents\lib_decision_reflection.ps1"
. "$PSScriptRoot\..\agents\lib_mentor_alpha_history.ps1"

function Reset-Refl {
    $path = Join-Path $tmpDir "refl.jsonl"
    if (Test-Path $path) { Remove-Item $path -Force }
    return $path
}

function Seed-Reflection {
    param($Path, $Market, $Alpha, $Pnl, [string]$EntryDate = "2026-05-01", $Veredicto = "EXECUTAR")
    $tid = "$Market-$(Get-Random)"
    Add-PendingReflection -TradeId $tid -Market $Market -EntryDateUtc $EntryDate `
        -MentorVeredicto $Veredicto -MentorConfidence 70 -MentorMensagem "x" -MesaSinal "LONG" -Tier "A" `
        -ReflectionsPath $Path
    Add-ResolvedReflection -TradeId $tid -ExitDateUtc "2026-05-05" -PnlPct $Pnl `
        -AlphaVsBtc $Alpha -HoldingDays 4 -Reflection "test" -ReflectionsPath $Path
}

Describe "Get-MarketAlphaSummary" {

    It "retorna null quando sem reflections pra market" {
        $path = Reset-Refl
        $s = Get-MarketAlphaSummary -Market "BTCUSDT" -ReflectionsPath $path
        $s.n_samples | Should Be 0
        $s.avg_alpha | Should Be $null
    }

    It "computa avg_alpha e beats_btc_rate com 3 trades" {
        $path = Reset-Refl
        Seed-Reflection $path "RENDERUSDT" 2.0 5.0
        Seed-Reflection $path "RENDERUSDT" -1.5 -3.0
        Seed-Reflection $path "RENDERUSDT" 3.5 8.0

        $s = Get-MarketAlphaSummary -Market "RENDERUSDT" -ReflectionsPath $path
        $s.n_samples | Should Be 3
        # avg = (2 + -1.5 + 3.5) / 3 = 1.333
        ($s.avg_alpha -gt 1.3 -and $s.avg_alpha -lt 1.4) | Should Be $true
        # beats_btc 2/3 = 66.67%
        ($s.beats_btc_rate_pct -gt 66 -and $s.beats_btc_rate_pct -lt 67) | Should Be $true
    }

    It "ignora alpha=null (BTC cache miss)" {
        $path = Reset-Refl
        Seed-Reflection $path "INJUSDT" 1.0 2.0
        # Reflection sem alpha (null)
        $tid = "INJUSDT-null"
        Add-PendingReflection -TradeId $tid -Market "INJUSDT" -EntryDateUtc "2026-05-01" `
            -MentorVeredicto "EXECUTAR" -MentorConfidence 70 -MentorMensagem "x" -MesaSinal "LONG" -Tier "A" `
            -ReflectionsPath $path
        Add-ResolvedReflection -TradeId $tid -ExitDateUtc "2026-05-05" -PnlPct 2 `
            -HoldingDays 4 -Reflection "x" -ReflectionsPath $path

        $s = Get-MarketAlphaSummary -Market "INJUSDT" -ReflectionsPath $path
        $s.n_samples | Should Be 1   # so 1 valid alpha
    }

    It "flag beats_btc_negative quando rate < 40%" {
        $path = Reset-Refl
        Seed-Reflection $path "DUMPUSDT" -2.0 -5.0
        Seed-Reflection $path "DUMPUSDT" -1.0 -2.0
        Seed-Reflection $path "DUMPUSDT" 1.0 1.0
        Seed-Reflection $path "DUMPUSDT" -3.0 -4.0

        $s = Get-MarketAlphaSummary -Market "DUMPUSDT" -ReflectionsPath $path
        $s.beats_btc_negative | Should Be $true
    }
}

Describe "Format-AlphaHistoryLine" {

    It "retorna ABSENT quando sem samples" {
        $line = Format-AlphaHistoryLine -Summary ([PSCustomObject]@{ n_samples = 0; avg_alpha = $null })
        $line | Should Match "ABSENT"
    }

    It "render compact quando samples >= 1" {
        $sum = [PSCustomObject]@{
            n_samples = 5; avg_alpha = 1.5; beats_btc_rate_pct = 60.0; beats_btc_negative = $false
        }
        $line = Format-AlphaHistoryLine -Summary $sum
        $line | Should Match "n=5"
        $line | Should Match "1.5"
    }

    It "marca LOSING_TO_BTC quando negative" {
        $sum = [PSCustomObject]@{
            n_samples = 10; avg_alpha = -2.1; beats_btc_rate_pct = 30.0; beats_btc_negative = $true
        }
        $line = Format-AlphaHistoryLine -Summary $sum
        $line | Should Match "LOSING_TO_BTC"
    }
}

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
