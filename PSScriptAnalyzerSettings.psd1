@{
    # Suprime falsos positivos de variaveis definidas em config.ps1 e libs
    # que sao usadas via dot-source em outros scripts — o analyzer nao segue imports.
    ExcludeRules = @(
        'PSUseDeclaredVarsMoreThanAssignments'  # vars de config sao usadas via dot-source
        'PSUseApprovedVerbs'                    # CoinEx-* usa namespace como prefixo
        'PSUseSingularNouns'                    # GetCandles/GetMarkets retornam colecoes intencionalmente
        'PSAvoidUsingWriteHost'                 # output colorido e intencional nos agentes
        'PSAvoidUsingEmptyCatchBlock'           # catches vazios sao fallbacks de APIs opcionais
        'PSAvoidUsingPositionalParameters'      # parâmetros posicionais em chamadas internas de lib
        'PSUseShouldProcessForStateChangingFunctions'  # New-* nos testes sao helpers puros, nao cmdlets reais
    )
}
