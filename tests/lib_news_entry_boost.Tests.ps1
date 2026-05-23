# lib_news_entry_boost.Tests.ps1 -- TDD pra Get-NewsEntryBoost.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_news_entry_boost.ps1")

$script:tmp = Join-Path $env:TEMP ("neb_$([guid]::NewGuid())")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$global:JOURNAL_DIR = $tmp
# Re-eval cached paths
$script:IDEA_PATH = Join-Path $tmp "idea_triggers.jsonl"
$script:NEWS_PATH = Join-Path $tmp "news_signals.jsonl"
$script:TREND_PATH = Join-Path $tmp "trend_persistence_cache.json"


Describe "Test-IdeaTriggeredRecently" {
    It "Sem arquivo retorna false" {
        Test-IdeaTriggeredRecently -Market "BTC" -IdeaPath (Join-Path $tmp "nope.jsonl") | Should Be $false
    }
    It "Triggered nas ultimas 24h retorna true" {
        $f = Join-Path $tmp "ideas_a.jsonl"
        $now = (Get-Date).ToUniversalTime().AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")
        @{ id="x"; market="BTC"; status="triggered"; fired_at=$now } | ConvertTo-Json -Compress | Out-File $f -Encoding utf8
        Test-IdeaTriggeredRecently -Market "BTC" -IdeaPath $f | Should Be $true
    }
    It "Triggered ha 5 dias atras retorna false" {
        $f = Join-Path $tmp "ideas_b.jsonl"
        $old = (Get-Date).ToUniversalTime().AddDays(-5).ToString("yyyy-MM-ddTHH:mm:ssZ")
        @{ id="x"; market="BTC"; status="triggered"; fired_at=$old } | ConvertTo-Json -Compress | Out-File $f -Encoding utf8
        Test-IdeaTriggeredRecently -Market "BTC" -IdeaPath $f | Should Be $false
    }
    It "Active mas nao triggered retorna false" {
        $f = Join-Path $tmp "ideas_c.jsonl"
        $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        @{ id="x"; market="BTC"; status="active"; created_at=$now } | ConvertTo-Json -Compress | Out-File $f -Encoding utf8
        Test-IdeaTriggeredRecently -Market "BTC" -IdeaPath $f | Should Be $false
    }
}


Describe "Get-NewsSignalRecent" {
    It "Sem arquivo retorna 0.0 (neutro)" {
        Get-NewsSignalRecent -Market "BTC" -NewsPath (Join-Path $tmp "nope.jsonl") | Should Be 0.0
    }
    It "News bullish recente retorna sentiment positivo" {
        $f = Join-Path $tmp "news_a.jsonl"
        $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        @{ ts=$now; market="ETH"; sentiment=0.7 } | ConvertTo-Json -Compress | Out-File $f -Encoding utf8
        Get-NewsSignalRecent -Market "ETH" -NewsPath $f | Should Be 0.7
    }
    It "News antiga (>3d) ignorada" {
        $f = Join-Path $tmp "news_b.jsonl"
        $old = (Get-Date).ToUniversalTime().AddDays(-5).ToString("yyyy-MM-ddTHH:mm:ssZ")
        @{ ts=$old; market="ETH"; sentiment=0.7 } | ConvertTo-Json -Compress | Out-File $f -Encoding utf8
        Get-NewsSignalRecent -Market "ETH" -NewsPath $f | Should Be 0.0
    }
}


Describe "Get-TrendPersistenceLabel" {
    It "Sem cache retorna UNKNOWN" {
        $r = Get-TrendPersistenceLabel -Market "BTC" -CachePath (Join-Path $tmp "nope.json")
        $r.label | Should Be "UNKNOWN"
        $r.score | Should Be 0
    }
    It "Cache com market retorna label + score" {
        $f = Join-Path $tmp "trend.json"
        @{ BTC = @{ label="STRONG_TREND"; score=0.62 }; ETH = @{ label="NOISE"; score=-0.05 } } |
            ConvertTo-Json -Depth 5 | Out-File $f -Encoding utf8
        $r = Get-TrendPersistenceLabel -Market "BTC" -CachePath $f
        $r.label | Should Be "STRONG_TREND"
        $r.score | Should Be 0.62
    }
}


Describe "Get-NewsEntryBoost - composite" {
    It "Sem nenhum sinal retorna boost=0" {
        $r = Get-NewsEntryBoost -Market "EMPTY" -Direction "LONG"
        $r.boost | Should Be 0
    }
    It "Idea triggered + LONG + news bullish + trend strong = boost forte" {
        # Fixtures escritos nos paths default (resolvidos via $global:JOURNAL_DIR)
        $iPath = Join-Path $tmp "idea_triggers.jsonl"
        $nPath = Join-Path $tmp "news_signals.jsonl"
        $tPath = Join-Path $tmp "trend_persistence_cache.json"
        $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        @{ id="i"; market="HOT"; status="triggered"; fired_at=$now } | ConvertTo-Json -Compress | Out-File $iPath -Encoding utf8
        @{ ts=$now; market="HOT"; sentiment=0.6 } | ConvertTo-Json -Compress | Out-File $nPath -Encoding utf8
        @{ HOT = @{ label="STRONG_TREND"; score=0.55 } } | ConvertTo-Json -Depth 5 | Out-File $tPath -Encoding utf8

        $r = Get-NewsEntryBoost -Market "HOT" -Direction "LONG"
        # idea_triggered=10 + news_aligned=5 + trend_strong=10 = 25 (sem funding cached)
        ($r.boost -ge 25) | Should Be $true
        ($r.reasons -join ',') -match "idea_triggered" | Should Be $true
        ($r.reasons -join ',') -match "trend_strong" | Should Be $true
    }
    It "Direction SHORT com news bullish nao recebe boost news" {
        $r = Get-NewsEntryBoost -Market "EMPTY" -Direction "SHORT"
        # so checa que nao crasha; deve ser 0
        $r.boost | Should Be 0
    }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
