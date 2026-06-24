require("addon")
local sampev = require("samp.events")
local ini = require("inicfg")
local requests = require("requests")
local json = require("cjson")
local math = require("math")
local os = require("os")

-- ================= GITHUB YANGILANISH SOZLAMALARI =================
local script_version = 1.2 
local script_name_file = "admin.lua" -- Yopilgan format nomi
local update_info_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/version.json"
local script_download_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/admin.lua"
-- ==================================================================

-- CONFIG.TXT DAN MA'LUMOTLARNI YUKLASH
local cfg = ini.load({
    settings = { 
        bot_name = "", 
        token = "", 
        chatid = "", 
        password = "", 
        openai_key = "" 
    },
    stats = {
        Dushanba = 0, Seshanba = 0, Chorshanba = 0,
        Payshanba = 0, Juma = 0, Shanba = 0, Yakshanba = 0,
        start_time = os.time(), daily_reports = 0, weekly_reports = 0
    }
}, "settings\\config.txt")

local bot_name = tostring(cfg.settings.bot_name):match("^%s*(.-)%s*$") or ""
local bot_token = tostring(cfg.settings.token):match("^%s*(.-)%s*$") or ""
local bot_chatid = tostring(cfg.settings.chatid):match("^%s*(.-)%s*$") or ""
local openai_key = tostring(cfg.settings.openai_key):match("^%s*(.-)%s*$") or ""

-- XOTIRA VA TIZIM O'ZGARUVCHILARI
local memory_file = "settings\\" .. bot_name:lower() .. "_memory.json"
local bot_memory = {}
local report_queue = {} 
local sp_queue = {} -- Shikoyatlar navbati
local is_spectating = false
local sp_timer = 0
local tg_capture_timer = nil 
local is_mp_active = false 
local ai_busy = false 
local is_logged_in = false 
local last_dialog_id = -1
local last_dialog_time = 0

function loadMemory()
    local f = io.open(memory_file, "r")
    if f then
        local data = f:read("*a")
        f:close()
        pcall(function() bot_memory = json.decode(data) end)
    end
end

function saveMemory()
    local f = io.open(memory_file, "w")
    if f then f:write(json.encode(bot_memory)); f:close() end
end

-- TELEGRAMGA XABAR YUBORISH
function sendTG(text)
    if bot_token == "" or bot_chatid == "" then return end
    local payload = { chat_id = bot_chatid, text = text, parse_mode = "Markdown" }
    local headers = {["Content-Type"] = "application/json"}
    newTask(function() pcall(function() requests.post("https://api.telegram.org/bot" .. bot_token .. "/sendMessage", {headers = headers, data = json.encode(payload), timeout = 2}) end) end)
end

-- GITHUB ORQALI AVTO-YANGILANISH
function checkUpdates()
    print("[UPDATE] Yangilanishlar tekshirilmoqda...")
    newTask(function()
        local success, response = pcall(function() return requests.get(update_info_url) end)
        if success and response and response.status_code == 200 then
            local data = json.decode(response.text)
            if data and data.version and tonumber(data.version) > script_version then
                print("[UPDATE] Yangi versiya topildi: v" .. data.version)
                sendTG("🔄 **Yangi versiya topildi!** (`v" .. data.version .. "`)\nYuklab olinmoqda...")
                
                local dl_success, dl_response = pcall(function() return requests.get(script_download_url) end)
                if dl_success and dl_response and dl_response.status_code == 200 then
                    local f = io.open(getWorkingDirectory() .. "\\scripts\\" .. script_name_file, "wb")
                    if f then
                        f:write(dl_response.text)
                        f:close()
                        print("[UPDATE] Muvaffaqiyatli yangilandi! RakSAMPni qayta ishga tushiring.")
                        sendTG("✅ **Bot yangilandi!** Skript yangi versiyaga o'tdi.")
                    end
                end
            end
        end
    end)
end

-- CHATGPT API ULANISH
function askChatGPT(system_prompt, user_text)
    if openai_key == "" or ai_busy then return nil end
    ai_busy = true
    local payload = { model = "gpt-3.5-turbo", messages = { {role = "system", content = system_prompt}, {role = "user", content = user_text} }, max_tokens = 80, temperature = 0.7 }
    local headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. openai_key }
    local success, response = pcall(function() return requests.post("https://api.openai.com/v1/chat/completions", {headers = headers, data = json.encode(payload), timeout = 5.0}) end)
    ai_busy = false
    if success and response and response.status_code == 200 then
        local data = json.decode(response.text)
        if data and data.choices and data.choices[1] and data.choices[1].message then
            return data.choices[1].message.content:gsub("\n", " ")
        end
    end
    return nil
