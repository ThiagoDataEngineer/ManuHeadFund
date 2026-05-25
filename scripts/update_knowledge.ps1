# update_knowledge.ps1
# Atualiza e valida os arquivos de conhecimento de trading
# Uso: .\update_knowledge.ps1 [-Check] [-Summary] [-AddNote "texto" -File "arquivo.md"]

param(
    [switch]$Check,
    [string]$AddNote = "",
    [string]$File = "",
    [switch]$Summary
)

$KnowledgeDir = (Join-Path $PSScriptRoot "knowledge")
$ClaudeFile   = (Join-Path $PSScriptRoot "CLAUDE.md")

$KnowledgeFiles = @{
    "TECHNICAL_ANALYSIS.md"  = "Price action, padroes, tendencias, MTF"
    "WYCKOFF_SMC.md"         = "Wyckoff Method + Smart Money Concepts"
    "SCALP_DAYTRADING.md"    = "Estrategias scalp e day trading testadas"
    "ONCHAIN_ANALYSIS.md"    = "Metricas on-chain, ferramentas"
    "MARKET_CYCLES.md"       = "Ciclos macro, halving, Weinstein"
    "RISK_MANAGEMENT.md"     = "Gestao de risco, sizing, Kelly"
    "INDICATORS_REFERENCE.md"= "Biblia de indicadores tecnicos"
    "MACRO_CONTEXT.md"       = "DXY, FED, M2, correlacoes macro-crypto"
    "BEAR_MARKET.md"         = "Especializacao profunda bear market"
    "REFERENCES_LIBRARY.md"  = "Analise critica de livros, traders, ferramentas"
    "PATH_TO_1PCT.md"        = "Roadmap pratico para o 1% real (4 fases)"
    "MENTOR.md"              = "Persona mentor: Livermore, Tudor Jones, Druckenmiller, Seykota..."
    "MENTOR_PROMPT.md"       = "System prompt do Mentor pronto para Claude API"
    "MANIPULATION.md"        = "Manipulacao: taxonomia, 5 papers peer-reviewed, 5 casos juridicos, deteccao"
    "GEM_COINS.md"           = "Micro-caps explosivos: ciclo de vida, DISCOVERY/MOMENTUM, validacao historica"
    "PUMP_FINGERPRINTS.md"   = "Assinaturas de pump: PEPE/WIF/BONK/SKYAI, deteccao organico vs wash, score 0-100"
    "MICRO_LIQUIDITY.md"     = "Mercados vol < 500K: slippage real, sizing por liquidez, saida fracionada"
    "NARRATIVE_CATALYSTS.md" = "Narrativas e pumps: taxonomia Tier 1-3, ciclo de vida, keywords, extincao"
    "MELAO_SATURNO.md"       = "Melao/Saturno V: ergodicidade, Melao Index, anti-scalping, otimizacao, Kelly"
    "TORI_TRADES.md"         = "Tori Trades: trendline strategy, Action/Safety Line, bounce/break, crypto"
}

function Write-Header { param([string]$T); Write-Host ""; Write-Host "=== $T ===" -ForegroundColor Cyan; Write-Host "" }
function Write-OK      { param([string]$m); Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-ERR     { param([string]$m); Write-Host "  [XX] $m" -ForegroundColor Red }

# MODO: CHECK
if ($Check) {
    Write-Header "Verificando arquivos de conhecimento"
    $allOk = $true
    foreach ($f in ($KnowledgeFiles.Keys | Sort-Object)) {
        $p = Join-Path $KnowledgeDir $f
        if (Test-Path $p) {
            $lines = (Get-Content $p).Count
            $kb    = [math]::Round((Get-Item $p).Length / 1KB, 1)
            Write-OK ("{0,-40} {1,5} linhas  {2} KB" -f $f, $lines, $kb)
        } else {
            Write-ERR "$f  NAO ENCONTRADO"
            $allOk = $false
        }
    }
    if (Test-Path $ClaudeFile) {
        $lines = (Get-Content $ClaudeFile).Count
        Write-OK ("CLAUDE.md{0,31} {1,5} linhas" -f "", $lines)
    } else {
        Write-ERR "CLAUDE.md  NAO ENCONTRADO"; $allOk = $false
    }
    Write-Host ""
    if ($allOk) { Write-Host "Todos os arquivos OK." -ForegroundColor Green }
    else         { Write-Host "Arquivos faltando." -ForegroundColor Red }
    return
}

# MODO: SUMMARY
if ($Summary) {
    Write-Header "Resumo da Base de Conhecimento"
    $totalLines = 0; $totalSize = 0
    foreach ($f in ($KnowledgeFiles.Keys | Sort-Object)) {
        $p = Join-Path $KnowledgeDir $f
        if (Test-Path $p) {
            $lines = (Get-Content $p).Count
            $size  = (Get-Item $p).Length
            $totalLines += $lines; $totalSize += $size
            Write-Host ("  {0,-42} {1,5} linhas   {2}" -f $f, $lines, $KnowledgeFiles[$f]) -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host ("  Total: {0} linhas  |  {1} KB" -f $totalLines, [math]::Round($totalSize/1KB,1)) -ForegroundColor Cyan
    return
}

# MODO: ADD NOTE
if ($AddNote -ne "" -and $File -ne "") {
    $target = Join-Path $KnowledgeDir $File
    if (-not (Test-Path $target)) { Write-ERR "Arquivo nao encontrado: $target"; return }
    $date    = Get-Date -Format "yyyy-MM-dd"
    $section = "`n`n---`n`n## Nota em $date`n`n$AddNote`n"
    Add-Content -Path $target -Value $section -Encoding UTF8
    Write-OK "Nota adicionada em $File"
    return
}

# MODO DEFAULT: HELP
Write-Header "update_knowledge.ps1 - Gestor da Base de Conhecimento"
Write-Host "Uso:" -ForegroundColor Yellow
Write-Host "  .\update_knowledge.ps1 -Check"
Write-Host "    Verifica se todos os arquivos existem"
Write-Host ""
Write-Host "  .\update_knowledge.ps1 -Summary"
Write-Host "    Mostra todos os arquivos com contagem de linhas"
Write-Host ""
Write-Host "  .\update_knowledge.ps1 -AddNote 'texto' -File 'BEAR_MARKET.md'"
Write-Host "    Adiciona nota datada ao final de um arquivo"
Write-Host ""
Write-Host "Arquivos disponiveis:" -ForegroundColor Yellow
foreach ($f in ($KnowledgeFiles.Keys | Sort-Object)) {
    Write-Host ("  {0,-42} {1}" -f $f, $KnowledgeFiles[$f])
}
