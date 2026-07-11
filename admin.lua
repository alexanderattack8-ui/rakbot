-- === KOD BOSHLANISHI ===
require("addon")
local sampev = require("samp.events")
local ini = require("inicfg")
local requests = require("requests")
local json = require("cjson")
local math = require("math")
local os = require("os")

-- ================= GITHUB YANGILANISH SOZLAMALARI =================
local script_version = 3.6 
local script_name_file = "admin.lua" 
local update_info_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/version.json"
-- ==================================================================

-- CONFIG.TXT DAN MA'LUMOTLARNI YUKLASH
local cfg = ini.load({
    settings = { 
        bot_name = "", 
        token = "", 
        chatid = "", 
        password = "",
        gemini_key = ""
    },
    daily_logs = {
        start_time = os.time()
    }
}, "settings\\config.txt")

local bot_name = tostring(cfg.settings.bot_name):match("^%s*(.-)%s*$") or ""
local bot_token = tostring(cfg.settings.token):match("^%s*(.-)%s*$") or ""
local bot_chatid = tostring(cfg.settings.chatid):match("^%s*(.-)%s*$") or ""
local gemini_key = tostring(cfg.settings.gemini_key):match("^%s*(.-)%s*$") or ""

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
    Monday = "Dushanba", 
    Tuesday = "Seshanba", 
    Wednesday = "Chorshanba",
    Thursday = "Payshanba", 
    Friday = "Juma", 
    Saturday = "Shanba", 
    Sunday = "Yakshanba"
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
        pcall(function() 
            bot_memory = json.decode(data) 
        end)
    end
end

function saveMemory()
    local f = io.open(memory_file, "w")
    if f then
        f:write(json.encode(bot_memory))
        f:close()
    end
end

local red_admins = { 
    ["Maga_By"] = true, 
    ["Ivan_Vasilyev"] = true, 
    ["John_Medvedev"] = true, 
    ["Ace_Alonso"] = true 
}

local auto_replies = {
    ["qachon warn"] = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["warn qachon"] = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["qancha warn"] = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
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
    ["qayerda"] = "Assalomu alaykum, planshet (/gps) orqali qidirib topishingiz mumkin.",
    ["topib ber"] = "Assalomu alaykum, planshet (/gps) orqali qidirib topishingiz mumkin.",
    ["qanday boraman"] = "Assalomu alaykum, planshet (/gps) orqali qidirib topishingiz mumkin.",
    ["qanday ishlayman"] = "Assalomu alaykum, bu RP jarayon, o'zingiz bilib olishingiz kerak."
}

local is_wandering = false
local angle = 0
local center_x, center_y = 0, 0
local current_speed = 0.05 
local is_hiding = false 
local sleep_end_time = 0
local checking_admins = false
local online_admins_table = {}
local current_stat_id = nil

local allowed_cmds = {
    ["/ban"] = true, ["/offban"] = true, ["/warn"] = true, ["/offwarn"] = true,
    ["/kick"] = true, ["/mute"] = true, ["/rmute"] = true, ["/offmute"] = true,
    ["/unmute"] = true, ["/offunmute"] = true
}

function isRPNick(name) 
    return string.match(name, "^%u%a+_%u%a+$") ~= nil 
end

function askGemini(system_prompt, user_text)
    if gemini_key == "" or ai_busy then 
        return nil 
    end
    
    ai_busy = true
    local safe_user_text = user_text:gsub('"', ''):gsub('\\', '')
    
    local payload = {
        contents = { { parts = { { text = system_prompt .. "\n\nO'yinchi/Admin yozdi: " .. safe_user_text } } } },
        generationConfig = { temperature = 0.6, maxOutputTokens = 80 }
    }
    
    local headers = { ["Content-Type"] = "application/json" }
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. gemini_key
    
    local success, response = pcall(function() 
        return requests.post(url, {headers = headers, data = json.encode(payload), timeout = 6.0}) 
    end)
    
    ai_busy = false
    
    if success and response and response.status_code == 200 then
        local data = json.decode(response.text)
        if data and data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts and data.candidates[1].content.parts[1] then
            return data.candidates[1].content.parts[1].text:gsub("\n", " ")
        end
    end
    
    return nil
