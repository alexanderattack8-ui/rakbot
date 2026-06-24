-- === KOD BOSHLANISHI ===
require("addon")
local sampev = require("samp.events")
local ini = require("inicfg")
local requests = require("requests")
local json = require("cjson")
local math = require("math")
local os = require("os")

-- ================= GITHUB YANGILANISH SOZLAMALARI =================
local script_version = 1.3 
local script_name_file = "admin.lua" --[cite: 1]
local update_info_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/version.json" --[cite: 1]
local script_download_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/admin.lua" --[cite: 1]
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
        start_time = os.time()
    }
}, "settings\\config.txt") --[cite: 1]

-- O'ZGARUVCHILARNI CONFIGDAN AJRATIB OLISH
local bot_name = tostring(cfg.settings.bot_name):match("^%s*(.-)%s*$") or "" --[cite: 1]
local bot_token = tostring(cfg.settings.token):match("^%s*(.-)%s*$") or "" --[cite: 1]
local bot_chatid = tostring(cfg.settings.chatid):match("^%s*(.-)%s*$") or "" --[cite: 1]
local openai_key = tostring(cfg.settings.openai_key):match("^%s*(.-)%s*$") or "" --[cite: 1]

-- XOTIRA VA LUG'ATLAR
local memory_file = "settings\\" .. bot_name:lower() .. "_memory.json" --[cite: 1]
local bot_memory = {} --[cite: 1]
local pending_reports = {}  --[cite: 1]
local report_queue = {}  --[cite: 1]
local tg_capture_timer = nil  --[cite: 1]
local is_mp_active = false  --[cite: 1]
local ai_busy = false  --[cite: 1]
local is_logged_in = false  --[cite: 1]

local days_map = {
    Monday = "Dushanba", Tuesday = "Seshanba", Wednesday = "Chorshanba",
    Thursday = "Payshanba", Friday = "Juma", Saturday = "Shanba", Sunday = "Yakshanba"
} --[cite: 1]

local active_chat_admin = nil --[cite: 1]
local active_chat_time = 0 --[cite: 1]
local chat_timeout_seconds = 60  --[cite: 1]

local last_dialog_id = -1 --[cite: 1]
local last_dialog_time = 0 --[cite: 1]

function loadMemory()
    local f = io.open(memory_file, "r") --[cite: 1]
    if f then
        local data = f:read("*a") --[cite: 1]
        f:close() --[cite: 1]
        pcall(function() bot_memory = json.decode(data) end) --[cite: 1]
    end
end

function saveMemory()
    local f = io.open(memory_file, "w") --[cite: 1]
    if f then
        f:write(json.encode(bot_memory)) --[cite: 1]
        f:close() --[cite: 1]
    end
end

local red_admins = { ["Maga_By"] = true, ["Ivan_Vasilyev"] = true, ["John_Medvedev"] = true, ["Ace_Alonso"] = true } --[cite: 1]

