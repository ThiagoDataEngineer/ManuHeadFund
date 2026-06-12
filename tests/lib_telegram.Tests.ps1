# lib_telegram.Tests.ps1 -- TDD para alertas Telegram
# Pester 3.x compatible -- sem acentos

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

$global:TELEGRAM_API_BASE = "https://api.telegram.org"

function Invoke-RestMethod {
    param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 1 } }
}

. (Join-Path $agentsDir "lib_telegram.ps1")

function New-MockGem {
    param([string]$Market="FIROUSDT", [int]$Score=75, [string]$Mode="DISCOVERY")
    $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type="BULLISH"; pct_change_today=15.0 }
    $sz = [PSCustomObject]@{ sizing_pct=0.002; sizing_usd=2.0; stop_pct=0.50; target_pct=2.00 }
    return [PSCustomObject]@{ market=$Market; score=$Score; mode=$Mode; vol_data=$vd; sizing=$sz }
}

Describe "Format-TelegramMessage -- conteudo basico" {

    It "retorna string com market e score" {
        $gem = New-MockGem "FIROUSDT" -Score 78
        $msg = Format-TelegramMessage -Gem $gem
        $msg | Should Match "FIROUSDT"
        $msg | Should Match "78"
    }

    It "DISCOVERY inclui mode e sizing" {
        $gem = New-MockGem "FIROUSDT" -Mode "DISCOVERY"
        $msg = Format-TelegramMessage -Gem $gem
        $msg | Should Match "DISCOVERY"
        $msg | Should Match "2"
    }

    It "MOMENTUM inclui mode correto" {
        $gem = New-MockGem "XYZUSDT" -Mode "MOMENTUM"
        $msg = Format-TelegramMessage -Gem $gem
        $msg | Should Match "MOMENTUM"
    }

    It "inclui MarketType FUTURES por padrao" {
        $gem = New-MockGem "FIROUSDT"
        $msg = Format-TelegramMessage -Gem $gem
        $msg | Should Match "FUTURES"
    }

    It "inclui MarketType SPOT quando passado" {
        $gem = New-MockGem "FIROUSDT"
        $msg = Format-TelegramMessage -Gem $gem -MarketType "SPOT"
        $msg | Should Match "SPOT"
    }

    It "com campos ausentes nao quebra" {
        $gem = [PSCustomObject]@{ market="XUSDT"; score=70; mode="DISCOVERY"; vol_data=$null; sizing=$null }
        { Format-TelegramMessage -Gem $gem } | Should Not Throw
    }

    It "retorna string nao vazia" {
        $gem = New-MockGem "FIROUSDT"
        $msg = Format-TelegramMessage -Gem $gem
        $msg.Length | Should BeGreaterThan 10
    }
}

Describe "Send-TelegramAlert -- validacoes e envio" {

    It "retorna false se TELEGRAM_ENABLED nao e true" {
        $r = Send-TelegramAlert -Message "teste" -Token "tok" -ChatId "123" -Enabled "false"
        $r | Should Be $false
    }

    It "retorna false se token vazio" {
        $r = Send-TelegramAlert -Message "teste" -Token "" -ChatId "123" -Enabled "true"
        $r | Should Be $false
    }

    It "retorna false se chat_id vazio" {
        $r = Send-TelegramAlert -Message "teste" -Token "tok" -ChatId "" -Enabled "true"
        $r | Should Be $false
    }

    It "retorna true quando mock ok=true" {
        $r = Send-TelegramAlert -Message "teste" -Token "tok" -ChatId "123" -Enabled "true"
        $r | Should Be $true
    }

    It "retorna false em erro HTTP" {
        function Invoke-RestMethod {
            param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
            throw "network error"
        }
        $r = Send-TelegramAlert -Message "teste" -Token "tok" -ChatId "123" -Enabled "true"
        $r | Should Be $false
    }
}

# Restaura mock padrao apos teste de erro HTTP do bloco anterior
function Invoke-RestMethod {
    param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 1 } }
}

Describe "TG_EMOJI -- hashtable global de emojis" {

    It "TG_EMOJI esta definido como Hashtable" {
        $global:TG_EMOJI | Should Not BeNullOrEmpty
        ($global:TG_EMOJI -is [hashtable]) | Should Be $true
    }

    It "TG_EMOJI contem todas as chaves esperadas" {
        $expected = @("alert","check","cross","clock","chart","money","target","stop","gem","fire")
        foreach ($k in $expected) {
            $global:TG_EMOJI.ContainsKey($k) | Should Be $true
        }
    }

    It "cada emoji tem Length >= 1" {
        foreach ($k in $global:TG_EMOJI.Keys) {
            $global:TG_EMOJI[$k].Length | Should BeGreaterThan 0
        }
    }
}

