# grade_llm_decisions.ps1 — AUTO-APRENDIZADO das decisoes LLM (2026-07-04)
# Fecha o loop que fizemos NA MAO no estudo dos gates: cada decisao do mentor
# (APROVAR/VETAR) e gradeada 48h+ depois contra candles REAIS:
#   VETAR  correto se o trade TERIA PERDIDO (mercado foi contra a direcao)
#   APROVAR correto se o trade TERIA GANHO  (mercado confirmou)
# Saidas:
#   journal/decision_grades.jsonl  — nota por decisao (dataset)
#   journal/llm_calibration.json   — placar agregado por decisao|direcao|regime
# O placar e INJETADO no prompt do mentor (bloco [CALIBRACAO]) -> o LLM decide
# a proxima vez SABENDO onde historicamente erra. Roda 1x/dia (guardian 06h).
# PS 5.1, BOM. Threshold: |move D+2| >= 3% define win/loss; <3% = neutro (nao grada).

param([int]$MinAgeHours = 48, [int]$MaxGrade = 300)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $root "journal"
$snapsPath = Join-Path $journalDir "signal_snapshots.jsonl"
$gradesPath = Join-Path $journalDir "decision_grades.jsonl"
$calibPath = Join-Path $journalDir "llm_calibration.json"
# _Mirror-LearningToSupabase (espelho manuheadfund) vive em lib_direction_learning.
. (Join-Path $root "agents\lib_direction_learning.ps1")

if (-not (Test-Path $snapsPath)) { Write-Host "sem snapshots"; exit 0 }

# Ja gradeados (dedupe por ts|market|decision)
$graded = @{}
if (Test-Path $gradesPath) {
    foreach ($line in (Get-Content $gradesPath -ErrorAction SilentlyContinue)) {
        try { $g = $line | ConvertFrom-Json; $graded["$($g.ts)|$($g.market)|$($g.decision)"] = $true } catch { }
    }
}

$cutoff = (Get-Date).ToUniversalTime().AddHours(-$MinAgeHours)
$candleCache = @{}

function Get-DailyCandles { param([string]$Market)
    if ($candleCache.ContainsKey($Market)) { return $candleCache[$Market] }
    $out = @()
    try {
        $r = Invoke-RestMethod -Uri "https://api.coinex.com/v2/spot/kline?market=$Market&period=1day&limit=100" -TimeoutSec 10
        if ($r.code -eq 0 -and $r.data) { $out = @($r.data) }
    } catch { }
    $candleCache[$Market] = $out
    Start-Sleep -Milliseconds 120
    return $out
}

$newGrades = 0; $sb = New-Object System.Text.StringBuilder
foreach ($line in (Get-Content $snapsPath -Encoding UTF8)) {
    if ($newGrades -ge $MaxGrade) { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $s = $null
    try { $s = $line | ConvertFrom-Json } catch { continue }
    if (-not $s.market -or -not $s.decision -or -not $s.entry_price) { continue }
    if ([double]$s.entry_price -le 0) { continue }
    if ($s.decision -notin @("APROVAR","VETAR")) { continue }
    $ts = $null
    try { $ts = [datetime]::Parse([string]$s.ts, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() } catch { continue }
    if ($ts -gt $cutoff) { continue }   # muito recente pra gradear
    $key = "$($s.ts)|$($s.market)|$($s.decision)"
    if ($graded.ContainsKey($key)) { continue }

    $cs = Get-DailyCandles -Market ([string]$s.market)
    if ($cs.Count -lt 3) { continue }
    $day0 = [long]([System.DateTimeOffset]$ts.Date).ToUnixTimeMilliseconds()
    $idx = -1
    for ($i = 0; $i -lt $cs.Count; $i++) { if ([long]$cs[$i].created_at -eq $day0) { $idx = $i; break } }
    if ($idx -lt 0 -or ($idx + 2) -ge $cs.Count) { continue }

    $entry = [double]$s.entry_price
    $close2 = [double]$cs[$idx + 2].close
    $dir = if ($s.direction) { "$($s.direction)".ToUpper() } else { "LONG" }
    # retorno NA DIRECAO do trade proposto
    $moveDir = if ($dir -eq "SHORT") { ($entry - $close2) / $entry * 100 } else { ($close2 - $entry) / $entry * 100 }

    if ([math]::Abs($moveDir) -lt 3) { continue }  # neutro: mercado nao provou nada

    $wouldWin = ($moveDir -ge 3)
    $correct = if ($s.decision -eq "APROVAR") { $wouldWin } else { -not $wouldWin }

    $grade = @{
        ts = [string]$s.ts; market = [string]$s.market; direction = $dir
        regime = [string]$s.regime; decision = [string]$s.decision
        move_dir_d2 = [math]::Round($moveDir, 2); would_win = $wouldWin; correct = $correct
        graded_at = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress
    [void]$sb.AppendLine($grade)
    $newGrades++
}
if ($sb.Length -gt 0) { Add-Content -Path $gradesPath -Value $sb.ToString().TrimEnd() -Encoding utf8 }
Write-Host "gradeadas agora: $newGrades"

# ── AGREGA o placar (llm_calibration.json) ──
$agg = @{}
foreach ($line in (Get-Content $gradesPath -ErrorAction SilentlyContinue)) {
    try { $g = $line | ConvertFrom-Json } catch { continue }
    $k = "$($g.decision)|$($g.direction)|$($g.regime)"
    if (-not $agg.ContainsKey($k)) { $agg[$k] = @{ n = 0; correct = 0; sum_move = 0.0 } }
    $agg[$k].n++
    if ($g.correct) { $agg[$k].correct++ }
    $agg[$k].sum_move += [double]$g.move_dir_d2
}
$calib = @()
foreach ($k in $agg.Keys) {
    $a = $agg[$k]; $parts = $k -split '\|'
    $calib += [PSCustomObject]@{
        key = $k; decision = $parts[0]; direction = $parts[1]; regime = $parts[2]
        n = $a.n
        accuracy = [math]::Round($a.correct / [math]::Max(1, $a.n), 3)
        avg_move_dir = [math]::Round($a.sum_move / [math]::Max(1, $a.n), 2)
    }
}
($calib | Sort-Object n -Descending | ConvertTo-Json -Depth 4) | Out-File -FilePath $calibPath -Encoding UTF8 -Force
Write-Host "placar: $($calib.Count) grupos -> $calibPath"

# Espelho Supabase (manuheadfund.decision_grades_agg) — AGREGADO por decision|direction|regime.
# PK = key. correct_rate = accuracy (correct/n). Best-effort; nao quebra o script.
if ((Get-Command _Mirror-LearningToSupabase -ErrorAction SilentlyContinue) -and $calib.Count -gt 0) {
    $nowUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $gradeRows = @($calib | ForEach-Object {
        @{
            key          = [string]$_.key
            decision     = [string]$_.decision
            direction    = [string]$_.direction
            regime       = [string]$_.regime
            n            = [int]$_.n
            correct_rate = [double]$_.accuracy
            avg_move_dir = [double]$_.avg_move_dir
            updated_at   = $nowUtc
        }
    })
    _Mirror-LearningToSupabase -Table "decision_grades_agg" -PrimaryKey "key" -Records $gradeRows
}
$calib | Where-Object { $_.n -ge 8 } | Sort-Object accuracy | Select-Object -First 6 | ForEach-Object {
    "  PIOR bolso: $($_.key) acc=$($_.accuracy) n=$($_.n) (mercado andou $($_.avg_move_dir)% na direcao)"
}