local auto_replies = {
    ["qachon warn"] = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["warn qachon"] = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["qancha warn"] = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["yordam"] = "Assalomu aleykum, kuzatyapman.",
    ["tuzatib bering"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["remont"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["buzildi"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["tutayapti"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["nega qamadingiz"] = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["meni aybim yo'q"] = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["yeching"] = "Assalomu aleykum, administrator bunday jarayonlarga aralashmaydi.",
    ["sababsiz"] = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["pul bering"] = "Assalomu aleykum, keyingi off-top uchun jazo qo'llaniladi."
} --[cite: 1]

local is_wandering = false --[cite: 1]
local angle = 0 --[cite: 1]
local center_x, center_y = 0, 0 --[cite: 1]
local current_speed = 0.05  --[cite: 1]
local is_hiding = false  --[cite: 1]
local sleep_end_time = 0 --[cite: 1]
local last_punish_admin = nil --[cite: 1]
local last_punish_status = true --[cite: 1]
local checking_admins = false --[cite: 1]
local online_admins_table = {} --[cite: 1]
local current_stat_id = nil --[cite: 1]
local current_stat_time = "Noma'lum" --[cite: 1]

local allowed_cmds = {
    ["/ban"] = true, ["/offban"] = true, ["/warn"] = true, ["/offwarn"] = true,
    ["/kick"] = true, ["/mute"] = true, ["/rmute"] = true, ["/offmute"] = true,
    ["/unmute"] = true, ["/offunmute"] = true
} --[cite: 1]

function isRPNick(name) return string.match(name, "^%u%l+_%u%l+$") ~= nil end --[cite: 1]

function sendTG(text)
    if bot_token == "" or bot_chatid == "" then return end --[cite: 1]
    local payload = { chat_id = bot_chatid, text = text, parse_mode = "Markdown" } --[cite: 1]
    local headers = {["Content-Type"] = "application/json"} --[cite: 1]
    newTask(function() pcall(function() requests.post("https://api.telegram.org/bot" .. bot_token .. "/sendMessage", {headers = headers, data = json.encode(payload), timeout = 2}) end) end) --[cite: 1]
end

-- GITHUB ORQALI AVTO-YANGILANISH FUNKSIYASI (XATOLIK TO'G'RILANDI)
function checkUpdates()
    print("[UPDATE] Yangilanishlar tekshirilmoqda...") --[cite: 1]
    newTask(function()
        local success, response = pcall(function() return requests.get(update_info_url) end) --[cite: 1]
        
        if success and response and response.status_code == 200 then --[cite: 1]
            local data = json.decode(response.text) --[cite: 1]
            
            if data and data.version and tonumber(data.version) > script_version then --[cite: 1]
                print("[UPDATE] Yangi versiya topildi: v" .. data.version) --[cite: 1]
                print("[UPDATE] Skript yangilanmoqda, kutib turing...") --[cite: 1]
                sendTG("🔄 **Yangi versiya topildi!** (`v" .. data.version .. "`)\nYuklab olinmoqda...") --[cite: 1]
                
                local dl_success, dl_response = pcall(function() return requests.get(script_download_url) end) --[cite: 1]
                if dl_success and dl_response and dl_response.status_code == 200 then --[cite: 1]
                    -- XATO BERUVCHI getWorkingDirectory() OLIB TASHLANDI
                    local f = io.open("scripts\\" .. script_name_file, "w")
                    if f then
                        f:write(dl_response.text) --[cite: 1]
                        f:close() --[cite: 1]
                        print("[UPDATE] Muvaffaqiyatli yangilandi! RakSAMPni qayta ishga tushiring.") --[cite: 1]
                        sendTG("✅ **Bot yangilandi!** Skript yangi versiyaga o'tdi.") --[cite: 1]
                    end
                end
            else
                print("[UPDATE] Bot eng so'nggi versiyada ishlamoqda (v" .. script_version .. ").") --[cite: 1]
            end
        else
            print("[UPDATE XATO] GitHub bilan bog'lanib bo'lmadi.") --[cite: 1]
        end
    end)
end

function askChatGPT(system_prompt, user_text)
    if openai_key == "" or ai_busy then return nil end --[cite: 1]
    ai_busy = true --[cite: 1]
    
    local payload = {
        model = "gpt-3.5-turbo",
        messages = {
            {role = "system", content = system_prompt}, --[cite: 1]
            {role = "user", content = user_text} --[cite: 1]
        },
        max_tokens = 80, --[cite: 1]
        temperature = 0.7 --[cite: 1]
    }
    
    local headers = { 
        ["Content-Type"] = "application/json", --[cite: 1]
        ["Authorization"] = "Bearer " .. openai_key --[cite: 1]
    }
    
    local url = "https://api.openai.com/v1/chat/completions" --[cite: 1]
    
    local success, response = pcall(function() return requests.post(url, {headers = headers, data = json.encode(payload), timeout = 5.0}) end) --[cite: 1]
    ai_busy = false --[cite: 1]
    
    if success and response and response.status_code == 200 then --[cite: 1]
        local data = json.decode(response.text) --[cite: 1]
        if data and data.choices and data.choices[1] and data.choices[1].message then --[cite: 1]
            return data.choices[1].message.content:gsub("\n", " ") --[cite: 1]
        end
    end
    return nil --[cite: 1]
end

function getSmartReply(text)
    local lower_text = text:lower() --[cite: 1]
    if lower_text:find("rp") and (lower_text:find("nik") or lower_text:find("nick")) then --[cite: 1]
        local target_name = text:match("([%w_]+)%s+rp") or text:match("([%w_]+)") --[cite: 1]
        if target_name then --[cite: 1]
            if isRPNick(target_name) then return "Assalomu alaykum, ha, bu RP nik." --[cite: 1]
            else return "Assalomu alaykum, yo'q, bu Non-RP (NRP) nik." end --[cite: 1]
        end
    end
    for key, reply in pairs(auto_replies) do --[cite: 1]
        if lower_text:find(key, 1, true) then return reply end --[cite: 1]
    end
    for question, answer in pairs(bot_memory) do --[cite: 1]
        if lower_text:find(question, 1, true) or question:find(lower_text, 1, true) then return answer end --[cite: 1]
    end
    return nil  --[cite: 1]
end

function getAIChatReply(text)
    local ai_response = askChatGPT("Siz SA-MP o'yinida " .. bot_name .. " ismli hurmatli adminsiz. Tabiiy ohangda o'zbek tilida qisqa, bitta gap bilan javob qaytaring.", text) --[cite: 1]
    if ai_response then return ai_response end --[cite: 1]
    return "Xo'sh, eshitaman." --[cite: 1]
end

function spectateRandomPlayer()
    local players = {} --[cite: 1]
    for i = 0, 1000 do --[cite: 1]
        if i ~= getBotId() then --[cite: 1]
            local success, name = pcall(getPlayerName, i) --[cite: 1]
            if success and type(name) == "string" and name ~= "" and name ~= "Unknown" then --[cite: 1]
                local is_admin = false --[cite: 1]
                if red_admins[name] then is_admin = true end --[cite: 1]
                for _, adm in ipairs(online_admins_table) do --[cite: 1]
                    if tonumber(adm.id) == i or adm.name == name then --[cite: 1]
                        is_admin = true; break --[cite: 1]
                    end
                end
                if not is_admin then table.insert(players, i) end --[cite: 1]
            end
        end
    end
    if #players > 0 then sendInput("/sp " .. players[math.random(1, #players)]) --[cite: 1]
    else sendInput("/sp " .. (math.random(1, 50))) end --[cite: 1]
end

function telegramPolling()
    local update_id = 0 --[cite: 1]
    newTask(function()
        while true do --[cite: 1]
            wait(3000)  --[cite: 1]
            local success, res = pcall(function() return requests.get("https://api.telegram.org/bot" .. bot_token .. "/getUpdates?offset=" .. (update_id + 1), {timeout = 2}) end) --[cite: 1]
            if success and res and res.status_code == 200 then --[cite: 1]
                local decoded = json.decode(res.text) --[cite: 1]
                if decoded.ok and #decoded.result > 0 then --[cite: 1]
                    for _, update in ipairs(decoded.result) do --[cite: 1]
                        update_id = update.update_id --[cite: 1]
                        if update.message and update.message.text and tostring(update.message.chat.id) == bot_chatid then --[cite: 1]
                            local txt = update.message.text --[cite: 1]
                            if txt:match("^/[%w_]+") then --[cite: 1]
                                sendInput(txt); sendTG("⏳ Buyruq serverga yuborildi:\n`" .. txt .. "`\n*Javob kutilmoqda...*"); tg_capture_timer = os.clock() + 3.0  --[cite: 1]
                            elseif txt:lower() == "!cmd" then  --[cite: 1]
                                sendTG("🤖 **" .. bot_name .. " - MENYU** 🤖\n\n📊 `/stats` - Ish hisobotlari\n👥 `!admins` - Onlayn adminlar\n📍 `!loc` - Bot joylashuvi\n💬 `!a [matn]` - Admin chatga yozish\n📢 `!say [matn]` - Oddiy chatga yozish\n🛌 `!pause [daq]` - O'yindan chiqish\n🟢 `!wake` - Serverga ulanish\n▶️ `!resume` - Qayta ishlash") --[cite: 1]
                            elseif txt:lower() == "!admins" then --[cite: 1]
                                checking_admins = true; online_admins_table = {}; sendInput("/admins"); sendTG("🔍 Adminlar ro'yxati olinmoqda...") --[cite: 1]
                                newTask(function()
                                    wait(2000); checking_admins = false --[cite: 1]
                                    if #online_admins_table == 0 then sendTG("❌ Adminlar topilmadi.") --[cite: 1]
                                    else
                                        local final_list = "👥 **Serverdagi Adminlar:**\n\n" --[cite: 1]
                                        for i, adm in ipairs(online_admins_table) do --[cite: 1]
                                            current_stat_id = adm.id; current_stat_time = "0 daqiqa"; sendInput("/stats " .. adm.id); wait(1500)  --[cite: 1]
                                            final_list = final_list .. "👤 " .. adm.name .. " [" .. adm.id .. "] - " .. adm.lvl .. " daraja | ⏱ " .. current_stat_time .. "\n" --[cite: 1]
                                        end
                                        current_stat_id = nil; final_list = final_list .. "\n📊 Jami onlayn: " .. #online_admins_table .. " ta"; sendTG(final_list) --[cite: 1]
                                    end
                                end)
                            elseif txt:lower() == "/stats" or txt:lower() == "!stats" then --[cite: 1]
                                local uptime = math.floor((os.time() - cfg.stats.start_time) / 3600) --[cite: 1]
                                sendTG("📊 **KUNLIK VA HAFTALIK HISOBOT:**\n\nDu: `" .. cfg.stats.Dushanba .. "` | Se: `" .. cfg.stats.Seshanba .. "` | Ch: `" .. cfg.stats.Chorshanba .. "`\nPa: `" .. cfg.stats.Payshanba .. "` | Ju: `" .. cfg.stats.Juma .. "` | Sh: `" .. cfg.stats.Shanba .. "` | Ya: `" .. cfg.stats.Yakshanba .. "`\n\n⏱ **Uptime:** `" .. uptime .. " soat`") --[cite: 1]
                            elseif txt:lower() == "!loc" then --[cite: 1]
                                local bx, by, bz = getBotPosition() --[cite: 1]
                                if bx then sendTG("📍 **Joylashuv:**\nX: `" .. string.format("%.2f", bx) .. "`\nY: `" .. string.format("%.2f", by) .. "`") end --[cite: 1]
                            elseif txt:match("^!a%s+(.+)") then sendInput("/a " .. txt:match("!a%s+(.+)")) --[cite: 1]
                            elseif txt:match("^!say%s+(.+)") then sendInput(txt:match("!say%s+(.+)")) --[cite: 1]
                            elseif txt:lower() == "!resume" then is_hiding = false; is_wandering = true; sendTG("▶️ Bot ishga qaytdi.") --[cite: 1]
                            elseif txt:match("^!pause%s+(%d+)") then --[cite: 1]
                                local mins = tonumber(txt:match("^!pause%s+(%d+)")); sleep_end_time = os.time() + (mins * 60); disconnect(); is_wandering = false; sendTG("🛌 Bot " .. mins .. " daqiqaga o'yindan chiqdi.") --[cite: 1]
                                newTask(function() while os.time() < sleep_end_time do wait(1000) end; if sleep_end_time ~= 0 then sleep_end_time = 0; connect(); sendTG("🟢 Ulanmoqda...") end end) --[cite: 1]
                            elseif txt:lower() == "!wake" then --[cite: 1]
                                if sleep_end_time ~= 0 then sleep_end_time = 0; connect(); sendTG("🟢 Bot ulanmoqda..."); end --[cite: 1]
                            end
                        end
                    end
                end
            end
        end
    end)
end

function sampev.onSendPlayerSync(data)
    if is_hiding then return end --[cite: 1]
    if is_wandering then --[cite: 1]
        data.keysData = 1 --[cite: 1]
        if math.random(1, 100) > 95 then current_speed = (current_speed == 0.05) and 0.15 or 0.05; angle = angle + (math.random() - 0.5) end --[cite: 1]
        local bx, by, bz = getBotPosition() --[cite: 1]
        if bx then --[cite: 1]
            local dist = math.sqrt((bx - center_x)^2 + (by - center_y)^2) --[cite: 1]
            if dist > 15 then angle = math.atan2(center_y - by, center_x - bx) end --[cite: 1]
            data.position.x = bx + math.cos(angle) * current_speed --[cite: 1]
            data.position.y = by + math.sin(angle) * current_speed --[cite: 1]
            setBotPosition(data.position.x, data.position.y, bz) --[cite: 1]
        end
        return {data} --[cite: 1]
    end
end

function sampev.onServerMessage(color, text)
    local clean = text:gsub("{......}", "") --[cite: 1]
    local lower_clean = clean:lower() --[cite: 1]

    if tg_capture_timer and os.clock() <= tg_capture_timer then --[cite: 1]
        if not clean:match("%[%d+%]:") and not clean:match("SMS:") and not clean:match("yozdi:") then --[cite: 1]
            sendTG("📩 **Server:**\n`" .. clean .. "`"); tg_capture_timer = nil  --[cite: 1]
        end
    end

    if lower_clean:find("hozir mp bo'ladi") or lower_clean:find("hozir mp boladi") or lower_clean:find("mp boshlan") or lower_clean:find("ishtirok etish uchun hisobotingizga") then --[cite: 1]
        is_mp_active = true; sendTG("📢 **MP Boshlandi!** Teleport ochildi.") --[cite: 1]
    elseif lower_clean:find("g'olib bo'lgan") or lower_clean:find("go'lib bolgan") or lower_clean:find("g'olib bolgan") or lower_clean:find("golib bolgan") then --[cite: 1]
        is_mp_active = false; sendTG("🛑 **MP Tugadi!** Teleport yopildi.") --[cite: 1]
    end

    if checking_admins then --[cite: 1]
        local admin_name, admin_id, admin_lvl = clean:match("([%a_]+)%[(%d+)%]%s*|%s*(%d+)%s*darajasi") --[cite: 1]
        if admin_name then table.insert(online_admins_table, {name = admin_name, id = admin_id, lvl = admin_lvl}) end --[cite: 1]
    end

    if current_stat_id then --[cite: 1]
        local ptime = clean:match("vaqti:%s*(%d+)%s*daqiqa") or clean:match("vaqti:%s*(%d+)") or clean:match("(%d+)%s*daqiqa") --[cite: 1]
        if ptime then current_stat_time = ptime .. " daqiqa" end --[cite: 1]
    end

    if last_punish_admin and (lower_clean:find("topilmadi") or lower_clean:find("bunday") or lower_clean:find("mavjud emas")) then --[cite: 1]
        last_punish_status = false  --[cite: 1]
        newTask(function() wait(500); sendInput("/a " .. last_punish_admin .. ", bunday id/nick topilmadi!"); sendTG("❌ Xato: " .. last_punish_admin .. " so'ragan o'yinchi topilmadi."); last_punish_admin = nil end) --[cite: 1]
    end

    local a_name, a_cmd, a_args = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(/[%a]+)%s+(.+)") --[cite: 1]
    if not a_name then a_name, a_cmd, a_args = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(/[%a]+)%s+(.+)") end --[cite: 1]
    
    if a_name and a_cmd and allowed_cmds[a_cmd:lower()] then --[cite: 1]
        local first_letter, last_name = a_name:match("^(%a)%a+_(%a+)$") --[cite: 1]
        if first_letter and last_name then --[cite: 1]
            last_punish_admin = first_letter .. "." .. last_name; last_punish_status = true --[cite: 1]
            newTask(function()
                wait(1500); sendInput(a_cmd .. " " .. a_args .. " // " .. last_punish_admin); wait(1500)  --[cite: 1]
                if last_punish_status then sendInput("/a +"); sendTG("🔨 Jazo berildi:\n`" .. a_cmd .. " " .. a_args .. "`"); last_punish_admin = nil end --[cite: 1]
            end)
        end
    end

    local adm_name, adm_text = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(.+)") --[cite: 1]
    if not adm_name then adm_name, adm_text = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(.+)") end --[cite: 1]

    if adm_name and adm_name ~= bot_name and not red_admins[adm_name] then --[cite: 1]
        if adm_text and not allowed_cmds[adm_text:match("^(%S+)")] then  --[cite: 1]
            local lower_text = adm_text:lower() --[cite: 1]
            local is_talking_to_me = false --[cite: 1]
            
            local bot_short_name = bot_name:match("^(%w+)_"):lower() --[cite: 1]
            if lower_text:find(bot_short_name) or lower_text:find("azim") or lower_text:find("asilbek") or lower_text:find("aslbek") then  --[cite: 1]
                is_talking_to_me = true --[cite: 1]
            elseif active_chat_admin == adm_name and (os.time() - active_chat_time) <= chat_timeout_seconds then  --[cite: 1]
                is_talking_to_me = true  --[cite: 1]
            end

            if is_talking_to_me then --[cite: 1]
                active_chat_admin = adm_name; active_chat_time = os.time(); sendTG("💬 *Admin (" .. adm_name .. ") botga yozyapti:*\n_" .. adm_text .. "_")  --[cite: 1]
                newTask(function()
                    wait(math.random(1500, 2500))  --[cite: 1]
                    local ai_reply = getAIChatReply("Siz O'yindagi Admin chatida suhbatlashyapsiz. " .. adm_name .. " ismli admin sizga yozdi: " .. adm_text) --[cite: 1]
                    if ai_reply then --[cite: 1]
                        sendInput("/a " .. ai_reply); sendTG("🤖 *Javob berildi:*\n_" .. ai_reply .. "_") --[cite: 1]
                    end
                end)
            end
        end
    end

    if clean:match("^SMS") or clean:match("yozdi:") then  --[cite: 1]
        local sender_name, sender_id = clean:match("(%a+_%a+)%[(%d+)%]") --[cite: 1]
        if sender_name and sender_id and isRPNick(sender_name) and not red_admins[sender_name] and sender_name ~= bot_name then --[cite: 1]
            sendTG("✉️ *Sizga SMS (" .. sender_name .. "):*\n_" .. clean .. "_")  --[cite: 1]
            newTask(function()
                local user_msg = clean:gsub(sender_name .. "%[%d+%]", ""):gsub("SMS:", ""):gsub("yozdi:", "") --[cite: 1]
                wait(math.random(2000, 4000))  --[cite: 1]
                local ai_reply = getAIChatReply("Sizga o'yinchi shunday SMS yozdi: " .. user_msg) --[cite: 1]
                if ai_reply then sendInput("/pm " .. sender_id .. " " .. ai_reply) end --[cite: 1]
            end)
        end
    end

    if clean:match("^(%a+_%a+)%[%d+%]:") and red_admins[clean:match("^(%a+_%a+)%[%d+%]:")] then sendTG("🔴 Qizil admin (" .. clean:match("^(%a+_%a+)%[%d+%]:") .. ") chatda yozdi!") end --[cite: 1]

    local target_id, admin_ans = clean:match("<ADM>.-%[%d+%]%s+.-%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)")  --[cite: 1]
    if target_id and admin_ans then --[cite: 1]
        target_id = tostring(target_id) --[cite: 1]
        if pending_reports[target_id] then --[cite: 1]
            bot_memory[pending_reports[target_id]:lower()] = admin_ans; saveMemory() --[cite: 1]
            sendTG("🧠 **O'rgandim!**\nSavol: `" .. pending_reports[target_id] .. "`\nJavob: `" .. admin_ans .. "`") --[cite: 1]
        end
    end

    if clean:find("%[Hisobotlar soni:") then --[cite: 1]
        local rep_name = clean:match("([%a_]+)%[%d+%]:") --[cite: 1]
        local rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.-)%s*%[Hisobotlar") --[cite: 1]
        
        if not rep_id then rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.+)"); if rep_text then rep_text = rep_text:gsub("%[Hisobotlar.-%]", "") end end --[cite: 1]

        if rep_id and rep_text then --[cite: 1]
            rep_name = rep_name or "Noma'lum" --[cite: 1]
            rep_id = tostring(rep_id) --[cite: 1]
            local lower_rep = rep_text:lower():match("^%s*(.-)%s*$") --[cite: 1]
            local is_fast_plus = (lower_rep:match("^[+%s]+$") ~= nil) --[cite: 1]

            if lower_rep:find("ag'dar") or lower_rep:find("to'ntar") then newTask(function() wait(1500); sendInput("/flip " .. rep_id) end) end --[cite: 1]
            if lower_rep:find("remont") or lower_rep:find("buzildi") or lower_rep:find("fix") then newTask(function() wait(2000); if math.random(1, 100) <= 50 then sendInput("/fixcar " .. rep_id) end end) end --[cite: 1]
            
            if is_fast_plus then --[cite: 1]
                if is_mp_active then --[cite: 1]
                    local final_reply = "Assalomu alaykum, hozir teleport bo'lasiz" --[cite: 1]
                    table.insert(report_queue, 1, {id = rep_id, reply = final_reply, name = rep_name, text = rep_text}) --[cite: 1]
                else
                    newTask(function()
                        wait(6000) --[cite: 1]
                        local final_reply = "Assalomu alaykum, teleport yopiq" --[cite: 1]
                        table.insert(report_queue, {id = rep_id, reply = final_reply, name = rep_name, text = rep_text}) --[cite: 1]
                    end)
                end
            else
                newTask(function()
                    wait(6000) --[cite: 1]
                    local final_reply = getSmartReply(rep_text) --[cite: 1]
                    if not final_reply then --[cite: 1]
                        final_reply = askChatGPT("Siz SA-MP server administratori sifatida o'yinchining savoliga qisqa va aniq javob bering.", rep_text) --[cite: 1]
                        if not final_reply or final_reply == "" then final_reply = "Assalomu Alaykum, sizni kuzatmoqdaman" end --[cite: 1]
                    end
                    table.insert(report_queue, {id = rep_id, reply = final_reply, name = rep_name, text = rep_text}) --[cite: 1]
                end)
            end
        end
    end

    if clean:find("yangiliklari uchun ariza paydo bo'ldi") and clean:find("/acceptgnews") then --[cite: 1]
        newTask(function() wait(1000); sendInput("/acceptgnews"); sendTG("✅ Yangiliklar arizasi tasdiqlandi!") end) --[cite: 1]
    end
end

-- ================= DIALOG VA SPAVN BOSHQARUVI =================
function sampev.onShowDialog(id, style, title, button1, button2, text)
    local clean_title = title:gsub("{......}", "") --[cite: 1]
    local clean_text = text:gsub("{......}", "") --[cite: 1]
    local lower_title = clean_title:lower() --[cite: 1]
    local lower_text = clean_text:lower() --[cite: 1]

    print("\n--- DIALOG KELDI ---") --[cite: 1]
    print("ID: " .. id .. " | Sarlavha: " .. clean_title) --[cite: 1]

    if id == last_dialog_id and (os.clock() - last_dialog_time) < 2.0 then return false end --[cite: 1]
    last_dialog_id = id --[cite: 1]
    last_dialog_time = os.clock() --[cite: 1]

    if lower_title:find("xush") or lower_title:find("добро") or lower_title:find("yangilik") or lower_title:find("новости") or lower_title:find("grand mobile") then --[cite: 1]
        print("[BOT] Info oyna yopildi.") --[cite: 1]
        sendDialogResponse(id, 1, 0, "") --[cite: 1]
        return false --[cite: 1]
    end

    if lower_title:find("avtorizatsiya") or lower_title:find("пароль") then  --[cite: 1]
        print("[BOT] Parol yuborilmoqda...") --[cite: 1]
        
        if cfg.settings.password == "" then --[cite: 1]
            print("[XATO] config.txt da parol yo'q! Bot o'yinga kirmasligi mumkin.") --[cite: 1]
        end
        
        sendDialogResponse(id, 1, 0, cfg.settings.password) --[cite: 1]
        
        if not is_logged_in then --[cite: 1]
            is_logged_in = true --[cite: 1]
            newTask(function()
                wait(4000)  --[cite: 1]
                print("[BOT] 1-Spavn so'rovi...") --[cite: 1]
                spawn() --[cite: 1]
                wait(2000) --[cite: 1]
                
                print("[BOT] 2-Spavn so'rovi...") --[cite: 1]
                spawn()  --[cite: 1]
                wait(3000) --[cite: 1]

                sendInput("/az") --[cite: 1]
                wait(1500) --[cite: 1]
                sendInput("/acceptgnews") --[cite: 1]
                wait(1500) --[cite: 1]
                
                sendInput("/sp") --[cite: 1]
                print("[BOT] Avtomatik kuzatuv (SP) rejimiga o'tildi.") --[cite: 1]
                
                sendTG("📰 O'yinga kirdi va avto-SP ga o'tdi.") --[cite: 1]
                
                is_wandering = true  --[cite: 1]
            end)
        end
        return false  --[cite: 1]
    end
    
    if clean_title:find("Arizani tasdiqlash") then  --[cite: 1]
        local auth_code = clean_text:match("kalitni kiriting:%s*(%d%d%d%d)") --[cite: 1]
        if auth_code then sendDialogResponse(id, 1, 0, auth_code); return false end  --[cite: 1]
    end
    
    local code = text:match("(%d%d%d%d%d)")  --[cite: 1]
    if code and not current_stat_id and not clean_title:find("Arizani tasdiqlash") then  --[cite: 1]
        sendDialogResponse(id, 1, 0, code); return false  --[cite: 1]
    end
    
    if current_stat_id then sendDialogResponse(id, 0, 0, ""); return false end --[cite: 1]
end

function onConnectionClosed()
    is_wandering = false --[cite: 1]
    is_logged_in = false  --[cite: 1]
    sendTG("❌ Bot serverdan uzildi.") --[cite: 1]
    newTask(function() wait(15000); connect(); sendTG("🟢 Qayta ulanmoqda..."); end) --[cite: 1]
end

function onExit()
    ini.save(cfg, "settings\\config.txt") --[cite: 1]
end

function onLoad()
    if isRPNick(bot_name) then  --[cite: 1]
        loadMemory() --[cite: 1]
        telegramPolling() --[cite: 1]
        checkUpdates() --[cite: 1]
        
        newTask(function()
            while true do --[cite: 1]
                if #report_queue > 0 then --[cite: 1]
                    local task = table.remove(report_queue, 1) --[cite: 1]
                    sendInput("/ans " .. task.id .. " " .. task.reply) --[cite: 1]
                    
                    local today_str = days_map[os.date("%A")] or "Dushanba" --[cite: 1]
                    cfg.stats[today_str] = (tonumber(cfg.stats[today_str]) or 0) + 1 --[cite: 1]
                    ini.save(cfg, "settings\\config.txt") --[cite: 1]
                    
                    wait(500) --[cite: 1]
                    sendInput("/re " .. task.id) --[cite: 1]
                    sendTG("✅ **Javob Berildi:**\n👤 O'yinchi: `" .. task.name .. " [" .. task.id .. "]`\n❓ Savol: `" .. task.text .. "`\n🤖 Bot Javobi: `" .. task.reply .. "`") --[cite: 1]
                    wait(1500) --[cite: 1]
                else
                    wait(500) --[cite: 1]
                end
            end
        end)
        
        print("[BOT] " .. bot_name .. " 100% Ishga tushdi!")  --[cite: 1]
    else 
        print("[XATO] Botingiz nomi " .. bot_name .. " emas! Ismni o'zgartiring.")  --[cite: 1]
    end
end
-- === KOD TUGASHI ===
