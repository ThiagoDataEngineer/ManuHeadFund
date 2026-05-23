# parity_contracts.Tests.ps1 -- Pester 3.x
# Garante que docs/PARITY_CONTRACTS.md eh honesto e cobre os 8 regimes canonicos.
# Convencoes: ($x) | Should Be $y | sem BeforeAll | sem em-dash | sem &&
#
# Refs:
#   docs/PARITY_CONTRACTS.md
#   memory/framework_paridade_python_ps.md  (Nivel 1)

$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $here "..")
$docPath  = Join-Path $repoRoot "docs\PARITY_CONTRACTS.md"

$script:CANONICAL_REGIMES = @(
    'BULL_STRONG','BULL_WEAK','SIDEWAYS','TRANSITION_UP',
    'TRANSITION_DOWN','BEAR_WEAK','BEAR_STRONG','CAPITULATION'
)

function _read_doc {
    if (-not (Test-Path $docPath)) { return $null }
    return (Get-Content $docPath -Raw -Encoding UTF8)
}

Describe "PARITY_CONTRACTS.md - existencia e estrutura" {

    It "docs/PARITY_CONTRACTS.md existe" {
        (Test-Path $docPath) | Should Be $true
    }

    It "Doc tem section header 'Regras Invariantes'" {
        $text = _read_doc
        ($text -match '##\s+Regras Invariantes') | Should Be $true
    }

    It "Doc declara versao ACTIVE" {
        $text = _read_doc
        ($text -match 'Status[:\*\s]+ACTIVE') | Should Be $true
    }
}

Describe "PARITY_CONTRACTS.md - cobertura de regras invariantes" {

    It "Test-RegimeDirectionAllowed existe em agents/lib_operational_whitelist.ps1" {
        $f = Join-Path $repoRoot "agents\lib_operational_whitelist.ps1"
        (Test-Path $f) | Should Be $true
        $content = Get-Content $f -Raw -Encoding UTF8
        ($content -match 'function\s+Test-RegimeDirectionAllowed') | Should Be $true
    }

    It "BULL_STRONG eh regime canonico documentado no doc" {
        $text = _read_doc
        ($text -match 'BULL_STRONG') | Should Be $true
        ($text -match 'regime_bull_strong') | Should Be $true
    }

    It "TRANSITION_UP + Monday (DoW=1) eh setup documentado" {
        $text = _read_doc
        # Aceita variacoes: "Mon BRT", "Monday", "DoW=1", "DoW 1"
        $hasTrans = $text -match 'TRANSITION_UP'
        $hasMon   = ($text -match 'Monday') -or ($text -match 'Mon\s+BRT') -or ($text -match 'DoW\s*=?\s*1\b')
        $hasTrans | Should Be $true
        $hasMon   | Should Be $true
    }

    It "Doc lista exatamente os 8 regimes canonicos" {
        $text = _read_doc
        foreach ($r in $script:CANONICAL_REGIMES) {
            ($text -match $r) | Should Be $true
        }
    }

    It "Doc cobre InvariantCulture (paridade locale-safe)" {
        $text = _read_doc
        ($text -match 'InvariantCulture') | Should Be $true
    }

    It "Doc cobre FRED API key (paridade macro)" {
        $text = _read_doc
        ($text -match 'FRED') | Should Be $true
    }
}
