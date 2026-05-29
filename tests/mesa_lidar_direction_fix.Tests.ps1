# mesa_lidar_direction_fix.Tests.ps1 -- TDD 2026-05-28
#
# Problema: LIDAR votava em direcao oposta ao direction_proxy do setup.
# Ex: direction_proxy=SHORT, RR=5, vol_ratio=1.2 -> LIDAR votava LONG.
# Causa: prompt fraco ("Leia o campo direction_proxy") -- LLM ignorava e
# inferia direcao pelo contexto tecnico recebido.
#
# Dados: 82 casos de CAOS genuino no mesa_drones.jsonl. Em 57% deles,
# vol_ratio >= 0.5 (liquidez OK) mas LIDAR ainda votava oposto ao setup.
# Padrão dominante: T=SHORT / R=NEUTRO / L=LONG (51.6% dos CAOS).
#
# Solucao (2 mudancas):
#   1. Threshold vol_ratio: 0.5 -> 0.37 (dados mostram P25=0.22 nos CAOS,
#      mas 0.37 e conservador -- resolve 36% dos casos de liquidez baixa)
#   2. Prompt LIDAR: instrucao imperativa com algoritmo explicito + exemplos
#      corretos/errados -- elimina ambiguidade sobre direction_proxy
#
# Estes testes cobrem:
#   Suite 1: prompt contem instrucoes imperativas sobre direction_proxy
#   Suite 2: prompt contem threshold 0.37 (nao 0.5)
#   Suite 3: prompt contem exemplos corretos e errados
#   Suite 4: prompt contem algoritmo obrigatorio numerado
#   Suite 5: regressao -- comportamento correto do LIDAR via Get-MesaConsensus
#   Suite 6: propriedades do prompt (escopo, nao avalia tecnico)
#
# Pester 3.x. UTF-8 BOM.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\agents\mesa_agent.ps1"

function Write-Host    { param($Object, $ForegroundColor) }
function Write-Warning { param($Message) }

function New-DroneOk {
    param([string]$Sinal="LONG",[int]$Forca=70,[string]$Just="ok",[string[]]$Conf=@())
    [PSCustomObject]@{ sinal=$Sinal; forca=$Forca; justificativa=$Just; confluencias=$Conf }
}

# ─── Suite 1: instrucoes imperativas sobre direction_proxy ────────────────────

Describe "LIDAR prompt: instrucoes imperativas direction_proxy" {

    It "prompt contem 'REGRA ABSOLUTA' ou equivalente imperativo" {
        $MESA_LIDAR_SYSTEM | Should Match "ABSOLUTA|OBRIGATORIO|NUNCA vote"
    }

    It "prompt proibe votar direcao diferente do direction_proxy" {
        $MESA_LIDAR_SYSTEM | Should Match "NUNCA vote em direcao diferente"
    }

    It "prompt contem algoritmo numerado (1. 2. 3.)" {
        $MESA_LIDAR_SYSTEM | Should Match "1\."
        $MESA_LIDAR_SYSTEM | Should Match "2\."
        $MESA_LIDAR_SYSTEM | Should Match "3\."
    }

    It "prompt instrui a ler direction_proxy do SETUP PROPOSTO" {
        $MESA_LIDAR_SYSTEM | Should Match "direction_proxy"
        $MESA_LIDAR_SYSTEM | Should Match "SETUP PROPOSTO"
    }

    It "prompt deixa claro que TERMAL e RADAR decidem direcao, nao LIDAR" {
        $MESA_LIDAR_SYSTEM | Should Match "TERMAL"
        $MESA_LIDAR_SYSTEM | Should Match "RADAR"
        $MESA_LIDAR_SYSTEM | Should Match "NAO decide se o mercado"
    }
}

# ─── Suite 2: threshold vol_ratio 0.37 ───────────────────────────────────────

Describe "LIDAR prompt: threshold vol_ratio 0.37" {

    It "prompt menciona 0.37 como threshold de liquidez" {
        $MESA_LIDAR_SYSTEM | Should Match "0\.37"
    }

    It "prompt NAO menciona 0.5 como threshold de liquidez (substituido)" {
        # 0.5 pode aparecer em exemplos de RR (ex: "RR=0.5") mas nao como threshold
        # A linha "vol_ratio >= 0.5" foi substituida por "vol_ratio >= 0.37"
        $MESA_LIDAR_SYSTEM | Should Not Match "vol_ratio >= 0\.5"
    }

    It "regra de NEUTRO usa 0.37 (nao 0.5)" {
        $MESA_LIDAR_SYSTEM | Should Match "vol_ratio < 0\.37"
    }

    It "regras de sinal usam 0.37 como threshold" {
        # Ambas as regras RR>=3 e RR 2-3 devem usar 0.37
        ($MESA_LIDAR_SYSTEM -split "`n" | Where-Object { $_ -match "vol_ratio >= 0\.37" }).Count |
            Should BeGreaterThan 1
    }
}

# ─── Suite 3: exemplos corretos e errados ────────────────────────────────────

