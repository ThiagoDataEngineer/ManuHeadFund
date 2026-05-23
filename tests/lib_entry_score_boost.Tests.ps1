# lib_entry_score_boost.Tests.ps1 -- TDD pra entry score boost via trend_persistence cache.
# Pester 3.x.
#
# Get-EntryScoreBoost(Market, BaseScore): retorna BaseScore + boost (0-15 pts)
# baseado em trend_persistence_cache.json.
# STRONG_TREND   = +10
# MODERATE_TREND = +5
# WEAK_TREND     = 0
# NOISE/MEAN_REV = -5 (penalty)
# UNKNOWN        = 0

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_entry_score_boost.ps1")

$script:tmp = Join-Path $env:TEMP ("esb_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null


Describe "Get-EntryScoreBoost - trend-driven" {
    BeforeEach {
        $script:cacheFile = Join-Path $tmp "trend.json"
    }

    It "STRONG_TREND adiciona +10 ao base" {
        @{ HOT = @{ label="STRONG_TREND"; score=0.55 } } | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "HOT" -BaseScore 70 -CachePath $cacheFile
        $r.adjusted_score | Should Be 80
        $r.boost | Should Be 10
        $r.trend_label | Should Be "STRONG_TREND"
    }

    It "MODERATE_TREND adiciona +5" {
        @{ MOD = @{ label="MODERATE_TREND"; score=0.30 } } | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "MOD" -BaseScore 70 -CachePath $cacheFile
        $r.boost | Should Be 5
        $r.adjusted_score | Should Be 75
    }

    It "WEAK_TREND nao muda score" {
        @{ WEAK = @{ label="WEAK_TREND"; score=0.10 } } | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "WEAK" -BaseScore 70 -CachePath $cacheFile
        $r.boost | Should Be 0
        $r.adjusted_score | Should Be 70
    }

    It "NOISE penaliza -5" {
        @{ NOISE = @{ label="NOISE"; score=-0.10 } } | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "NOISE" -BaseScore 70 -CachePath $cacheFile
        $r.boost | Should Be -5
        $r.adjusted_score | Should Be 65
    }

    It "MEAN_REVERTING penaliza -5" {
        @{ MR = @{ label="MEAN_REVERTING"; score=-0.30 } } | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "MR" -BaseScore 70 -CachePath $cacheFile
        $r.boost | Should Be -5
        $r.adjusted_score | Should Be 65
    }

    It "Market nao em cache: UNKNOWN, boost=0" {
        @{} | ConvertTo-Json | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "NOWHERE" -BaseScore 70 -CachePath $cacheFile
        $r.boost | Should Be 0
        $r.trend_label | Should Be "UNKNOWN"
    }

    It "Sem arquivo cache: UNKNOWN, boost=0" {
        $r = Get-EntryScoreBoost -Market "X" -BaseScore 70 -CachePath (Join-Path $tmp "nope.json")
        $r.boost | Should Be 0
        $r.trend_label | Should Be "UNKNOWN"
    }

    It "Score nao cai abaixo de 0" {
        @{ MR = @{ label="MEAN_REVERTING"; score=-0.30 } } | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "MR" -BaseScore 3 -CachePath $cacheFile
        $r.adjusted_score | Should Be 0
    }

    It "Score nao passa de 100" {
        @{ HOT = @{ label="STRONG_TREND"; score=0.55 } } | ConvertTo-Json -Depth 5 | Out-File $cacheFile -Encoding utf8
        $r = Get-EntryScoreBoost -Market "HOT" -BaseScore 95 -CachePath $cacheFile
        $r.adjusted_score | Should Be 100
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
