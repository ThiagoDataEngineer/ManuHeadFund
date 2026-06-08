# 📱 Telegram Setup Guide — GEM STRATEGIES Alerts

**Status**: ⚠️ Setup Required  
**Library**: `lib_telegram_alerts_simple.ps1`  
**Date**: 2026-06-09

---

## 🚀 QUICK SETUP (2 minutos)

### **Step 1: Create Bot via @BotFather**

1. Open Telegram
2. Search for `@BotFather`
3. Send `/start`
4. Send `/newbot`
5. Name your bot: `ManuHeadFundBot` (or custom)
6. Get Bot Token (copy it!)

**Result**: Token like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`

---

### **Step 2: Get Your Chat ID**

1. Search for bot you just created
2. Send `/start`
3. Go to: `https://api.telegram.org/bot[YOUR_BOT_TOKEN]/getUpdates`
   - Replace `[YOUR_BOT_TOKEN]` with your token
4. Find `"chat":{"id":XXXXX...}`
5. Copy your Chat ID

**Result**: Number like `123456789`

---

### **Step 3: Configure in PowerShell**

```powershell
cd "c:\Users\thiag\Coinex_AI_USER_API"

# Load library
. agents/lib_telegram_alerts_simple.ps1

# Configure (use YOUR values!)
Set-TelegramConfig `
    -BotToken "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" `
    -ChatId "123456789"

# Test
Send-TelegramAlert -Message "✅ Telegram is working!" -Type "SUCCESS"
```

**You should receive message on Telegram!** ✅

---

## 📋 INTEGRATION

Once configured, GEM STRATEGIES will send alerts automatically:

```powershell
# In lib_gem_router.ps1 (already integrated)
Send-TelegramTrade -Market "PEPOUSDT" -Strategy "PULL_BACK" -EntryPrice 0.0002 -Target 0.0006

Send-TelegramClose -Market "PEPOUSDT" -PnL 150 -Reason "TP Hit"
```

---

## 🧪 TEST COMMANDS

```powershell
# Test connection
Send-TelegramAlert -Message "Test INFO" -Type "INFO"
Send-TelegramAlert -Message "Test SUCCESS" -Type "SUCCESS"  
Send-TelegramAlert -Message "Test WARNING" -Type "WARNING"
Send-TelegramAlert -Message "Test ERROR" -Type "ERROR"

# Simulate trade open
Send-TelegramTrade -Market "BTCUSDT" -Strategy "PULL_BACK_RECOVERY" `
    -EntryPrice 50000 -Target 60000

# Simulate trade close  
Send-TelegramClose -Market "BTCUSDT" -PnL 2000 -Reason "TP Hit"

# Check status
Show-TelegramStatus
```

---

## ✅ WHAT YOU'LL RECEIVE

Once GEM STRATEGIES finds a trade:

```
📈 TRADE OPENED

Market: PEPOUSDT
Strategy: PULL_BACK_RECOVERY
Entry: $0.00002150
Target: $0.00064500

Time: 14:35:22
```

```
✅ TRADE CLOSED

Market: PEPOUSDT
PnL: $125.50
Reason: TP Hit

Time: 15:47:33
```

---

## 🆘 TROUBLESHOOTING

### **"Bot not responding"**
- Check Bot Token is correct
- Check Chat ID is correct
- Bot must be added to chat first (send `/start` to bot)

### **"Invalid token"**
- Copy token directly from @BotFather
- Don't add extra spaces

### **"Chat ID not found"**
- Make sure you sent message to your bot first
- Try: `https://api.telegram.org/bot[TOKEN]/getUpdates`

---

## 📱 YOUR BOT TOKEN (Save This!)

```
Bot Name: ________________
Bot Token: ________________
Chat ID: ________________
```

---

## 🔗 NEXT STEPS

1. ✅ Create bot via @BotFather
2. ✅ Get token + chat ID
3. ✅ Configure in PowerShell
4. ✅ Test with Send-TelegramAlert
5. ✅ System will send alerts automatically

---

**Once setup: You'll get Telegram alerts for EVERY trade!** 🚀