Describe "LIDAR prompt: exemplos corretos e errados" {

    It "prompt contem secao EXEMPLOS CORRETOS" {
        $MESA_LIDAR_SYSTEM | Should Match "EXEMPLOS CORRETOS"
    }

    It "prompt contem secao EXEMPLOS ERRADOS" {
        $MESA_LIDAR_SYSTEM | Should Match "EXEMPLOS ERRADOS|ERRADO"
    }

    It "exemplo correto: direction_proxy=SHORT + RR=5 -> sinal=SHORT" {
        $MESA_LIDAR_SYSTEM | Should Match "direction_proxy=SHORT.*sinal=SHORT"
    }

    It "exemplo correto: direction_proxy=LONG + vol_ratio baixo -> NEUTRO" {
        $MESA_LIDAR_SYSTEM | Should Match "direction_proxy=LONG.*NEUTRO.*liquidez"
    }

    It "exemplo errado: votar LONG quando direction_proxy=SHORT" {
        $MESA_LIDAR_SYSTEM | Should Match "direction_proxy=SHORT.*LONG.*ERRADO"
    }

    It "exemplo errado: votar SHORT quando direction_proxy=LONG" {
        $MESA_LIDAR_SYSTEM | Should Match "direction_proxy=LONG.*SHORT.*ERRADO"
    }
}

# ─── Suite 4: escopo do LIDAR preservado ─────────────────────────────────────

Describe "LIDAR prompt: escopo preservado" {

    It "prompt menciona RR como criterio principal" {
        $MESA_LIDAR_SYSTEM | Should Match "RR|R-multiples"
    }

    It "prompt menciona vol_ratio como criterio de liquidez" {
        $MESA_LIDAR_SYSTEM | Should Match "vol_ratio"
    }

    It "prompt menciona stop coerente como criterio" {
        $MESA_LIDAR_SYSTEM | Should Match "stop coerente|Stop INCOERENTE"
    }

    It "prompt proibe avaliar RSI/EMA/Ichimoku (escopo de outros drones)" {
        $MESA_LIDAR_SYSTEM | Should Match "RSI|EMA|Ichimoku"
        $MESA_LIDAR_SYSTEM | Should Match "NAO E SEU PAPEL|papel de TERMAL"
    }

    It "prompt menciona Van Tharp como persona" {
        $MESA_LIDAR_SYSTEM | Should Match "Van Tharp"
    }
}

# ─── Suite 5: regressao Get-MesaConsensus ────────────────────────────────────

Describe "Regressao: Get-MesaConsensus nao afetado pela mudanca de prompt" {

    It "SHORT/SHORT/LONG ainda e MEDIO_2 SHORT (maioria)" {
        $r = Get-MesaConsensus `
            -Termal (New-DroneOk -Sinal "SHORT" -Forca 75) `
            -Radar  (New-DroneOk -Sinal "SHORT" -Forca 60) `
            -Lidar  (New-DroneOk -Sinal "LONG"  -Forca 55)
        $r.consensus      | Should Be "MEDIO_2"
        $r.sinal_consenso | Should Be "SHORT"
    }

    It "SHORT/NEUTRO/LONG ainda e CAOS (1/1/1 split)" {
        $r = Get-MesaConsensus `
            -Termal (New-DroneOk -Sinal "SHORT"  -Forca 75) `
            -Radar  (New-DroneOk -Sinal "NEUTRO" -Forca 50) `
            -Lidar  (New-DroneOk -Sinal "LONG"   -Forca 55)
        $r.consensus | Should Be "CAOS"
    }

    It "SHORT/SHORT/NEUTRO e MEDIO_2 SHORT (LIDAR correto vota NEUTRO por liquidez)" {
        # Comportamento esperado APOS o fix: LIDAR vota NEUTRO (liquidez baixa)
        # em vez de LONG (inferindo direcao). Resultado: MEDIO_2 em vez de CAOS.
        $r = Get-MesaConsensus `
            -Termal (New-DroneOk -Sinal "SHORT"  -Forca 75) `
            -Radar  (New-DroneOk -Sinal "SHORT"  -Forca 60) `
            -Lidar  (New-DroneOk -Sinal "NEUTRO" -Forca 25)
        $r.consensus      | Should Be "MEDIO_2"
        $r.sinal_consenso | Should Be "SHORT"
    }

    It "SHORT/SHORT/SHORT e FORTE_3 (LIDAR correto confirma direction_proxy=SHORT)" {
        # Comportamento esperado APOS o fix: LIDAR confirma SHORT do setup
        # em vez de votar LONG. Resultado: FORTE_3 em vez de CAOS.
        $r = Get-MesaConsensus `
            -Termal (New-DroneOk -Sinal "SHORT" -Forca 75) `
            -Radar  (New-DroneOk -Sinal "SHORT" -Forca 60) `
            -Lidar  (New-DroneOk -Sinal "SHORT" -Forca 65)
        $r.consensus      | Should Be "FORTE_3"
        $r.sinal_consenso | Should Be "SHORT"
    }
}

# ─── Suite 6: prompt LIDAR diferente dos outros drones ───────────────────────

Describe "LIDAR prompt e distinto de TERMAL e RADAR" {

    It "LIDAR nao tem instrucoes de price action (papel do TERMAL)" {
        # LIDAR nao deve mencionar ADX, EMA9, EMA21 como criterios de decisao
        # (pode mencionar como exemplos do que NAO fazer)
        $MESA_LIDAR_SYSTEM | Should Not Match "ADX >= 25|EMA9 acima EMA21"
    }

    It "LIDAR nao tem instrucoes de macro (papel do RADAR)" {
        # LIDAR menciona DXY/macro apenas para dizer que NAO e seu papel.
        # Nao deve ter instrucoes de como avaliar macro (ex: "DXY forte = bearish").
        $MESA_LIDAR_SYSTEM | Should Not Match "DXY forte|yield curve.*inversao|FED pivot|M2 global YoY"
    }

    It "LIDAR e diferente do TERMAL" {
        $MESA_LIDAR_SYSTEM -eq $MESA_TERMAL_SYSTEM | Should Be $false
    }

    It "LIDAR e diferente do RADAR" {
        $MESA_LIDAR_SYSTEM -eq $MESA_RADAR_SYSTEM | Should Be $false
    }
}
