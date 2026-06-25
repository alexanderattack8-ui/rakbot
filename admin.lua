-- === KOD BOSHLANISHI ===
require("addon")
local sampev = require("samp.events")
local ini = require("inicfg")
local requests = require("requests")
local json = require("cjson")
local math = require("math")
local os = require("os")

-- ================= GITHUB YANGILANISH SOZLAMALARI =================
local script_version = 2.1 
local script_name_file = "admin.lua" 
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
        start_time = os.time()
    }
}, "settings\\config.txt")

-- O'ZGARUVCHILARNI CONFIGDAN AJRATIB OLISH
local bot_name = tostring(cfg.settings.bot_name):match("^%s*(.-)%s*$") or ""
local bot_token = tostring(cfg.settings.token):match("^%s*(.-)%s*$") or ""
local bot_chatid = tostring(cfg.settings.chatid):match("^%s*(.-)%s*$") or ""
local openai_key = tostring(cfg.settings.openai_key):match("^%s*(.-)%s*$") or ""

-- XOTIRA VA LUG'ATLAR
local memory_file = "settings\\" .. bot_name:lower() .. "_memory.json"
local bot_memory = {}
local pending_reports = {} 
local report_queue = {} 
local sp_queue = {} 
local is_spectating = false
local sp_timer = 0
local tg_capture_timer = nil 
local is_mp_active = false 
local ai_busy = false 
local is_logged_in = false 

local days_map = {
    Monday = "Dushanba", Tuesday = "Seshanba", Wednesday = "Chorshanba",
    Thursday = "Payshanba", Friday = "Juma", Saturday = "Shanba", Sunday = "Yakshanba"
}

local active_chat_admin = nil
local active_chat_time = 0
local chat_timeout_seconds = 60 

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
    if f then
        f:write(json.encode(bot_memory))
        f:close()
    end
end

local red_admins = { ["Maga_By"] = true, ["Ivan_Vasilyev"] = true, ["John_Medvedev"] = true, ["Ace_Alonso"] = true }