end

function getAIChatReply(text)
    local prompt = string.format("Siz SA-MP serverining administratori %s siz. Kimdir sizga yozdi. Qisqa, tabiiy va do'stona ohangda o'zbek tilida (1 ta gap bilan) javob bering.", bot_name)
    local ai_response = askGemini(prompt, text)
    if ai_response then return ai_response end
    return nil
end

function getSmartReply(text, sender_name)
    local lower_text = text:lower()
    
    if lower_text:find("rp") and (lower_text:find("nik") or lower_text:find("nick")) then
        local target_name = text:match("(%u%a+_%u%a+)")
        if not target_name then target_name = sender_name end
        if target_name and target_name ~= "Noma'lum" then
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

function sendTG(text)
    if bot_token == "" or bot_chatid == "" then return end
    local payload = { chat_id = bot_chatid, text = text, parse_mode = "Markdown" }
    local headers = { ["Content-Type"] = "application/json" }
    newTask(function() 
        pcall(function() 
            requests.post("https://api.telegram.org/bot" .. bot_token .. "/sendMessage", {headers = headers, data = json.encode(payload), timeout = 2}) 
        end) 
    end)
end

function checkUpdates()
    newTask(function()
        local success, response = pcall(function() return requests.get(update_info_url, {timeout = 3}) end)
        if success and response and response.status_code == 200 then
            local data = json.decode(response.text)
            if data and data.version and tonumber(data.version) > script_version then
                sendTG("🔄 **Yangi versiya chiqdi! (v" .. data.version .. ")**\nIltimos, yangi kodni GitHub'dan qo'lda yangilang.")
            end
        end
    end)
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
            wait(5000) 
            local success, res = pcall(function() return requests.get("https://api.telegram.org/bot" .. bot_token .. "/getUpdates?offset=" .. (update_id + 1), {timeout = 1}) end)
            
            if success and res and res.status_code == 200 then
                local decoded = json.decode(res.text)
                if decoded.ok and #decoded.result > 0 then
                    for _, update in ipairs(decoded.result) do
                        update_id = update.update_id
                        
                        if update.message and update.message.text and tostring(update.message.chat.id) == bot_chatid then
                            local txt = update.message.text
                            if txt:match("^/[%w_]+") then
                                sendInput(txt)
                                sendTG("⏳ Buyruq serverga yuborildi:\n`" .. txt .. "`")
                                tg_capture_timer = os.clock() + 3.0 
                            elseif txt:lower() == "!cmd" then 
                                sendTG("🤖 **MENYU (v3.6 Terminator)**\n📊 `/stats` - Hisobot\n🔄 `!reset` - Hisobotni tozalash\n👥 `!admins` - Onlayn adminlar\n💬 `!a [matn]` - Admin chat\n🛌 `!pause [daq]` - Uxlash")
                            elseif txt:lower() == "!admins" then
                                checking_admins = true
                                online_admins_table = {}
                                sendInput("/admins")
                                sendTG("🔍 Adminlar tekshirilmoqda...")
                                newTask(function() wait(2500); checking_admins = false; sendTG("✅ Adminlar ro'yxati yangilandi (Jami: " .. #online_admins_table .. ")") end)
                            elseif txt:lower() == "/stats" or txt:lower() == "!stats" then
                                local msg = "📊 **OXIRGI 7 KUNLIK HISOBOT:**\n\n"
                                local current_time = os.time()
                                for i = 6, 0, -1 do
                                    local d = current_time - (i * 86400) 
                                    local d_str = os.date("%d.%m", d)
                                    local d_name = days_map[os.date("%A", d)]
                                    local rp = cfg.daily_logs[d_str .. "_rep"] or 0
                                    local soat = cfg.daily_logs[d_str .. "_soat"] or 0
                                    if i == 0 then msg = msg .. "🟢 *" .. d_str .. " (" .. d_name .. ") [Bugun]:* Rep `" .. rp .. "` | Soat `" .. soat .. "`\n"
                                    else msg = msg .. "📅 *" .. d_str .. " (" .. d_name .. "):* Rep `" .. rp .. "` | Soat `" .. soat .. "`\n" end
                                end
                                sendTG(msg)
                            elseif txt:lower() == "!reset" then
                                cfg.daily_logs = {}; cfg.daily_logs.start_time = os.time(); ini.save(cfg, "settings\\config.txt")
                                sendTG("✅ **Barcha tarixiy hisobotlar tozalandi! 0 dan boshlandi.**")
                            elseif txt:match("^!pause%s+(%d+)") then
                                local mins = tonumber(txt:match("^!pause%s+(%d+)")); sleep_end_time = os.time() + (mins * 60); disconnect(); is_wandering = false; sendTG("🛌 Bot " .. mins .. " daqiqaga uxlaydi.")
                                newTask(function() while os.time() < sleep_end_time do wait(1000) end; if sleep_end_time ~= 0 then sleep_end_time = 0; connect(); sendTG("🟢 Ulanmoqda...") end end)
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
            sendTG("📩 **Server:**\n`" .. clean .. "`")
            tg_capture_timer = nil 
        end
    end

    if lower_clean:find("hozir mp bo'ladi") or lower_clean:find("hozir mp boladi") or lower_clean:find("mp boshlan") or lower_clean:find("ishtirok etish uchun") or lower_clean:find("tadbiri boshlan") then
        is_mp_active = true
        sendTG("📢 **MP Boshlandi!** O'yinchilar avtomatik teleport bo'lmoqda.")
    elseif lower_clean:find("g'olib bo'ldi") or lower_clean:find("g'olib bolgan") or lower_clean:find("golib bolgan") or lower_clean:find("tadbiri tugadi") then
        is_mp_active = false
        sendTG("🛑 **MP Tugadi!** Teleport yopildi.")
    end

    if clean:find("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa") then
        local daqiqa = clean:match("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa")
        local soat = math.floor(tonumber(daqiqa) / 60)
        local today = os.date("%d.%m") 
        cfg.daily_logs[today .. "_soat"] = soat; ini.save(cfg, "settings\\config.txt")
        sendTG("📊 Bugungi boshqaruv vaqti: " .. daqiqa .. " daqiqa. Hozircha: `" .. soat .. "` soat yozildi.")
    end

    if clean:find("Shikoyat") and clean:find("ID:%s*(%d+)") then
        local target_id = clean:match("ID:%s*(%d+)")
        table.insert(sp_queue, target_id); sendTG("📝 Shikoyat: " .. target_id .. " ID navbatga qo'shildi!")
    end

    if checking_admins then
        local admin_name, admin_id, admin_lvl = clean:match("([%a_]+)%[(%d+)%]%s*|%s*(%d+)%s*darajasi")
        if admin_name then table.insert(online_admins_table, {name = admin_name, id = admin_id, lvl = admin_lvl}) end
    end

    -- ================= XOTIRA TO'QNASHUVI FIX QILINGAN QISM =================
    local a_name, a_cmd, a_args = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(/[%a]+)%s+(.+)")
    if not a_name then 
        a_name, a_cmd, a_args = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(/[%a]+)%s+(.+)") 
    end
    
    if a_name and a_cmd and allowed_cmds[a_cmd:lower()] then
        local first_letter, last_name = a_name:match("^(%a)%a+_(%a+)$")
        if first_letter and last_name then
            
            -- Xavfsiz, mustaqil o'zgaruvchilar (Local variables)
            local current_punish_admin = first_letter .. "." .. last_name
            local current_cmd = a_cmd
            local current_args = a_args
            
            newTask(function()
                wait(1500)
                sendInput(current_cmd .. " " .. current_args .. " // " .. current_punish_admin)
                wait(1500) 
                sendInput("/a +")
                sendTG("🔨 Jazo berildi:\n`" .. current_cmd .. " " .. current_args .. "`")
            end)
        end
    end

    local adm_name, adm_text = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(.+)")
    if not adm_name then adm_name, adm_text = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(.+)") end

    if adm_name and adm_name ~= bot_name and not red_admins[adm_name] then
        if adm_text and not allowed_cmds[adm_text:match("^(%S+)")] then 
            local lower_adm_text = adm_text:lower()
            local is_talking_to_me = false
            
            local bot_short_name = bot_name:match("^(%w+)_"):lower()
            if lower_adm_text:find(bot_short_name) or lower_adm_text:find("azim") or lower_adm_text:find("asilbek") or lower_adm_text:find("bot") then 
                is_talking_to_me = true
            elseif active_chat_admin == adm_name and (os.time() - active_chat_time) <= chat_timeout_seconds then 
                is_talking_to_me = true 
            end

            if is_talking_to_me then
                active_chat_admin = adm_name; active_chat_time = os.time()
                sendTG("💬 *Admin (" .. adm_name .. ") botga yozyapti:*\n_" .. adm_text .. "_") 
                newTask(function()
                    wait(math.random(1500, 2500)) 
                    local ai_reply = getAIChatReply("Admin chatida " .. adm_name .. " ismli hamkasbingiz sizga yozdi: " .. adm_text)
                    if ai_reply then
                        sendInput("/a " .. ai_reply)
                        sendTG("🤖 *Gemini AI Javobi:*\n_" .. ai_reply .. "_")
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

    local target_id, admin_ans = clean:match("<ADM>.-%[%d+%]%s+.-%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)") 
    if target_id and admin_ans then
        target_id = tostring(target_id)
        if pending_reports[target_id] then
            bot_memory[pending_reports[target_id]:lower()] = admin_ans; saveMemory()
            sendTG("🧠 **Bazaga qo'shildi (O'rgandim)!**\nSavol: `" .. pending_reports[target_id] .. "`\nJavob: `" .. admin_ans .. "`")
            pending_reports[target_id] = nil 
        end
    end

    -- ================= REPORTLAR BOSHQAARUVI =================
    if clean:find("%[Hisobotlar soni:") then
        local rep_name = clean:match("([%a_]+)%[%d+%]:")
        local rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.-)%s*%[Hisobotlar")
        
        if not rep_id then 
            rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.+)")
            if rep_text then rep_text = rep_text:gsub("%[Hisobotlar.-%]", "") end 
        end

        if rep_id and rep_text then
            rep_name = rep_name or "Noma'lum"
            rep_id = tostring(rep_id)
            pending_reports[rep_id] = rep_text
            
            local lower_rep = rep_text:lower():match("^%s*(.-)%s*$")
            
            -- `+` yozuvini tekshirish (Ichida faqat probel yoki + bo'lsa)
            local is_fast_plus = (lower_rep:match("^[+%s]+$") ~= nil)

            if lower_rep:find("ag'dar") or lower_rep:find("to'ntar") then newTask(function() wait(1500); sendInput("/flip " .. rep_id) end) end
            if lower_rep:find("remont") or lower_rep:find("buzildi") or lower_rep:find("fix") then newTask(function() wait(2000); if math.random(1, 100) <= 50 then sendInput("/fixcar " .. rep_id) end end) end
            
            if is_fast_plus then
                -- Barcha holatlarda `+` ga javob bermaslik (ignoring)
                sendTG("ℹ️ O'yinchi " .. rep_name .. " [" .. rep_id .. "] `+` yubordi (E'tiborsiz qoldirildi).")
            else
                newTask(function()
                    if is_mp_active then
                        wait(math.random(4000, 7000))
                        table.insert(report_queue, {id = rep_id, reply = "Assalomu aleykum, iltimos kuting.", name = rep_name, text = rep_text})
                        return
                    end
                    
                    local text_len = string.len(rep_text)
                    local calc_delay = 6000 + (text_len * 150)
                    if calc_delay < 6000 then calc_delay = math.random(6000, 8000) end
                    if calc_delay > 15000 then calc_delay = math.random(13000, 15000) end
                    calc_delay = calc_delay + math.random(-500, 1000) 
                    
                    wait(calc_delay) 
                    
                    local final_reply = getSmartReply(rep_text, rep_name)
                    
                    if not final_reply then
                        local gemini_prompt = string.format([[
Siz SA-MP serverida "%s" ismli administrorsiz.
O'yinchi quyidagi savolni yubordi: "%s"
Sizning vazifangiz FAQAT bitta gap bilan, do'stona, qisqa va aniq o'zbek tilida javob berish. Hech qanday qo'shimcha izoh yozmang!
QOIDA: Agar shikoyat bo'lsa "kuzatishni boshladim" deng. Agar qanday ishlash, nima qilish haqida bo'lsa "bu RP jarayon" deng. 
Javobingiz doim "Assalomu alaykum" so'zidan boshlansin.
]], bot_name, rep_text)
                        
                        final_reply = askGemini(gemini_prompt, rep_text)
                        
                        if not final_reply or final_reply == "" then
                            if rep_text:lower():find("qayer") or rep_text:lower():find("topib") or rep_text:lower():find("qanday boraman") then 
                                final_reply = "Assalomu alaykum, planshet (/gps) orqali qidirib topishingiz mumkin."
                            elseif rep_text:lower():find("chin") or rep_text:lower():find("moshin") or rep_text:lower():find("tuzat") then 
                                final_reply = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing."
                            else 
                                final_reply = "Assalomu Alaykum, sizni kuzatmoqdaman." 
                            end
                        end
                        
                        if final_reply:find("kuzat") then
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

function sampev.onShowDialog(id, style, title, button1, button2, text)
    local clean_title = title:gsub("{......}", "")
    local clean_text = text:gsub("{......}", "")
    local lower_title = clean_title:lower()

    if id == last_dialog_id and (os.clock() - last_dialog_time) < 2.0 then return false end
    last_dialog_id = id; last_dialog_time = os.clock()

    if lower_title:find("xush") or lower_title:find("добро") or lower_title:find("yangilik") or lower_title:find("новости") or lower_title:find("grand mobile") then
        sendDialogResponse(id, 1, 0, ""); return false
    end

    if lower_title:find("avtorizatsiya") or lower_title:find("пароль") then 
        sendDialogResponse(id, 1, 0, cfg.settings.password)
        if not is_logged_in then
            is_logged_in = true
            newTask(function()
                wait(4000); spawn(); wait(2000); spawn(); wait(3000)
                sendInput("/az"); wait(1500); sendInput("/acceptgnews"); wait(1500); sendInput("/sp")
                sendTG("📰 O'yinga kirdi va avto-SP ga o'tdi."); is_wandering = true 
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
    is_wandering = false; is_logged_in = false; sendTG("❌ Bot serverdan uzildi.")
    newTask(function() wait(15000); connect(); sendTG("🟢 Qayta ulanmoqda...") end)
end

function onExit() ini.save(cfg, "settings\\config.txt") end

function onLoad()
    if isRPNick(bot_name) then 
        loadMemory(); telegramPolling(); checkUpdates()
        newTask(function()
            while true do
                wait(1000) 
                
                if is_spectating then
                    if os.time() - sp_timer >= 30 then sendInput("/sp"); is_spectating = false; sp_timer = os.time() end
                elseif #sp_queue > 0 then
                    local target_id = table.remove(sp_queue, 1) 
                    sendInput("/sp " .. target_id); is_spectating = true; sp_timer = os.time(); sendTG("👁 Maxsus SP: " .. target_id .. " ID kuzatilmoqda.")
                else
                    if os.time() - sp_timer >= 5 then spectateRandomPlayer(); is_spectating = true; sp_timer = os.time() end
                end

                if #report_queue > 0 then
                    local task = table.remove(report_queue, 1)
                    sendInput("/ans " .. task.id .. " " .. task.reply)
                    
                    local today = os.date("%d.%m") 
                    cfg.daily_logs[today .. "_rep"] = (tonumber(cfg.daily_logs[today .. "_rep"]) or 0) + 1
                    ini.save(cfg, "settings\\config.txt")
                    
                    wait(500); sendInput("/re " .. task.id)
                    sendTG("✅ **Javob Berildi:**\n👤 O'yinchi: `" .. task.name .. " [" .. task.id .. "]`\n❓ Savol: `" .. task.text .. "`\n🤖 Bot Javobi: `" .. task.reply .. "`")
                    wait(1500)
                end
            end
        end)
        print("[BOT] " .. bot_name .. " 100% Ishga tushdi! (v3.6 Terminator)") 
    else print("[XATO] Botingiz nomi " .. bot_name .. " emas! Ismni o'zgartiring.") end
end
-- === KOD TUGASHI ===