end

-- TELEGRAM BUYRUQLARNI O'QISH
function telegramPolling()
    local update_id = 0
    newTask(function()
        while true do
            wait(2000) 
            local success, res = pcall(function() return requests.get("https://api.telegram.org/bot" .. bot_token .. "/getUpdates?offset=" .. (update_id + 1), {timeout = 2}) end)
            if success and res and res.status_code == 200 then
                local decoded = json.decode(res.text)
                if decoded.ok and #decoded.result > 0 then
                    for _, update in ipairs(decoded.result) do
                        update_id = update.update_id
                        if update.message and update.message.text and tostring(update.message.chat.id) == bot_chatid then
                            local txt = update.message.text
                            
                            if txt == "!cmd" then
                                local cmd_list = "🛠 **Mavjud buyruqlar:**\n" ..
                                                 "1️⃣ `!stats` - Bugungi boshqaruv vaqtini ko'rish\n" ..
                                                 "2️⃣ `!sp [id]` - Qo'lda kimnidir kuzatish\n" ..
                                                 "3️⃣ `!say [matn]` - O'yin chatiga xabar yozish\n" ..
                                                 "4️⃣ `!kick [id] [sabab]` - O'yinchini serverdan haydash\n" ..
                                                 "5️⃣ `!navbat` - SP navbatida nechta odam borligini ko'rish"
                                sendTG(cmd_list)
                            elseif txt == "!stats" then
                                sendTG("⏳ Ma'lumot serverdan olinmoqda...")
                                sendInput("/admins")
                            elseif txt:find("^!say%s+(.+)") then
                                local msg = txt:match("^!say%s+(.+)")
                                sendInput(msg)
                                sendTG("💬 Chatga yozildi: " .. msg)
                            elseif txt:find("^!sp%s+(%d+)") then
                                local id = txt:match("^!sp%s+(%d+)")
                                sendInput("/sp " .. id)
                                is_spectating = true
                                sp_timer = os.time()
                                sendTG("👁 " .. id .. " ID qo'lda kuzatuvga olindi.")
                            elseif txt:find("^!kick%s+(%d+)%s+(.+)") then
                                local id, reason = txt:match("^!kick%s+(%d+)%s+(.+)")
                                sendInput("/kick " .. id .. " " .. reason)
                                sendTG("👢 O'yinchi haydaldi: " .. id .. " | Sabab: " .. reason)
                            elseif txt == "!navbat" then
                                sendTG("📋 Hozirda kuzatuv navbatida " .. #sp_queue .. " ta o'yinchi bor.")
                            elseif txt:match("^/[%w_]+") then
                                sendInput(txt)
                                sendTG("⏳ Buyruq serverga yuborildi: `" .. txt .. "`")
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- SERVER XABARLARINI O'QISH
function sampev.onServerMessage(color, text)
    local clean = text:gsub("{......}", "")
    local lower_clean = clean:lower()

    -- 1. Boshqaruv vaqtini ushlash
    if clean:find("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa") then
        local daqiqa = clean:find("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa")
        sendTG("📊 Sizning bugungi boshqaruv vaqtingiz: " .. daqiqa .. " daqiqa.")
    end

    -- 2. Shikoyat kelganini aniqlash va navbatga yozish
    if clean:find("Shikoyat") and clean:find("ID:%s*(%d+)") then
        local target_id = clean:match("ID:%s*(%d+)")
        table.insert(sp_queue, target_id)
        sendTG("📝 Shikoyat qabul qilindi. " .. target_id .. " ID navbatga qo'shildi! (Navbatda: " .. #sp_queue .. ")")
    end

    -- 3. MP (Tadbirlar) holati
    if lower_clean:find("hozir mp bo'ladi") or lower_clean:find("mp boshlan") then
        is_mp_active = true; sendTG("📢 **MP Boshlandi!** Teleport ochildi.")
    elseif lower_clean:find("g'olib bo'lgan") then
        is_mp_active = false; sendTG("🛑 **MP Tugadi!** Teleport yopildi.")
    end

    -- 4. Admin Chat va AI Suhbat
    local adm_name, adm_text = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(.+)")
    if not adm_name then adm_name, adm_text = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(.+)") end

    if adm_name and adm_name ~= bot_name then
        local bot_short_name = bot_name:match("^(%w+)_"):lower()
        if adm_text:lower():find(bot_short_name) or adm_text:lower():find("azim") then 
            sendTG("💬 *Admin (" .. adm_name .. ") botga yozyapti:*\n_" .. adm_text .. "_") 
            newTask(function()
                wait(math.random(1500, 2500)) 
                local ai_reply = askChatGPT("Siz O'yindagi Admin chatida suhbatlashyapsiz. Qisqa javob bering.", adm_text)
                if ai_reply then sendInput("/a " .. ai_reply); sendTG("🤖 *Javob:* " .. ai_reply) end
            end)
        end
    end

    -- 5. Hisobotlarga javob berish
    if clean:find("%[Hisobotlar soni:") then
        local rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.-)%s*%[Hisobotlar")
        if not rep_id then rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.+)"); if rep_text then rep_text = rep_text:gsub("%[Hisobotlar.-%]", "") end end

        if rep_id and rep_text then
            local is_fast_plus = (rep_text:match("^[+%s]+$") ~= nil)
            if is_fast_plus then
                local final_reply = is_mp_active and "Assalomu alaykum, hozir teleport bo'lasiz" or "Assalomu alaykum, teleport yopiq"
                table.insert(report_queue, {id = rep_id, reply = final_reply, text = rep_text})
            else
                newTask(function()
                    wait(6000)
                    local final_reply = askChatGPT("SA-MP administratori sifatida javob bering", rep_text) or "Kuzatmoqdaman"
                    table.insert(report_queue, {id = rep_id, reply = final_reply, text = rep_text})
                end)
            end
        end
    end
end

-- ================= DIALOG VA SPAVN BOSHQARUVI =================
function sampev.onShowDialog(id, style, title, button1, button2, text)
    local clean_title = title:gsub("{......}", "")
    local lower_title = clean_title:lower()

    if id == last_dialog_id and (os.clock() - last_dialog_time) < 2.0 then return false end
    last_dialog_id = id; last_dialog_time = os.clock()

    if lower_title:find("xush") or lower_title:find("добро") or lower_title:find("yangilik") or lower_title:find("grand mobile") then
        sendDialogResponse(id, 1, 0, "")
        return false
    end

    if lower_title:find("avtorizatsiya") or lower_title:find("пароль") then 
        if cfg.settings.password == "" then print("[XATO] config.txt da parol yo'q!") end
        sendDialogResponse(id, 1, 0, cfg.settings.password)
        
        if not is_logged_in then
            is_logged_in = true
            newTask(function()
                wait(4000); spawn(); wait(2000); spawn(); wait(3000)
                sendInput("/az"); wait(1500)
                sendInput("/acceptgnews"); wait(1500)
                sendInput("/sp")
                sendTG("📰 O'yinga kirdi va avto-SP ga o'tdi.")
            end)
        end
        return false 
    end
end

function onConnectionClosed()
    is_logged_in = false 
    sendTG("❌ Bot serverdan uzildi.")
    newTask(function() wait(15000); connect(); sendTG("🟢 Qayta ulanmoqda..."); end)
end

function onLoad()
    loadMemory()
    telegramPolling()
    checkUpdates()
    
    -- AVTO-SP VA NAVBAT SIKLI
    newTask(function()
        while true do
            wait(1000) -- Har soniyada tekshiradi
            
            -- 1. Avto-SP Mantiqi
            if is_spectating then
                if os.time() - sp_timer >= 30 then
                    sendInput("/sp") 
                    is_spectating = false
                    sendTG("✅ 30 soniya o'tdi. Kuzatuvdan chiqildi.")
                end
            elseif #sp_queue > 0 then
                local target_id = table.remove(sp_queue, 1) 
                sendInput("/sp " .. target_id)
                is_spectating = true
                sp_timer = os.time()
                sendTG("👁 Avto-SP ishga tushdi: " .. target_id .. " ID kuzatilmoqda (30 soniya)...")
            end

            -- 2. Reportlarga javob berish navbati
            if #report_queue > 0 then
                local task = table.remove(report_queue, 1)
                sendInput("/ans " .. task.id .. " " .. task.reply)
                wait(500)
                sendInput("/re " .. task.id)
                sendTG("✅ **Javob Berildi:**\n❓ Savol: `" .. task.text .. "`\n🤖 Javob: `" .. task.reply .. "`")
                wait(1500)
            end
        end
    end)
    print("[BOT] " .. bot_name .. " 100% Ishga tushdi!") 
end
