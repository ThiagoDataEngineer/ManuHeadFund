# B20 anti-regression 2026-05-20 PM6+490min.
# Garante paridade spot com futures B19b — todas funções PlaceOrder
# geram client_id, persistem em order_client_ids.jsonl e atualizam status.

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "B20 spot client_id parity com futures B19b" {
    BeforeAll {
        $script:libSrc = Get-Content (Join-Path $projectRoot "agents\lib_coinex.ps1") -Raw
    }

    It "CoinEx-PlaceSpotOrder chama New-OrderClientId" {
        $start = $libSrc.IndexOf("function CoinEx-PlaceSpotOrder")
        $end = $libSrc.IndexOf("function ", $start + 30)
        $scope = $libSrc.Substring($start, $end - $start)
        $scope | Should Match 'New-OrderClientId'
    }
    It "CoinEx-PlaceSpotOrder adiciona client_id ao body" {
        $start = $libSrc.IndexOf("function CoinEx-PlaceSpotOrder")
        $end = $libSrc.IndexOf("function ", $start + 30)
        $scope = $libSrc.Substring($start, $end - $start)
        $scope | Should Match '\$body\.client_id'
    }
    It "CoinEx-PlaceSpotOrder atualiza Update-OrderClientIdStatus" {
        $start = $libSrc.IndexOf("function CoinEx-PlaceSpotOrder")
        $end = $libSrc.IndexOf("function ", $start + 30)
        $scope = $libSrc.Substring($start, $end - $start)
        $scope | Should Match 'Update-OrderClientIdStatus'
    }
    It "CoinEx-PlaceSpotStopOrder tambem tem client_id" {
        $start = $libSrc.IndexOf("function CoinEx-PlaceSpotStopOrder")
        $end = $libSrc.IndexOf("function ", $start + 30)
        if ($end -lt 0) { $end = $libSrc.Length }
        $scope = $libSrc.Substring($start, $end - $start)
        $scope | Should Match 'New-OrderClientId'
        $scope | Should Match '\$body\.client_id'
    }
    It "B21: _Order-GenerateClientId sem dead code (apenas 1 geracao GUID)" {
        $gen = Get-Content (Join-Path $projectRoot "agents\lib_order_idempotency.ps1") -Raw
        # Conta ocorrencias de [guid]::NewGuid() dentro de _Order-GenerateClientId
        $start = $gen.IndexOf("function _Order-GenerateClientId")
        $end = $gen.IndexOf("function ", $start + 30)
        if ($end -lt 0) { $end = $gen.Length }
        $scope = $gen.Substring($start, $end - $start)
        $guidCount = ([regex]::Matches($scope, '\[guid\]::NewGuid\(\)')).Count
        $guidCount | Should Be 1
    }
}
