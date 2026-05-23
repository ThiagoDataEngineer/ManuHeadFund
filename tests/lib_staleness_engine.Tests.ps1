$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_staleness_engine.ps1")

function _TmpDir {
    $d = Join-Path $env:TEMP ("stale_" + $PID + "_" + (Get-Random))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

Describe "Get-StalenessRegistry" {
    It "Retorna array non-empty" {
        $reg = Get-StalenessRegistry
        $reg.Count | Should BeGreaterThan 3
    }
    It "Cada item tem campos obrigatorios" {
        foreach ($item in (Get-StalenessRegistry)) {
            $item.name | Should Not BeNullOrEmpty
            $item.item_pattern | Should Not BeNullOrEmpty
            $item.rerun_cmd | Should Not BeNullOrEmpty
            ($item.priority_base -in @("HIGH","MEDIUM","LOW")) | Should Be $true
        }
    }
}

Describe "Test-Stale-CapitalSensitive" {
    It "capital_sensitive=false: sempre false mesmo com drift alto" {
        $item = @{ capital_sensitive = $false }
        Test-Stale-CapitalSensitive -Item $item -DriftPct 100 | Should Be $false
    }
    It "capital_sensitive=true + drift 50%: true" {
        $item = @{ capital_sensitive = $true }
        Test-Stale-CapitalSensitive -Item $item -DriftPct 50 | Should Be $true
    }
    It "capital_sensitive=true + drift 10%: false (abaixo threshold 30)" {
        $item = @{ capital_sensitive = $true }
        Test-Stale-CapitalSensitive -Item $item -DriftPct 10 | Should Be $false
    }
}

Describe "Test-Stale-TimeBased" {
    It "File ausente: true (stale by definition)" {
        $d = _TmpDir
        try {
            $item = @{ time_sensitive = $true; max_age_days = 30; item_pattern = "test_*.json" }
            Test-Stale-TimeBased -Item $item -JournalDir $d | Should Be $true
        } finally { Remove-Item $d -Recurse -Force }
    }
    It "File fresh: false" {
        $d = _TmpDir
        try {
            $item = @{ time_sensitive = $true; max_age_days = 30; item_pattern = "test_*.json" }
            "{}" | Out-File (Join-Path $d "test_1.json") -Encoding utf8
            Test-Stale-TimeBased -Item $item -JournalDir $d | Should Be $false
        } finally { Remove-Item $d -Recurse -Force }
    }
    It "File old (>max_age): true" {
        $d = _TmpDir
        try {
            $item = @{ time_sensitive = $true; max_age_days = 7; item_pattern = "test_*.json" }
            $f = Join-Path $d "test_1.json"
            "{}" | Out-File $f -Encoding utf8
            (Get-Item $f).LastWriteTime = (Get-Date).AddDays(-30)
            Test-Stale-TimeBased -Item $item -JournalDir $d | Should Be $true
        } finally { Remove-Item $d -Recurse -Force }
    }
}

Describe "Get-StaleItems integration" {
    It "Sem drift + diretorio vazio: items time-sensitive flagged" {
        $d = _TmpDir
        try {
            $items = Get-StaleItems -JournalDir $d -DriftPct 0
            # Maioria do registry eh time_sensitive + arquivo ausente => stale
            $items.Count | Should BeGreaterThan 2
        } finally { Remove-Item $d -Recurse -Force }
    }
    It "Drift alto 60% bumps capital_sensitive items pra HIGH" {
        $d = _TmpDir
        try {
            $items = Get-StaleItems -JournalDir $d -DriftPct 60
            $highCount = @($items | Where-Object { $_.priority -eq "HIGH" }).Count
            $highCount | Should BeGreaterThan 0
        } finally { Remove-Item $d -Recurse -Force }
    }
    It "Auto-safe items distinguished from manual review" {
        $d = _TmpDir
        try {
            $items = Get-StaleItems -JournalDir $d -DriftPct 0
            $autoSafe = @($items | Where-Object { $_.auto_safe })
            $manualReview = @($items | Where-Object { -not $_.auto_safe })
            ($autoSafe.Count + $manualReview.Count) | Should Be $items.Count
        } finally { Remove-Item $d -Recurse -Force }
    }
}

Describe "Write-StalenessAudit" {
    It "Cria audit.json + history.jsonl" {
        $d = _TmpDir
        try {
            $audit = Write-StalenessAudit -JournalDir $d -DriftPct 25 -CapitalSnapshot @{total=3000}
            (Test-Path (Join-Path $d "staleness_audit.json")) | Should Be $true
            (Test-Path (Join-Path $d "staleness_audit_history.jsonl")) | Should Be $true
            $audit.n_stale | Should BeGreaterThan 0
        } finally { Remove-Item $d -Recurse -Force }
    }
}

Describe "Property: priority sorting" {
    It "HIGH items vem antes de MEDIUM antes de LOW" {
        $d = _TmpDir
        try {
            $items = Get-StaleItems -JournalDir $d -DriftPct 100  # bump capital_sens to HIGH
            $prevOrder = -1
            $order = @{ HIGH=0; MEDIUM=1; LOW=2 }
            foreach ($i in $items) {
                $cur = $order[$i.priority]
                ($cur -ge $prevOrder) | Should Be $true
                $prevOrder = $cur
            }
        } finally { Remove-Item $d -Recurse -Force }
    }
}