-- KALIT SO'ZLAR (LUG'AT) BOYITILDI
local auto_replies = {
    ["qachon warn"] = "Assalomu alaykum, statisika orqali ko'rishingiz mumkun.",
    ["warn qachon"] = "Assalomu alaykum, statisika orqali ko'rishingiz mumkun.",
    ["qancha warn"] = "Assalomu alaykum, statisika orqali ko'rishingiz mumkun.",
    ["yordam"] = "Assalomu aleykum, kuzatyapman.",
    ["tuzatib bering"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["remont"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["buzildi"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["tutayapti"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["chin"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["pochinit"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["moshinam"] = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["nega qamadingiz"] = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["meni aybim yo'q"] = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["yeching"] = "Assalomu aleykum, administrator bunday jarayonlarga aralashmaydi.",
    ["sababsiz"] = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["pul bering"] = "Assalomu aleykum, keyingi off-top uchun jazo qo'llaniladi.",
    ["qayerda"] = "Assalomu alaykum, planshet Planshet orqali qidirib topishingiz mumkin.",
    ["topib ber"] = "Assalomu alaykum, planshet Planshet orqali qidirib topishingiz mumkin.",
	["kishan", "bog'lab"] = "Assalomu aleykum, administrator bunday jarayonlarga aralashmaydi."
	
}

local is_wandering = false
local angle = 0
local center_x, center_y = 0, 0
local current_speed = 0.05 
local is_hiding = false 
local sleep_end_time = 0
local last_punish_admin = nil
local last_punish_status = true
local checking_admins = false
local online_admins_table = {}
local current_stat_id = nil
local current_stat_time = "Noma'lum"

local allowed_cmds = {
    ["/ban"] = true, ["/offban"] = true, ["/warn"] = true, ["/offwarn"] = true,
    ["/kick"] = true, ["/mute"] = true, ["/rmute"] = true, ["/offmute"] = true,
    ["/unmute"] = true, ["/offunmute"] = true
}

function isRPNick(name) return string.match(name, "^%u%a+_%u%a+$") ~= nil end

function sendTG(text)
    if bot_token == "" or bot_chatid == "" then return end
    local payload = { chat_id = bot_chatid, text = text, parse_mode = "Markdown" }
    local headers = {["Content-Type"] = "application/json"}
    newTask(function() pcall(function() requests.post("https://api.telegram.org/bot" .. bot_token .. "/sendMessage", {headers = headers, data = json.encode(payload), timeout = 3}) end) end)
end

function checkUpdates()
    print("[UPDATE] Yangilanishlar tekshirilmoqda...")
    newTask(function()
        local success, response = pcall(function() return requests.get(update_info_url, {timeout = 5}) end)
        if success and response and response.status_code == 200 then
            local data = json.decode(response.text)
            if data and data.version and tonumber(data.version) > script_version then
                print("[UPDATE] Yangi versiya topildi: v" .. data.version)
                sendTG("🔄 **Yangi versiya topildi!** (`v" .. data.version .. "`)\nYuklab olinmoqda...")
                
                local dl_success, dl_response = pcall(function() return requests.get(script_download_url, {timeout = 10}) end)
                if dl_success and dl_response and dl_response.status_code == 200 then
                    local f = io.open("scripts\\temp_update.lua", "w")
                    if f then
                        f:write(dl_response.text)
                        f:close()
                        os.remove("scripts\\" .. script_name_file)
                        os.rename("scripts\\temp_update.lua", "scripts\\" .. script_name_file)
                        print("[UPDATE] Muvaffaqiyatli yangilandi! RakSAMPni qayta ishga tushiring.")
                        sendTG("✅ **Bot yangilandi!** Skript yangi versiyaga o'tdi.")
                    end
                end
            else
                print("[UPDATE] Bot eng so'nggi versiyada ishlamoqda (v" .. script_version .. ").")
            end
        else
            print("[UPDATE XATO] GitHub bilan bog'lanib bo'lmadi.")
        end
    end)
end

function askChatGPT(system_prompt, user_text)
    if openai_key == "" or ai_busy then return nil end
    ai_busy = true
    local payload = { model = "gpt-3.5-turbo", messages = { {role = "system", content = system_prompt}, {role = "user", content = user_text} }, max_tokens = 80, temperature = 0.5 }
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

function getSmartReply(text, sender_name)
    local lower_text = text:lower()
    if lower_text:find("rp") and (lower_text:find("nik") or lower_text:find("nick")) then
        local target_name = text:match("(%u%a+_%u%a+)") or sender_name
        if target_name then
            if isRPNick(target_name) then return "Assalomu alaykum, ha, bu RP nik."
            else return "Assalomu alaykum, yo'q, bu Non-RP (NRP) nik." end
        end
    end
    for key, reply in pairs(auto_replies) do
        if lower_text:find(key, 1, true) then return reply end
    end
    for question, answer in pairs(bot_memory) do
        if lower_text:find(question, 1, true) or question:find(lower_text, 1, true) then return answer end
    end
    return nil 
end

function getAIChatReply(text)
    local ai_response = askChatGPT("Siz SA-MP o'yinida " .. bot_name .. " ismli hurmatli adminsiz. Tabiiy ohangda o'zbek tilida qisqa, bitta gap bilan javob qaytaring.", text)
    if ai_response then return ai_response end
    return "Xo'sh, eshitaman."
end

function spectateRandomPlayer()
    local players = {}
    for i = 0, 1000 do
        if i ~= getBotId() then
            local success, name = pcall(getPlayerName, i)
            if success and type(name) == "string" and name ~= "" and name ~= "Unknown" then
                local is_admin = false
                if red_admins[name] then is_admin = true end
                for _, adm in ipairs(online_admins_table) do
                    if tonumber(adm.id) == i or adm.name == name then is_admin = true; break end
                end
                if not is_admin then table.insert(players, i) end
            end
        end
    end
    if #players > 0 then sendInput("/sp " .. players[math.random(1, #players)])
    else sendInput("/sp " .. (math.random(1, 50))) end
end

function telegramPolling()
    local update_id = 0
    newTask(function()
        while true do
            wait(3000) 
            local success, res = pcall(function() return requests.get("https://api.telegram.org/bot" .. bot_token .. "/getUpdates?offset=" .. (update_id + 1), {timeout = 2}) end)
            if success and res and res.status_code == 200 then
                local decoded = json.decode(res.text)
                if decoded.ok and #decoded.result > 0 then
                    for _, update in ipairs(decoded.result) do
                        update_id = update.update_id
                        if update.message and update.message.text and tostring(update.message.chat.id) == bot_chatid then
                            local txt = update.message.text
                            if txt:match("^/[%w_]+") then
                                sendInput(txt); sendTG("⏳ Buyruq serverga yuborildi:\n`" .. txt .. "`\n*Javob kutilmoqda...*"); tg_capture_timer = os.clock() + 3.0 
                            elseif txt:lower() == "!cmd" then 
                                sendTG("🤖 **" .. bot_name .. " - MENYU (v2.1)** 🤖\n\n📊 `/stats` - Ish hisobotlari\n👥 `!admins` - Onlayn adminlar\n📍 `!loc` - Bot joylashuvi\n💬 `!a [matn]` - Admin chatga yozish\n📢 `!say [matn]` - Oddiy chatga yozish\n🛌 `!pause [daq]` - O'yindan chiqish\n🟢 `!wake` - Serverga ulanish\n▶️ `!resume` - Qayta ishlash")
                            elseif txt:lower() == "!admins" then
                                checking_admins = true; online_admins_table = {}; sendInput("/admins"); sendTG("🔍 Adminlar ro'yxati olinmoqda...")
                                newTask(function()
                                    wait(2000); checking_admins = false
                                    if #online_admins_table == 0 then sendTG("❌ Adminlar topilmadi.")
                                    else
                                        local final_list = "👥 **Serverdagi Adminlar:**\n\n"
                                        for i, adm in ipairs(online_admins_table) do
                                            current_stat_id = adm.id; current_stat_time = "0 daqiqa"; sendInput("/stats " .. adm.id); wait(1500) 
                                            final_list = final_list .. "👤 " .. adm.name .. " [" .. adm.id .. "] - " .. adm.lvl .. " daraja | ⏱ " .. current_stat_time .. "\n"
                                        end
                                        current_stat_id = nil; final_list = final_list .. "\n📊 Jami onlayn: " .. #online_admins_table .. " ta"; sendTG(final_list)
                                    end
                                end)
                            elseif txt:lower() == "/stats" or txt:lower() == "!stats" then
                                local uptime = math.floor((os.time() - cfg.stats.start_time) / 3600)
                                sendTG("📊 **KUNLIK VA HAFTALIK HISOBOT:**\n\nDu: `" .. cfg.stats.Dushanba .. "` | Se: `" .. cfg.stats.Seshanba .. "` | Ch: `" .. cfg.stats.Chorshanba .. "`\nPa: `" .. cfg.stats.Payshanba .. "` | Ju: `" .. cfg.stats.Juma .. "` | Sh: `" .. cfg.stats.Shanba .. "` | Ya: `" .. cfg.stats.Yakshanba .. "`\n\n⏱ **Uptime:** `" .. uptime .. " soat`")
                            elseif txt:lower() == "!loc" then
                                local bx, by, bz = getBotPosition()
                                if bx then sendTG("📍 **Joylashuv:**\nX: `" .. string.format("%.2f", bx) .. "`\nY: `" .. string.format("%.2f", by) .. "`") end
                            elseif txt:match("^!a%s+(.+)") then sendInput("/a " .. txt:match("!a%s+(.+)"))
                            elseif txt:match("^!say%s+(.+)") then sendInput(txt:match("!say%s+(.+)"))
                            elseif txt:lower() == "!resume" then is_hiding = false; is_wandering = true; sendTG("▶️ Bot ishga qaytdi.")
                            elseif txt:match("^!pause%s+(%d+)") then
                                local mins = tonumber(txt:match("^!pause%s+(%d+)")); sleep_end_time = os.time() + (mins * 60); disconnect(); is_wandering = false; sendTG("🛌 Bot " .. mins .. " daqiqaga o'yindan chiqdi.")
                                newTask(function() while os.time() < sleep_end_time do wait(1000) end; if sleep_end_time ~= 0 then sleep_end_time = 0; connect(); sendTG("🟢 Ulanmoqda...") end end)
                            elseif txt:lower() == "!wake" then
                                if sleep_end_time ~= 0 then sleep_end_time = 0; connect(); sendTG("🟢 Bot ulanmoqda..."); end
                            end
                        end
                    end
                end
            end
        end
    end)
end

function sampev.onSendPlayerSync(data)
    if is_hiding then return end
    if is_wandering then
        data.keysData = 1
        if math.random(1, 100) > 95 then current_speed = (current_speed == 0.05) and 0.15 or 0.05; angle = angle + (math.random() - 0.5) end
        local bx, by, bz = getBotPosition()
        if bx then
            local dist = math.sqrt((bx - center_x)^2 + (by - center_y)^2)
            if dist > 15 then angle = math.atan2(center_y - by, center_x - bx) end
            data.position.x = bx + math.cos(angle) * current_speed
            data.position.y = by + math.sin(angle) * current_speed
            setBotPosition(data.position.x, data.position.y, bz)
        end
        return {data}
    end
end

function sampev.onServerMessage(color, text)
    local clean = text:gsub("{......}", "")
    local lower_clean = clean:lower()

    if tg_capture_timer and os.clock() <= tg_capture_timer then
        if not clean:match("%[%d+%]:") and not clean:match("SMS:") and not clean:match("yozdi:") then
            sendTG("📩 **Server:**\n`" .. clean .. "`"); tg_capture_timer = nil 
        end
    end

    if clean:find("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa") then
        local daqiqa = clean:match("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa")
        sendTG("📊 Sizning bugungi boshqaruv vaqtingiz: " .. daqiqa .. " daqiqa.")
    end

    if clean:find("Shikoyat") and clean:find("ID:%s*(%d+)") then
        local target_id = clean:match("ID:%s*(%d+)")
        table.insert(sp_queue, target_id)
        sendTG("📝 Shikoyat: " .. target_id .. " ID navbatga qo'shildi! (Jami: " .. #sp_queue .. ")")
    end

    if lower_clean:find("hozir mp bo'ladi") or lower_clean:find("hozir mp boladi") or lower_clean:find("mp boshlan") or lower_clean:find("ishtirok etish uchun hisobotingizga") then
        is_mp_active = true; sendTG("📢 **MP Boshlandi!** Teleport ochildi.")
    elseif lower_clean:find("g'olib bo'lgan") or lower_clean:find("go'lib bolgan") or lower_clean:find("g'olib bolgan") or lower_clean:find("golib bolgan") then
        is_mp_active = false; sendTG("🛑 **MP Tugadi!** Teleport yopildi.")
    end

    if checking_admins then
        local admin_name, admin_id, admin_lvl = clean:match("([%a_]+)%[(%d+)%]%s*|%s*(%d+)%s*darajasi")
        if admin_name then table.insert(online_admins_table, {name = admin_name, id = admin_id, lvl = admin_lvl}) end
    end

    if current_stat_id then
        local ptime = clean:match("vaqti:%s*(%d+)%s*daqiqa") or clean:match("vaqti:%s*(%d+)") or clean:match("(%d+)%s*daqiqa")
        if ptime then current_stat_time = ptime .. " daqiqa" end
    end

    if last_punish_admin and (lower_clean:find("topilmadi") or lower_clean:find("bunday") or lower_clean:find("mavjud emas")) then
        last_punish_status = false 
        newTask(function() wait(500); sendInput("/a " .. last_punish_admin .. ", bunday id/nick topilmadi!"); sendTG("❌ Xato: " .. last_punish_admin .. " so'ragan o'yinchi topilmadi."); last_punish_admin = nil end)
    end

    local a_name, a_cmd, a_args = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(/[%a]+)%s+(.+)")
    if not a_name then a_name, a_cmd, a_args = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(/[%a]+)%s+(.+)") end
    
    if a_name and a_cmd and allowed_cmds[a_cmd:lower()] then
        local first_letter, last_name = a_name:match("^(%a)%a+_(%a+)$")
        if first_letter and last_name then
            last_punish_admin = first_letter .. "." .. last_name; last_punish_status = true
            newTask(function()
                wait(1500); sendInput(a_cmd .. " " .. a_args .. " // " .. last_punish_admin); wait(1500) 
                if last_punish_status then sendInput("/a +"); sendTG("🔨 Jazo berildi:\n`" .. a_cmd .. " " .. a_args .. "`"); last_punish_admin = nil end
            end)
        end
    end

    local adm_name, adm_text = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(.+)")
    if not adm_name then adm_name, adm_text = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(.+)") end

    if adm_name and adm_name ~= bot_name and not red_admins[adm_name] then
        if adm_text and not allowed_cmds[adm_text:match("^(%S+)")] then 
            local lower_text = adm_text:lower()
            local is_talking_to_me = false
            
            local bot_short_name = bot_name:match("^(%w+)_"):lower()
            if lower_text:find(bot_short_name) or lower_text:find("azim") or lower_text:find("asilbek") or lower_text:find("aslbek") then 
                is_talking_to_me = true
            elseif active_chat_admin == adm_name and (os.time() - active_chat_time) <= chat_timeout_seconds then 
                is_talking_to_me = true 
            end

            if is_talking_to_me then
                active_chat_admin = adm_name; active_chat_time = os.time(); sendTG("💬 *Admin (" .. adm_name .. ") botga yozyapti:*\n_" .. adm_text .. "_") 
                newTask(function()
                    wait(math.random(1500, 2500)) 
                    local ai_reply = getAIChatReply("Siz O'yindagi Admin chatida suhbatlashyapsiz. " .. adm_name .. " ismli admin sizga yozdi: " .. adm_text)
                    if ai_reply then
                        sendInput("/a " .. ai_reply); sendTG("🤖 *Javob berildi:*\n_" .. ai_reply .. "_")
                    end
                end)
            end
        end
    end

    if clean:match("^SMS") or clean:match("yozdi:") then 
        local sender_name, sender_id = clean:match("(%a+_%a+)%[(%d+)%]")
        if sender_name and sender_id and isRPNick(sender_name) and not red_admins[sender_name] and sender_name ~= bot_name then
            sendTG("✉️ *Sizga SMS (" .. sender_name .. "):*\n_" .. clean .. "_") 
            newTask(function()
                local user_msg = clean:gsub(sender_name .. "%[%d+%]", ""):gsub("SMS:", ""):gsub("yozdi:", "")
                wait(math.random(2000, 4000)) 
                local ai_reply = getAIChatReply("Sizga o'yinchi shunday SMS yozdi: " .. user_msg)
                if ai_reply then sendInput("/pm " .. sender_id .. " " .. ai_reply) end
            end)
        end
    end

    if clean:match("^(%a+_%a+)%[%d+%]:") and red_admins[clean:match("^(%a+_%a+)%[%d+%]:")] then sendTG("🔴 Qizil admin (" .. clean:match("^(%a+_%a+)%[%d+%]:") .. ") chatda yozdi!") end

    local target_id, admin_ans = clean:match("<ADM>.-%[%d+%]%s+.-%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)") 
    if target_id and admin_ans then
        target_id = tostring(target_id)
        if pending_reports[target_id] then
            bot_memory[pending_reports[target_id]:lower()] = admin_ans; saveMemory()
            sendTG("🧠 **O'rgandim!**\nSavol: `" .. pending_reports[target_id] .. "`\nJavob: `" .. admin_ans .. "`")
        end
    end

    if clean:find("%[Hisobotlar soni:") then
        local rep_name = clean:match("([%a_]+)%[%d+%]:")
        local rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.-)%s*%[Hisobotlar")
        
        if not rep_id then rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.+)"); if rep_text then rep_text = rep_text:gsub("%[Hisobotlar.-%]", "") end end

        if rep_id and rep_text then
            rep_name = rep_name or "Noma'lum"
            rep_id = tostring(rep_id)
            local lower_rep = rep_text:lower():match("^%s*(.-)%s*$")
            local is_fast_plus = (lower_rep:match("^[+%s]+$") ~= nil)

            if lower_rep:find("ag'dar") or lower_rep:find("to'ntar") then newTask(function() wait(1500); sendInput("/flip " .. rep_id) end) end
            if lower_rep:find("remont") or lower_rep:find("buzildi") or lower_rep:find("fix") then newTask(function() wait(2000); if math.random(1, 100) <= 50 then sendInput("/fixcar " .. rep_id) end end) end
            
            if is_fast_plus then
                if is_mp_active then
                    local final_reply = "Assalomu alaykum, hozir teleport bo'lasiz"
                    table.insert(report_queue, 1, {id = rep_id, reply = final_reply, name = rep_name, text = rep_text})
                else
                    newTask(function()
                        wait(6000)
                        local final_reply = "Assalomu alaykum, teleport yopiq"
                        table.insert(report_queue, {id = rep_id, reply = final_reply, name = rep_name, text = rep_text})
                    end)
                end
            else
                newTask(function()
                    wait(4000)
                    local final_reply = getSmartReply(rep_text, rep_name)
                    if not final_reply then
                        -- AI QOIDALARI YANADA KUCHAYTIRILDI
                        local admin_system_prompt = string.format([[
Siz SA-MP serverining o'zbek administratori "%s"siz. Reportlarga qat'iy, rasmiy va faqat 1 ta gap bilan javob bering.
QOIDALAR:
1. Agar o'yinchi joylashuv (qayerda, qanday boraman, topib ber) so'rasa: "Assalomu alaykum, qidirayotgan joyingizni planshet (/gps) orqali topishingiz mumkin."
2. Agar mashinasi haqida (moshinamni tuzatib ber, chin, buzildi, remont) yozsa: "Assalomu alaykum, spidometrdagi evakuator tugmasini bosing."
3. Agar o'yinchi kimgadir shikoyat qilsa (DM, DB, uryapti, so'kyapti, id): "Assalomu alaykum, ushbu o'yinchini kuzatishni boshladim."
4. Agar o'yinchi pul, mashina, donat yoki narx so'rasa: "Assalomu alaykum, bu RP jarayon, o'zingiz bilib olishingiz kerak."
5. Shaxsiy qoida o'ylab topmang, aniq va qisqa javob bering.
]], bot_name)
                        final_reply = askChatGPT(admin_system_prompt, rep_text)
                        
                        -- Agar internet uzilsa yoki AI javob bera olmasa, ehtiyot qismlar
                        if not final_reply or final_reply == "" then
                            if rep_text:lower():find("qayer") or rep_text:lower():find("topib") then 
                                final_reply = "Assalomu alaykum, planshet (/gps) orqali qidirib topishingiz mumkin."
                            elseif rep_text:lower():find("chin") or rep_text:lower():find("moshin") then
                                final_reply = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing."
                            else 
                                final_reply = "Assalomu Alaykum, sizni kuzatmoqdaman." 
                            end
                        end
                        
                        if final_reply:find("kuzatishni boshladim") then
                            local extract_id = rep_text:match("(%d+)")
                            if extract_id then table.insert(sp_queue, extract_id) end
                        end
                    end
                    table.insert(report_queue, {id = rep_id, reply = final_reply, name = rep_name, text = rep_text})
                end)
            end
        end
    end

    if clean:find("yangiliklari uchun ariza paydo bo'ldi") and clean:find("/acceptgnews") then
        newTask(function() wait(1000); sendInput("/acceptgnews"); sendTG("✅ Yangiliklar arizasi tasdiqlandi!") end)
    end
end

-- ================= DIALOG VA SPAVN BOSHQARUVI =================
function sampev.onShowDialog(id, style, title, button1, button2, text)
    local clean_title = title:gsub("{......}", "")
    local clean_text = text:gsub("{......}", "")
    local lower_title = clean_title:lower()
    local lower_text = clean_text:lower()

    if id == last_dialog_id and (os.clock() - last_dialog_time) < 2.0 then return false end
    last_dialog_id = id
    last_dialog_time = os.clock()

    if lower_title:find("xush") or lower_title:find("добро") or lower_title:find("yangilik") or lower_title:find("новости") or lower_title:find("grand mobile") then
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
                sendInput("/az"); wait(1500); sendInput("/acceptgnews"); wait(1500); sendInput("/sp")
                sendTG("📰 O'yinga kirdi va avto-SP ga o'tdi.")
                is_wandering = true 
            end)
        end
        return false 
    end
    
    if clean_title:find("Arizani tasdiqlash") then 
        local auth_code = clean_text:match("kalitni kiriting:%s*(%d%d%d%d)")
        if auth_code then sendDialogResponse(id, 1, 0, auth_code); return false end 
    end
    
    local code = text:match("(%d%d%d%d%d)") 
    if code and not current_stat_id and not clean_title:find("Arizani tasdiqlash") then 
        sendDialogResponse(id, 1, 0, code); return false 
    end
    
    if current_stat_id then sendDialogResponse(id, 0, 0, ""); return false end
end

function onConnectionClosed()
    is_wandering = false
    is_logged_in = false 
    sendTG("❌ Bot serverdan uzildi.")
    newTask(function() wait(15000); connect(); sendTG("🟢 Qayta ulanmoqda..."); end)
end

function onExit()
    ini.save(cfg, "settings\\config.txt")
end

function onLoad()
    if isRPNick(bot_name) then 
        loadMemory()
        telegramPolling()
        checkUpdates()
        
        newTask(function()
            while true do
                wait(1000) 
                
                if is_spectating then
                    if os.time() - sp_timer >= 30 then
                        sendInput("/sp") 
                        is_spectating = false
                    end
                elseif #sp_queue > 0 then
                    local target_id = table.remove(sp_queue, 1) 
                    sendInput("/sp " .. target_id)
                    is_spectating = true
                    sp_timer = os.time()
                end

                if #report_queue > 0 then
                    local task = table.remove(report_queue, 1)
                    sendInput("/ans " .. task.id .. " " .. task.reply)
                    
                    local today_str = days_map[os.date("%A")] or "Dushanba"
                    cfg.stats[today_str] = (tonumber(cfg.stats[today_str]) or 0) + 1
                    ini.save(cfg, "settings\\config.txt")
                    
                    wait(500)
                    sendInput("/re " .. task.id)
                    sendTG("✅ **Javob Berildi:**\n👤 O'yinchi: `" .. task.name .. " [" .. task.id .. "]`\n❓ Savol: `" .. task.text .. "`\n🤖 Bot Javobi: `" .. task.reply .. "`")
                    wait(1500)
                end
            end
        end)
        
        print("[BOT] " .. bot_name .. " 100% Ishga tushdi! (v2.1)") 
    else 
        print("[XATO] Botingiz nomi " .. bot_name .. " emas! Ismni o'zgartiring.") 
    end
end
-- === KOD TUGASHI ===
