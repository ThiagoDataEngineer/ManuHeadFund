# lib_gem_auto_approve.Tests.ps1 -- Pester 3.x

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\lib_gem_auto_approve.ps1"

# Stub Get-FundamentalScore pra testes
$global:STUB_FQS_RESULT = $null
function Get-FundamentalScore {
    param($Market, $RegistryPath)
    return $global:STUB_FQS_RESULT
}

function New-TmpJournal {
    $d = Join-Path $env:TEMP "gemauto_$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

function New-Gem {
    param([double]$Score=92,[double]$SizingPct=0.5,[string]$Market="DASHUSDT")
    [PSCustomObject]@{ market=$Market; score=$Score; mode="DISCOVERY"; sizing_pct=$SizingPct }
}


Describe "Test-GemAutoApprove" {

    It "approved=false quando GEM_AUTO_APPROVE.flag ausente (opt-in)" {
        $jd = New-TmpJournal
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "QUALITY" }
        $r = Test-GemAutoApprove -Gem (New-Gem) -JournalDir $jd
        $r.approved | Should Be $false
        ($r.blocked_by -contains "no_opt_in_flag") | Should Be $true
        Remove-Item $jd -Recurse -Force
    }

    It "approved=true quando TODOS criterios atendidos (happy path)" {
        $jd = New-TmpJournal
        "x" | Out-File (Join-Path $jd "GEM_AUTO_APPROVE.flag") -Encoding utf8
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "QUALITY" }
        $r = Test-GemAutoApprove -Gem (New-Gem -Score 92) -JournalDir $jd
        $r.approved | Should Be $true
        ($r.reasons -contains "fqs_QUALITY") | Should Be $true
        @($r.blocked_by).Count | Should Be 0
        Remove-Item $jd -Recurse -Force
    }

    It "approved=false quando score < 90" {
        $jd = New-TmpJournal
        "x" | Out-File (Join-Path $jd "GEM_AUTO_APPROVE.flag") -Encoding utf8
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "QUALITY" }
        $r = Test-GemAutoApprove -Gem (New-Gem -Score 85) -JournalDir $jd
        $r.approved | Should Be $false
        ($r.blocked_by | Where-Object { $_ -match "score_below_min" }).Count | Should Be 1
        Remove-Item $jd -Recurse -Force
    }

    It "approved=false quando FQS SPECULATIVE" {
        $jd = New-TmpJournal
        "x" | Out-File (Join-Path $jd "GEM_AUTO_APPROVE.flag") -Encoding utf8
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "SPECULATIVE" }
        $r = Test-GemAutoApprove -Gem (New-Gem) -JournalDir $jd
        $r.approved | Should Be $false
        ($r.blocked_by | Where-Object { $_ -match "fqs_category_too_low" }).Count | Should Be 1
        Remove-Item $jd -Recurse -Force
    }

    It "approved=false quando sizing > 1%" {
        $jd = New-TmpJournal
        "x" | Out-File (Join-Path $jd "GEM_AUTO_APPROVE.flag") -Encoding utf8
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "QUALITY" }
        $r = Test-GemAutoApprove -Gem (New-Gem -SizingPct 1.5) -JournalDir $jd
        $r.approved | Should Be $false
        ($r.blocked_by | Where-Object { $_ -match "sizing_exceeds_cap" }).Count | Should Be 1
        Remove-Item $jd -Recurse -Force
    }

    It "approved=false quando daily cap atingido" {
        $jd = New-TmpJournal
        "x" | Out-File (Join-Path $jd "GEM_AUTO_APPROVE.flag") -Encoding utf8
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "QUALITY" }
        # Cria log com 3 entries hoje
        $today = (Get-Date).ToString("yyyy-MM-dd")
        $logFile = Join-Path $jd "gem_auto_approve_log.jsonl"
        1..3 | ForEach-Object {
            @{ date = $today; market = "TEST$_"; score = 95 } | ConvertTo-Json -Compress |
                Add-Content -Path $logFile -Encoding utf8
        }
        $r = Test-GemAutoApprove -Gem (New-Gem) -JournalDir $jd -DailyCap 3
        $r.approved | Should Be $false
        ($r.blocked_by | Where-Object { $_ -match "daily_cap_reached" }).Count | Should Be 1
        Remove-Item $jd -Recurse -Force
    }

    It "BLUE_CHIP tambem aprovado (mesma allowed list)" {
        $jd = New-TmpJournal
        "x" | Out-File (Join-Path $jd "GEM_AUTO_APPROVE.flag") -Encoding utf8
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "BLUE_CHIP" }
        $r = Test-GemAutoApprove -Gem (New-Gem) -JournalDir $jd
        $r.approved | Should Be $true
        Remove-Item $jd -Recurse -Force
    }

    It "approved=false quando N/A_no_registry" {
        $jd = New-TmpJournal
        "x" | Out-File (Join-Path $jd "GEM_AUTO_APPROVE.flag") -Encoding utf8
        $global:STUB_FQS_RESULT = [PSCustomObject]@{ category = "N/A_no_registry" }
        $r = Test-GemAutoApprove -Gem (New-Gem) -JournalDir $jd
        $r.approved | Should Be $false
        Remove-Item $jd -Recurse -Force
    }
}


Describe "Add-GemAutoApproveLog" {

    It "Loga entry em gem_auto_approve_log.jsonl" {
        $jd = New-TmpJournal
        $gem = New-Gem
        $appr = [PSCustomObject]@{ approved = $true; reasons = @("score_ok","fqs_QUALITY"); fqs = "QUALITY" }
        Add-GemAutoApproveLog -Gem $gem -ApprovalResult $appr -OrderId "ORD123" -JournalDir $jd
        $logFile = Join-Path $jd "gem_auto_approve_log.jsonl"
        (Test-Path $logFile) | Should Be $true
        # Get-Content single-line retorna string; force array via @()
        $lines = @(Get-Content $logFile -Encoding UTF8)
        $lines.Count | Should Be 1
        $rawJson = [System.IO.File]::ReadAllText($logFile).Trim()
        $entry = $rawJson | ConvertFrom-Json
        $entry.market | Should Be "DASHUSDT"
        $entry.order_id | Should Be "ORD123"
        Remove-Item $jd -Recurse -Force
    }
}