function New-FullGem {
    $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type="BULLISH"; pct_change_today=15.0 }
    $sz = [PSCustomObject]@{ sizing_pct=0.002; sizing_usd=2.0; stop_pct=0.50; target_pct=2.00 }
    return [PSCustomObject]@{
        market           = "FIROUSDT"
        score            = 78
        mode             = "DISCOVERY"
        vol_data         = $vd
        sizing           = $sz
        mcap_usd         = 1200000
        listing_days     = 5
        narrative        = "AI agents"
        organic_score    = 82
        gates_passed     = @("G1","G2","G3")
        fingerprint_match = "PEPE-like"
        logo_url         = "https://example.com/logo.png"
    }
}

Describe "Format-TgGemApproval -- novo layout com TLDR e CONTEXTO" {

    It "Gem completo inclui APROVAR no output" {
        $gem = New-FullGem
        $msg = Format-TgGemApproval -Gem $gem
        $msg | Should Match "APROVAR"
    }

    It "mcap_usd=1200000 aparece formatado como 1.2 ou 1.20" {
        $gem = New-FullGem
        $msg = Format-TgGemApproval -Gem $gem
        $msg | Should Match "1\.2"
    }

    It "backward-compat: Gem minimal sem novos campos retorna string nao vazia" {
        $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type="BULLISH"; pct_change_today=15.0 }
        $sz = [PSCustomObject]@{ sizing_pct=0.002; sizing_usd=2.0; stop_pct=0.50; target_pct=2.00 }
        $gem = [PSCustomObject]@{ market="XUSDT"; score=70; mode="DISCOVERY"; vol_data=$vd; sizing=$sz }
        $msg = Format-TgGemApproval -Gem $gem
        $msg.Length | Should BeGreaterThan 10
        $msg | Should Match "APROVAR"
    }

    It "gates_passed @(G1,G2,G3) aparece como G1 G2 G3" {
        $gem = New-FullGem
        $msg = Format-TgGemApproval -Gem $gem
        $msg | Should Match "G1 G2 G3"
    }
}

Describe "Send-GemAlertWithLogo -- envio com logo e fallback" {

    It "retorna false quando Enabled != true" {
        $gem = New-FullGem
        $r = Send-GemAlertWithLogo -Gem $gem -Token "tok" -ChatId "123" -Enabled "false"
        $r | Should Be $false
    }

    It "sem logo_url chama sendMessage (texto), nao sendPhoto" {
        $script:lastUri = ""
        function Invoke-RestMethod {
            param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
            $script:lastUri = $Uri
            return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 1 } }
        }
        $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type="BULLISH"; pct_change_today=15.0 }
        $sz = [PSCustomObject]@{ sizing_pct=0.002; sizing_usd=2.0; stop_pct=0.50; target_pct=2.00 }
        $gem = [PSCustomObject]@{ market="XUSDT"; score=70; mode="DISCOVERY"; vol_data=$vd; sizing=$sz }
        $r = Send-GemAlertWithLogo -Gem $gem -Token "tok" -ChatId "123" -Enabled "true"
        $r | Should Be $true
        $script:lastUri | Should Match "sendMessage"
        $script:lastUri | Should Not Match "sendPhoto"
    }

    It "com logo_url chama sendPhoto" {
        $script:lastUri = ""
        function Invoke-RestMethod {
            param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
            $script:lastUri = $Uri
            return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 1 } }
        }
        $gem = New-FullGem
        $r = Send-GemAlertWithLogo -Gem $gem -Token "tok" -ChatId "123" -Enabled "true"
        $r | Should Be $true
        $script:lastUri | Should Match "sendPhoto"
    }
}

# Restaura mock padrao apos os testes acima
function Invoke-RestMethod {
    param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
    return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 1 } }
}

# =============================================================================
# STAGE 3 -- INLINE KEYBOARD CALLBACK TESTS
# Cada bloco abaixo testa um contrato; inicialmente falha com NotImplementedException
# ate o Agent 2 implementar a logica real.
# =============================================================================

Describe "Stage 3 - Inline Keyboard Callbacks" {

    Context "New-TgApprovalKeyboard" {

        It "retorna Hashtable com chave inline_keyboard" {
            $kb = New-TgApprovalKeyboard -GemId "TESTGEM"
            ($kb -is [hashtable]) | Should Be $true
            $kb.ContainsKey("inline_keyboard") | Should Be $true
        }

        It "inline_keyboard e array de arrays (linhas de botoes)" {
            $kb = New-TgApprovalKeyboard -GemId "TESTGEM"
            $rows = @($kb.inline_keyboard)
            $rows.Count | Should BeGreaterThan 0
            # cada linha deve ser uma colecao (array) de botoes
            $firstRow = @($rows[0])
            $firstRow.Count | Should BeGreaterThan 0
        }

        It "primeira linha contem 2 botoes com textos EXECUTAR e CANCELAR" {
            $kb = New-TgApprovalKeyboard -GemId "TESTGEM"
            $row0 = @($kb.inline_keyboard)[0]
            $btns = @($row0)
            $btns.Count | Should Be 2
            $allText = ($btns | ForEach-Object { $_.text }) -join " | "
            $allText | Should Match "EXECUTAR"
            $allText | Should Match "CANCELAR"
        }

        It "botao EXECUTAR tem callback_data approve:TESTGEM" {
            $kb = New-TgApprovalKeyboard -GemId "TESTGEM"
            $btns = @(@($kb.inline_keyboard)[0])
            $exec = $btns | Where-Object { $_.text -match "EXECUTAR" } | Select-Object -First 1
            $exec | Should Not BeNullOrEmpty
            $exec.callback_data | Should Be "approve:TESTGEM"
        }

        It "botao CANCELAR tem callback_data reject:TESTGEM" {
            $kb = New-TgApprovalKeyboard -GemId "TESTGEM"
            $btns = @(@($kb.inline_keyboard)[0])
            $rej = $btns | Where-Object { $_.text -match "CANCELAR" } | Select-Object -First 1
            $rej | Should Not BeNullOrEmpty
            $rej.callback_data | Should Be "reject:TESTGEM"
        }
    }

    Context "Send-TgApprovalRequest" {

        It "retorna ok=false quando Enabled != true" {
            $gem = New-FullGem
            $r = Send-TgApprovalRequest -Gem $gem -GemId "G1" -Token "tok" -ChatId "123" -Enabled "false"
            $r.ok | Should Be $false
        }

        It "com logo_url chama /sendPhoto" {
            $script:lastUri = ""
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                $script:lastUri = $Uri
                return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 42 } }
            }
            $gem = New-FullGem
            $r = Send-TgApprovalRequest -Gem $gem -GemId "G1" -Token "tok" -ChatId "123" -Enabled "true"
            $script:lastUri | Should Match "sendPhoto"
        }

        It "sem logo_url chama /sendMessage" {
            $script:lastUri = ""
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                $script:lastUri = $Uri
                return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 42 } }
            }
            $vd = [PSCustomObject]@{ spike_ratio=2.5; spike_type="BULLISH"; pct_change_today=15.0 }
            $sz = [PSCustomObject]@{ sizing_pct=0.002; sizing_usd=2.0; stop_pct=0.50; target_pct=2.00 }
            $gem = [PSCustomObject]@{ market="XUSDT"; score=70; mode="DISCOVERY"; vol_data=$vd; sizing=$sz }
            $r = Send-TgApprovalRequest -Gem $gem -GemId "G1" -Token "tok" -ChatId "123" -Enabled "true"
            $script:lastUri | Should Match "sendMessage"
            $script:lastUri | Should Not Match "sendPhoto"
        }

        It "fallback para /sendMessage se /sendPhoto falhar" {
            $script:lastUri = ""
            $script:uriHistory = @()
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                $script:lastUri = $Uri
                $script:uriHistory += $Uri
                if ($Uri -match "sendPhoto") {
                    return [PSCustomObject]@{ ok = $false; description = "bad photo" }
                }
                return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 99 } }
            }
            $gem = New-FullGem
            $r = Send-TgApprovalRequest -Gem $gem -GemId "G1" -Token "tok" -ChatId "123" -Enabled "true"
            ($script:uriHistory -join " ") | Should Match "sendMessage"
        }

        It "retorna message_id da resposta da API em sucesso" {
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 777 } }
            }
            $gem = New-FullGem
            $r = Send-TgApprovalRequest -Gem $gem -GemId "G1" -Token "tok" -ChatId "123" -Enabled "true"
            $r.ok | Should Be $true
            $r.message_id | Should Be 777
        }
    }

    Context "Confirm-TgCallback" {

        It "retorna false quando Token vazio" {
            $r = Confirm-TgCallback -CallbackId "CB1" -Token ""
            $r | Should Be $false
        }

        It "chama /answerCallbackQuery" {
            $script:lastUri = ""
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                $script:lastUri = $Uri
                return [PSCustomObject]@{ ok = $true }
            }
            $r = Confirm-TgCallback -CallbackId "CB1" -Token "tok"
            $script:lastUri | Should Match "answerCallbackQuery"
        }

        It "inclui callback_query_id no body" {
            $script:lastBody = $null
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                $script:lastBody = $Body
                return [PSCustomObject]@{ ok = $true }
            }
            $r = Confirm-TgCallback -CallbackId "CB123" -Token "tok"
            # Body pode ser hashtable ou JSON string; checa ambos
            $bodyStr = if ($script:lastBody -is [string]) {
                $script:lastBody
            } else {
                ($script:lastBody | ConvertTo-Json -Depth 5)
            }
            $bodyStr | Should Match "CB123"
            $bodyStr | Should Match "callback_query_id"
        }

        It "retorna true quando API responde ok=true" {
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                return [PSCustomObject]@{ ok = $true }
            }
            $r = Confirm-TgCallback -CallbackId "CB1" -Token "tok"
            $r | Should Be $true
        }

        It "retorna false quando API responde ok=false (sem throw)" {
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                return [PSCustomObject]@{ ok = $false; description = "bad" }
            }
            { Confirm-TgCallback -CallbackId "CB1" -Token "tok" } | Should Not Throw
            $r = Confirm-TgCallback -CallbackId "CB1" -Token "tok"
            $r | Should Be $false
        }
    }

    Context "Update-TgCaption" {

        It "retorna false quando Token vazio" {
            $r = Update-TgCaption -MessageId 1 -Caption "x" -Token "" -ChatId "123"
            $r | Should Be $false
        }

        It "retorna false quando ChatId vazio" {
            $r = Update-TgCaption -MessageId 1 -Caption "x" -Token "tok" -ChatId ""
            $r | Should Be $false
        }

        It "chama /editMessageCaption quando -WasPhoto" {
            $script:lastUri = ""
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                $script:lastUri = $Uri
                return [PSCustomObject]@{ ok = $true }
            }
            $r = Update-TgCaption -MessageId 1 -Caption "novo" -WasPhoto -Token "tok" -ChatId "123"
            $script:lastUri | Should Match "editMessageCaption"
        }

        It "chama /editMessageText quando NAO -WasPhoto" {
            $script:lastUri = ""
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                $script:lastUri = $Uri
                return [PSCustomObject]@{ ok = $true }
            }
            $r = Update-TgCaption -MessageId 1 -Caption "novo" -Token "tok" -ChatId "123"
            $script:lastUri | Should Match "editMessageText"
            $script:lastUri | Should Not Match "editMessageCaption"
        }

        It "retorna true quando ok=true" {
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                return [PSCustomObject]@{ ok = $true }
            }
            $r = Update-TgCaption -MessageId 1 -Caption "x" -Token "tok" -ChatId "123"
            $r | Should Be $true
        }

        It "retorna false quando Invoke-RestMethod lanca excecao" {
            function Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
                throw "network error"
            }
            $r = Update-TgCaption -MessageId 1 -Caption "x" -Token "tok" -ChatId "123"
            $r | Should Be $false
        }
    }

    Context "Wait-TgCallbackApproval" {

        # Restaura mock padrao antes deste Context
        function Invoke-RestMethod {
            param($Uri, $Method, $Body, $Headers, $ContentType, $ErrorAction)
            return [PSCustomObject]@{ ok = $true; result = [PSCustomObject]@{ message_id = 42 } }
        }

        It "retorna decision=error quando Send-TgApprovalRequest falha" {
            # Mock interno: forcar ok=false
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $false; message_id = $null; was_photo = $false }
            }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 1 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            $r.decision | Should Be "error"
        }

        It "retorna decision=approve quando callback_query data=approve:GEM123" {
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $true; message_id = 42; was_photo = $false }
            }
            function Confirm-TgCallback { param($CallbackId, $Text, $Token) return $true }
            function Update-TgCaption   { param($MessageId, $Caption, $WasPhoto, $Token, $ChatId) return $true }
            $fakeUpdate = @{
                update_id = 999
                callback_query = @{
                    id   = "CB1"
                    data = "approve:GEM123"
                    from = @{ first_name = "Thiago" }
                    message = @{ message_id = 42 }
                }
            }
            function Receive-TelegramUpdates { return @($fakeUpdate) }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 5 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            $r.decision | Should Be "approve"
        }

        It "retorna decision=reject quando callback_query data=reject:GEM123" {
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $true; message_id = 42; was_photo = $false }
            }
            function Confirm-TgCallback { param($CallbackId, $Text, $Token) return $true }
            function Update-TgCaption   { param($MessageId, $Caption, $WasPhoto, $Token, $ChatId) return $true }
            $fakeUpdate = @{
                update_id = 1000
                callback_query = @{
                    id   = "CB2"
                    data = "reject:GEM123"
                    from = @{ first_name = "Thiago" }
                    message = @{ message_id = 42 }
                }
            }
            function Receive-TelegramUpdates { return @($fakeUpdate) }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 5 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            $r.decision | Should Be "reject"
        }

        It "ignora callback_query com GemId diferente (replay protection)" {
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $true; message_id = 42; was_photo = $false }
            }
            function Confirm-TgCallback { param($CallbackId, $Text, $Token) return $true }
            function Update-TgCaption   { param($MessageId, $Caption, $WasPhoto, $Token, $ChatId) return $true }
            $fakeUpdate = @{
                update_id = 1001
                callback_query = @{
                    id   = "CB3"
                    data = "approve:OUTRO_GEM"
                    from = @{ first_name = "Thiago" }
                    message = @{ message_id = 42 }
                }
            }
            function Receive-TelegramUpdates { return @($fakeUpdate) }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 1 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            # Deve ser timeout, nao approve, pois o id nao bate
            $r.decision | Should Be "timeout"
        }

        It "retorna decision=timeout quando nao recebe callback dentro do prazo" {
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $true; message_id = 42; was_photo = $false }
            }
            function Receive-TelegramUpdates { return @() }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 1 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            $r.decision | Should Be "timeout"
        }

        It "retorna from=first_name do callback_query.from" {
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $true; message_id = 42; was_photo = $false }
            }
            function Confirm-TgCallback { param($CallbackId, $Text, $Token) return $true }
            function Update-TgCaption   { param($MessageId, $Caption, $WasPhoto, $Token, $ChatId) return $true }
            $fakeUpdate = @{
                update_id = 1002
                callback_query = @{
                    id   = "CB4"
                    data = "approve:GEM123"
                    from = @{ first_name = "Thiago" }
                    message = @{ message_id = 42 }
                }
            }
            function Receive-TelegramUpdates { return @($fakeUpdate) }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 5 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            $r.from | Should Be "Thiago"
        }

        It "chama Confirm-TgCallback ao receber approve" {
            $script:confirmCalled = $false
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $true; message_id = 42; was_photo = $false }
            }
            function Confirm-TgCallback {
                param($CallbackId, $Text, $Token)
                $script:confirmCalled = $true
                return $true
            }
            function Update-TgCaption { param($MessageId, $Caption, $WasPhoto, $Token, $ChatId) return $true }
            $fakeUpdate = @{
                update_id = 1003
                callback_query = @{
                    id   = "CB5"
                    data = "approve:GEM123"
                    from = @{ first_name = "Thiago" }
                    message = @{ message_id = 42 }
                }
            }
            function Receive-TelegramUpdates { return @($fakeUpdate) }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 5 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            $script:confirmCalled | Should Be $true
        }

        It "chama Update-TgCaption ao receber approve" {
            $script:updateCalled = $false
            function Send-TgApprovalRequest {
                param($Gem, $GemId, $Token, $ChatId, $Enabled)
                return @{ ok = $true; message_id = 42; was_photo = $false }
            }
            function Confirm-TgCallback { param($CallbackId, $Text, $Token) return $true }
            function Update-TgCaption {
                param($MessageId, $Caption, $WasPhoto, $Token, $ChatId)
                $script:updateCalled = $true
                return $true
            }
            $fakeUpdate = @{
                update_id = 1004
                callback_query = @{
                    id   = "CB6"
                    data = "approve:GEM123"
                    from = @{ first_name = "Thiago" }
                    message = @{ message_id = 42 }
                }
            }
            function Receive-TelegramUpdates { return @($fakeUpdate) }
            $gem = New-FullGem
            $r = Wait-TgCallbackApproval -Gem $gem -GemId "GEM123" -TimeoutSeconds 5 -PollSeconds 1 -Token "tok" -ChatId "123" -Enabled "true"
            $script:updateCalled | Should Be $true
        }
    }
}
