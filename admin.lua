-- === KOD BOSHLANISHI ===
require("addon")
local updater = require("updater")
local sampev = require("samp.events")
local ini = require("inicfg")
local requests = require("requests")
local json = require("cjson")
local math = require("math")
local os = require("os")

-- ================= VERSIYA =================
local script_version = 4.5
local script_name_file = "admin.lua"
local update_info_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/version.json"

-- ================= CONFIG =================
local cfg = ini.load({
    settings = {
        bot_name = "",
        token = "",
        chatid = "",
        password = "",
        gemini_key = "",
    },
    daily_logs = {
        start_time = os.time()
    },
    faq_meta = {
        last_update = 0
    }
}, "settings\\config.txt")

local bot_name   = tostring(cfg.settings.bot_name):match("^%s*(.-)%s*$") or ""

-- ================= LITSENZIYA =================
-- GitHub raw faylidagi ruxsat berilgan nicklar ro'yxati.
-- Client ichidagi kodni 100% buzib bo'lmaydi, shuning uchun himoya fail-closed ishlaydi.
local license_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/licenses.txt"
local license_check_interval = 6 * 60 * 60
local license_ok = false
local license_last_check = 0
local license_fail_reason = "tekshirilmagan"

local function normalizeNick(n)
    return tostring(n or ""):lower():gsub("%s+", "")
end

local function checkLicense(force)
    if not force and os.time() - license_last_check < license_check_interval then
        return license_ok
    end
    license_last_check = os.time()
    local ok, res = pcall(function()
        return requests.get(license_url, { timeout = 8 })
    end)
    if not ok or not res or res.status_code ~= 200 then
        license_ok = false
        license_fail_reason = "GitHub litsenziya fayli ochilmadi"
        return false
    end
    local wanted = normalizeNick(bot_name)
    license_ok = false
    for line in tostring(res.text):gmatch("[^\\r\\n]+") do
        line = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        if line ~= "" and normalizeNick(line) == wanted then
            license_ok = true
            break
        end
    end
    if not license_ok then license_fail_reason = "nick litsenziyada yo'q" end
    return license_ok
end

local function licenseGuard()
    if checkLicense(false) then return true end
    print("[LITSENZIYA] Ishlash to'xtatildi: " .. license_fail_reason)
    return false
end

local bot_token  = tostring(cfg.settings.token):match("^%s*(.-)%s*$") or ""
local bot_chatid = tostring(cfg.settings.chatid):match("^%s*(.-)%s*$") or ""
local gemini_key = tostring(cfg.settings.gemini_key):match("^%s*(.-)%s*$") or ""

-- ================= FAYL YO'LLARI =================
local memory_file     = "settings\\memory_base.json"   -- BITTA UMUMIY BAZA (nick qo'shilmaydi)
local old_memory_file = "settings\\" .. bot_name:lower() .. "_memory.json"  -- eski nickli baza (ko'chirish uchun)
local faq_file    = "settings\\faq_base.json"

-- ================= O'ZGARUVCHILAR =================
local bot_memory      = {}
local faq_base        = {}
local pending_reports = {}
local report_queue    = {}
local sp_queue        = {}

local is_spectating  = false
local sp_timer       = 0
local is_wandering   = false
local wander_timer   = 0
local last_activity  = os.time()
local angle          = 0
local center_x       = 0
local center_y       = 0
local current_speed  = 0.05
local is_hiding      = false
local sleep_end_time = 0

local tg_capture_timer = nil
local is_mp_active     = false
local ai_busy          = false
local is_logged_in     = false

local active_chat_admin    = nil
local active_chat_time     = 0
local chat_timeout_seconds = 60
local last_dialog_id       = -1
local last_dialog_time     = 0

local checking_admins     = false
local online_admins_table = {}
local current_stat_id     = nil
local faq_last_update     = tonumber(cfg.faq_meta.last_update) or 0
local faq_updating        = false
local base_ok = true
local base_error_sent = false
local form_senders = {}

local FAQ_UPDATE_INTERVAL = 7 * 86400 -- 7 kunda bir marta avtomatik yangilanadi

local days_map = {
    Monday    = "Dushanba",
    Tuesday   = "Seshanba",
    Wednesday = "Chorshanba",
    Thursday  = "Payshanba",
    Friday    = "Juma",
    Saturday  = "Shanba",
    Sunday    = "Yakshanba"
}

-- ================= KATTA ADMINLAR =================
local red_admins = {
    ["Maga_By"]       = true,
    ["Ivan_Vasilyev"] = true,
    ["John_Medvedev"] = true,
    ["Ace_Alonso"]    = true
}

-- ================= AVTOMATIK JAVOBLAR =================
local auto_replies = {
    ["qachon warn"]      = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["warn qachon"]      = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["qancha warn"]      = "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin.",
    ["tuzatib bering"]   = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["remont"]           = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["buzildi"]          = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["tutayapti"]        = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["pochinit"]         = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["moshinam"]         = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["tiqilib qoldi"]    = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["stuck"]            = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["evakuator"]        = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["chin"]             = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing.",
    ["nega qamadingiz"]  = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["meni aybim yo'q"]  = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["yeching"]          = "Assalomu aleykum, administrator bunday jarayonlarga aralashmaydi.",
    ["sababsiz"]         = "Assalomu aleykum, dalil bilan shikoyat yozing.",
    ["pul bering"]       = "Assalomu aleykum, keyingi off-top uchun jazo qo'llaniladi.",
    ["qayerda"]          = "Assalomu alaykum, planshetni ochib navigator tugmasini bosing.",
    ["topib ber"]        = "Assalomu alaykum, planshetni ochib navigator tugmasini bosing.",
    ["qanday boraman"]   = "Assalomu alaykum, planshetni ochib navigator tugmasini bosing.",
    ["qanday ishlayman"] = "Assalomu alaykum, bu RP jarayon, o'zingiz bilib olishingiz kerak.",
    ["divot"]            = "Assalomu alaykum, savolingizni ko'rib chiqmoqdaman."
}

-- ================= RUXSAT ETILGAN BUYRUQLAR =================
local allowed_cmds = {
    ["/ban"]      = true, ["/offban"]    = true,
    ["/warn"]     = true, ["/offwarn"]   = true,
    ["/kick"]     = true, ["/mute"]      = true,
    ["/rmute"]    = true, ["/offmute"]   = true,
    ["/unmute"]   = true, ["/offunmute"] = true,
    ["/jail"]     = true, ["/unjail"]    = true,
    ["/freeze"]   = true, ["/unfreeze"]  = true,
    ["/slap"]     = true, ["/slay"]      = true,
    ["/spec"]     = true, ["/unspec"]    = true,
    ["/setworld"] = true, ["/goto"]      = true,
    ["/gethere"]  = true, ["/bring"]     = true,
    ["/akick"]    = true, ["/aban"]      = true,
    ["/amute"]    = true, ["/awarn"]     = true
}

-- =================================================
--           YORDAMCHI FUNKSIYALAR
-- =================================================

function isRPNick(name)
    return string.match(name, "^%u%a+_%u%a+$") ~= nil
end

function startWandering()
    local bx, by, bz = getBotPosition()
    if bx then
        center_x = bx
        center_y = by
    end
    angle         = math.random() * math.pi * 2
    current_speed = 0.05
    is_wandering  = true
    is_spectating = false
    last_activity = os.time()
    wander_timer  = os.time()
end

function stopWandering()
    is_wandering = false
end

-- =================================================
--           XOTIRA FUNKSIYALARI
-- =================================================

function bazaXato(reason)
    base_ok = false
    if base_error_sent then return end
    base_error_sent = true
    sendTG("вљ пёЏ *Baza ishlamayapti!*\n`" .. tostring(reason) .. "`")
end

function bazaTuzuk()
    base_ok = true
    base_error_sent = false
end

function memAnswer(v)
    if type(v) == "table" then return v.answer end
    return v
end

function readJSONFile(path)
    local f = io.open(path, "r")
    if not f then return nil, "fayl topilmadi: " .. path end
    local data = f:read("*a")
    f:close()
    if not data or data == "" then return nil, "fayl bo'sh: " .. path end
    local ok, decoded = pcall(json.decode, data)
    if not ok or type(decoded) ~= "table" then return nil, "JSON xato: " .. path end
    return decoded
end

function loadMemory()
    bot_memory = {}
    local data, err = readJSONFile(memory_file)
    if data then bot_memory = data end

    -- eski nickli bazani umumiy bazaga ko'chirish (bir martalik migratsiya)
    local old_data = nil
    if old_memory_file ~= memory_file then
        old_data = readJSONFile(old_memory_file)
        if old_data then
            local moved = 0
            for q, a in pairs(old_data) do
                if bot_memory[q] == nil then
                    bot_memory[q] = a
                    moved = moved + 1
                end
            end
            if moved > 0 then saveMemory() end
            print("[BAZA] Eski bazadan ko'chirildi: " .. moved .. " ta")
        end
    end

    local count = 0
    for _ in pairs(bot_memory) do count = count + 1 end
    if data == nil and old_data == nil then
        bazaXato("Xotira bazasi o'qilmadi (" .. tostring(err) .. ")")
    else
        bazaTuzuk()
    end
    print("[BAZA] Xotira: " .. count .. " ta savol-javob")
end

function saveMemory()
    local ok, err = pcall(function()
        local f = io.open(memory_file, "w")
        if not f then error("yozib bo'lmadi: " .. memory_file, 0) end
        f:write(json.encode(bot_memory))
        f:close()
    end)
    if not ok then
        bazaXato("Xotira bazasiga yozilmadi (" .. tostring(err) .. ")")
        return false
    end
    return true
end

-- =================================================
-- FAQ FUNKSIYALARI
-- =================================================
function stripHTML(html)
    if not html then return "" end
    local t = html:gsub("<br%s*/?>", " ")
    t = t:gsub("<li[^>]*>", "вЂў ")
    t = t:gsub("</li>", " ")
    t = t:gsub("<p[^>]*>", " ")
    t = t:gsub("</p>", " ")
    t = t:gsub("<[^>]+>", "")
    t = t:gsub("&nbsp;", " ")
    t = t:gsub("&lt;", "<")
    t = t:gsub("&gt;", ">")
    t = t:gsub("&amp;", "&")
    t = t:gsub("&quot;", '"')
    t = t:gsub("%s+", " ")
    return t:match("^%s*(.-)%s*$") or ""
end

function loadFAQFromFile()
    faq_base = {}
    local data, err = readJSONFile(faq_file)
    if data then
        faq_base = data
    else
        bazaXato("FAQ bazasi o'qilmadi (" .. tostring(err) .. ")")
    end
    local count = 0
    for _ in pairs(faq_base) do count = count + 1 end
    print("[BAZA] FAQ: " .. count .. " ta maqola")
end

function getFAQReply(text)
    if not text or text == "" then return nil end
    local lower = text:lower():gsub("[%p%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    for key, data in pairs(faq_base) do
        if lower == key then return data.answer end
    end
    for key, data in pairs(faq_base) do
        if lower:find(key, 1, true) or key:find(lower, 1, true) then
            return data.answer
        end
    end
    local words = {}
    for w in lower:gmatch("%S+") do
        if w:len() > 3 then table.insert(words, w) end
    end
    local best, best_score = nil, 0
    for key, data in pairs(faq_base) do
        local score = 0
        for _, w in ipairs(words) do
            if key:find(w, 1, true) then score = score + 1 end
        end
        if score > best_score then best_score = score; best = data end
    end
    if best_score >= 2 and best then return best.answer end
    return nil
end

function saveFAQToFile()
    local ok, err = pcall(function()
        local f = io.open(faq_file, "w")
        if not f then error("yozib bo'lmadi: " .. faq_file, 0) end
        f:write(json.encode(faq_base))
        f:close()
    end)
    if not ok then
        bazaXato("FAQ bazasiga yozilmadi (" .. tostring(err) .. ")")
        return false
    end
    return true
end

-- =================================================
-- FAQ NI support.grnd.gg DAN YUKLASH VA TARJIMA
-- =================================================
function extractArticleTitleAndBody(html)
    -- 1-usul: sahifadagi JSON-LD (eng ishonchli, Intercom SEO uchun qo'shadi)
    local ld = html:match('<script type="application/ld%+json"[^>]*>(.-)</script>')
    if ld then
        local ok, data = pcall(json.decode, ld)
        if ok and data then
            local title = data.headline or data.name
            local body  = data.articleBody or data.description
            if body and stripHTML(body):len() > 10 then
                return title, stripHTML(body)
            end
        end
    end

    -- 2-usul: <title> va asosiy maqola blokidan qidirish (zaxira usul)
    local title = html:match("<title>(.-)</title>")
    if title then
        title = title:gsub("%s*|.*$", ""):match("^%s*(.-)%s*$")
    end

    local body_html = html:match('<article[^>]*>(.-)</article>')
    if body_html then
        local body = stripHTML(body_html)
        if body:len() > 10 then return title, body end
    end

    return title, nil
end

function translateToUzbek(text, is_title)
    if not text or text:match("^%s*$") then return text end
    if gemini_key == "" then return nil end

    local limit = is_title and 100 or 900
    local prompt = "Quyidagi matnni ruschadan o'zbek tiliga tarjima qil. " ..
                   "FAQAT tarjima matnini qaytar, hech qanday izoh, kirish so'zi yoki tirnoq ishlatma."

    local payload = {
        contents = { { parts = { { text = prompt .. "\n\n" .. text } } } },
        generationConfig = { temperature = 0.2, maxOutputTokens = limit }
    }
    local headers = { ["Content-Type"] = "application/json" }
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. gemini_key

    local ok, response = pcall(function()
        return requests.post(url, { headers = headers, data = json.encode(payload), timeout = 15 })
    end)

    if ok and response and response.status_code == 200 then
        local ok2, data = pcall(json.decode, response.text)
        if ok2 and data and data.candidates and data.candidates[1] and
           data.candidates[1].content and data.candidates[1].content.parts and
           data.candidates[1].content.parts[1] then
            local out = data.candidates[1].content.parts[1].text
            return out:gsub('^"(.*)"$', "%1"):match("^%s*(.-)%s*$")
        end
    end
    return nil
end

function updateFAQFromWeb(manual_chat_id)
    if faq_updating then return end
    faq_updating = true
    newTask(function()
        local new_faq  = {}
        local total_ok = 0
        local total_fail = 0
        local section_fail = 0
        for _, section in ipairs(faq_sections) do
            local ok, res = pcall(function()
                return requests.get(section.url, { timeout = 10 })
            end)
            if ok and res and res.status_code == 200 then
                local links = {}
                local seen  = {}
                for href in res.text:gmatch('href="(https://support%.grnd%.gg/ru/articles/[^"]+)"') do
                    if not seen[href] then
                        seen[href] = true
                        table.insert(links, href)
                    end
                end
                for _, link in ipairs(links) do
                    wait(1500)
                    local ok2, ares = pcall(function()
                        return requests.get(link, { timeout = 10 })
                    end)
                    if ok2 and ares and ares.status_code == 200 then
                        local rus_title, rus_body = extractArticleTitleAndBody(ares.text)
                        if rus_title and rus_body then
                            local uz_title = translateToUzbek(rus_title, true)
                            wait(1000)
                            local uz_body = translateToUzbek(rus_body, false)
                            if uz_title and uz_body and uz_body ~= "" then
                                local key = uz_title:lower():gsub("[%p%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
                                new_faq[key] = {
                                    answer  = uz_body,
                                    title   = uz_title,
                                    url     = link,
                                    section = section.name
                                }
                                total_ok = total_ok + 1
                            else
                                total_fail = total_fail + 1
                            end
                        else
                            total_fail = total_fail + 1
                        end
                    else
                        total_fail = total_fail + 1
                    end
                    wait(1500)
                end
            else
                section_fail = section_fail + 1
            end
        end
        if total_ok > 0 then
            faq_base = new_faq
            saveFAQToFile()
        else
            bazaXato("FAQ saytdan yuklanmadi (bo'lim xato: " .. section_fail .. ")")
        end
        faq_last_update = os.time()
        cfg.faq_meta.last_update = faq_last_update
        pcall(function() ini.save(cfg, "settings\\config.txt") end)
        faq_updating = false
    end)
end

-- =================================================
-- AI FUNKSIYALARI
-- =================================================
function askGemini(system_prompt, user_text)
    if gemini_key == "" or ai_busy then return nil end
    ai_busy = true
    local safe = user_text:gsub('"', ''):gsub('\\', '')
    local payload = {
        contents = { { parts = { { text = system_prompt .. "\n\nYozdi: " .. safe } } } },
        generationConfig = { temperature = 0.6, maxOutputTokens = 80 }
    }
    local headers = { ["Content-Type"] = "application/json" }
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. gemini_key
    local ok, response = pcall(function()
        return requests.post(url, { headers = headers, data = json.encode(payload), timeout = 6.0 })
    end)
    ai_busy = false
    if ok and response and response.status_code == 200 then
        local data = json.decode(response.text)
        if data and data.candidates and data.candidates[1] and
           data.candidates[1].content and data.candidates[1].content.parts and
           data.candidates[1].content.parts[1] then
            return data.candidates[1].content.parts[1].text:gsub("\n", " ")
        end
    end
    return nil
end

function getAIChatReply(text)
    local prompt = string.format(
        "Siz SA-MP serverining administratori %s siz. Kimdir sizga yozdi. Qisqa, tabiiy va do'stona ohangda o'zbek tilida (1 ta gap bilan) javob bering. Hech qanday link yozmang.",
        bot_name
    )
    return askGemini(prompt, text)
end

-- =================================================
--     ASOSIY AQLLI JAVOB TIZIMI
-- =================================================

function getSmartReply(text, sender_name)
    local lower_text = text:lower():gsub("[%p%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")

    -- ================= 1) ADMIN.LUA ICHIDAGI JAVOBLAR =================
    -- RP nick tekshirish
    if lower_text:find("rp") and (lower_text:find("nik") or lower_text:find("nick")) then
        local target_name = text:match("(%u%a+_%u%a+)") or sender_name
        if target_name and target_name ~= "Noma'lum" then
            if isRPNick(target_name) then
                return "Assalomu alaykum, ha, bu RP nik."
            else
                return "Assalomu alaykum, yo'q, bu Non-RP (NRP) nik."
            end
        end
    end
    -- Tayyor avtomatik javoblar
    for key, reply in pairs(auto_replies) do
        if lower_text:find(key, 1, true) then return reply end
    end

    -- ================= 2) BAZA (FAQ) =================
    local faq_reply = getFAQReply(text)
    if faq_reply then
        local clean = faq_reply
            :gsub("https?://[%S]+", "")
            :gsub("%s+", " ")
            :match("^%s*(.-)%s*$")
        if clean and clean:len() > 10 then
            return "Assalomu alaykum, " .. clean:sub(1, 200)
        end
    end

    -- ================= 3) ADMINLAR BERGAN JAVOBLAR (umumiy xotira bazasi) =================
    if bot_memory[lower_text] then
        return memAnswer(bot_memory[lower_text])
    end
    for question, value in pairs(bot_memory) do
        local q = question:gsub("[%p%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
        if q and q ~= "" and (lower_text:find(q, 1, true) or q:find(lower_text, 1, true)) then
            return memAnswer(value)
        end
    end
    local words = {}
    for w in lower_text:gmatch("%S+") do
        if w:len() > 3 then table.insert(words, w) end
    end
    local best_mem, best_mem_score = nil, 0
    for question, value in pairs(bot_memory) do
        local score = 0
        for _, w in ipairs(words) do
            if question:find(w, 1, true) then score = score + 1 end
        end
        if score > best_mem_score then
            best_mem_score = score
            best_mem = memAnswer(value)
        end
    end
    if best_mem_score >= 2 and best_mem then return best_mem end

    return nil
end

-- =================================================
-- FALLBACK JAVOBLAR
-- =================================================
function getFallbackReply(rep_text)
    local lower_rep = rep_text:lower()

    if lower_rep:find("qayer") or lower_rep:find("topib") or
       lower_rep:find("qanday bor") or lower_rep:find("manzil") or
       lower_rep:find("navigator") then
        return "Assalomu alaykum, planshetni ochib navigator tugmasini bosing."

    elseif lower_rep:find("moshin") or lower_rep:find("tuzat") or
           lower_rep:find("remont") or lower_rep:find("buzil") or
           lower_rep:find("evakuator") or lower_rep:find("tiqil") or
           lower_rep:find("stuck") or lower_rep:find("pochinit") then
        return "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing."

    elseif lower_rep:find("shikoyat") or lower_rep:find("aldadi") or
           lower_rep:find("urdi") or lower_rep:find("haqorat") or
           lower_rep:find("xuruj") or lower_rep:find("dm ") then
        return "Assalomu alaykum, dalil bilan shikoyat yozing."

    elseif lower_rep:find("ban") or lower_rep:find("warn") or
           lower_rep:find("mute") or lower_rep:find("jail") or
           lower_rep:find("jazo") then
        return "Assalomu alaykum, /getinfo buyrug'i orqali o'z profilingizdan bilib olishingiz mumkin."

    elseif lower_rep:find("pul") or lower_rep:find("mol") or
           lower_rep:find("item") or lower_rep:find("buyum") then
        return "Assalomu alaykum, administrator o'yinchi mulkiga aralashmaydi."

    elseif lower_rep:find("uy") or lower_rep:find("kvartira") or
           lower_rep:find("biznes") then
        return "Assalomu alaykum, ko'chmas mulk bo'yicha tegishli bo'limga murojaat qiling."

    elseif lower_rep:find("ish") or lower_rep:find("maosh") or
           lower_rep:find("kasb") then
        return "Assalomu alaykum, ish haqida ma'lumot olish uchun /works buyrug'ini yozing."

    elseif lower_rep:find("oila") or lower_rep:find("nikoh") or
           lower_rep:find("marry") then
        return "Assalomu alaykum, oila masalalari bo'yicha ZAGS ga murojaat qiling."

    elseif lower_rep:find("tashkilot") or lower_rep:find("politsiya") or
           lower_rep:find("armiya") then
        return "Assalomu alaykum, tashkilotga kirish uchun ularning ofisiga borib ariza topshiring."

    else
        return "Assalomu alaykum, savolingizni ko'rib chiqmoqdaman."
    end
end

-- =================================================
--           TELEGRAM FUNKSIYALARI
-- =================================================

function sendTG(text)
    if bot_token == "" or bot_chatid == "" then return end
    local payload = { chat_id = bot_chatid, text = text, parse_mode = "Markdown" }
    local headers = { ["Content-Type"] = "application/json" }
    newTask(function()
        pcall(function()
            requests.post(
                "https://api.telegram.org/bot" .. bot_token .. "/sendMessage",
                { headers = headers, data = json.encode(payload), timeout = 2 }
            )
        end)
    end)
end

function checkUpdates()
    newTask(function()
        local ok, res = pcall(function()
            return requests.get(update_info_url, { timeout = 3 })
        end)
        if ok and res and res.status_code == 200 then
            local data = json.decode(res.text)
            if data and data.version and tonumber(data.version) > script_version then
                -- Updater o'zi yuklaydi; bu yerda faqat eski tekshiruv xabari chiqmaydi.
            end
        end
    end)
end

-- =================================================
--           SP FUNKSIYASI
-- =================================================

function spectateRandomPlayer()
    local players = {}
    for i = 0, 1000 do
        if i ~= getBotId() then
            local ok, name = pcall(getPlayerName, i)
            if ok and type(name) == "string" and name ~= "" and name ~= "Unknown" then
                local is_admin = false
                if red_admins[name] then is_admin = true end
                for _, adm in ipairs(online_admins_table) do
                    if tonumber(adm.id) == i or adm.name == name then
                        is_admin = true; break
                    end
                end
                if not is_admin then table.insert(players, i) end
            end
        end
    end
    local target = #players > 0 and players[math.random(1, #players)] or math.random(1, 50)
    sendInput("/sp " .. target)
    is_spectating = true
    sp_timer      = os.time()
    last_activity = os.time()
    stopWandering()
end

-- =================================================
--           TELEGRAM POLLING
-- =================================================

function telegramPolling()
    local update_id = 0
    newTask(function()
        while true do
            wait(5000)
            local ok, res = pcall(function()
                return requests.get(
                    "https://api.telegram.org/bot" .. bot_token ..
                    "/getUpdates?offset=" .. (update_id + 1),
                    { timeout = 1 }
                )
            end)
            if ok and res and res.status_code == 200 then
                local okd, decoded = pcall(json.decode, res.text)
                if okd and decoded and decoded.ok and decoded.result and #decoded.result > 0 then
                    for _, update in ipairs(decoded.result) do
                        update_id = update.update_id
                        if update.message and update.message.text and
                           tostring(update.message.chat.id) == bot_chatid then
                            local txt = update.message.text
                            local low = txt:lower()

                            if txt:match("^/[%w_]+") then
                                sendInput(txt)
                                sendTG("вЏі Buyruq yuborildi:\n`" .. txt .. "`")
                                tg_capture_timer = os.clock() + 3.0

                            elseif low == "!cmd" then
                                sendTG(
                                    "рџ¤– *MENYU (v4.5)*\n\n" ..
                                    "рџ“Љ `/stats` вЂ” Hisobot\n" ..
                                    "рџ”„ `!reset` вЂ” Hisobotni tozalash\n" ..
                                    "рџ‘Ґ `!admins` вЂ” Onlayn adminlar\n" ..
                                    "рџ“‹ `!forma` вЂ” Forma yuborgan adminlar\n" ..
                                    "рџ›Њ `!pause [daq]` вЂ” Uxlash\n" ..
                                    "рџ’¬ `!a [matn]` вЂ” Admin chatga yozish\n" ..
                                    "рџ”Ќ `!test [savol]` вЂ” Javob testi\n" ..
                                    "рџ“Љ `!status` вЂ” Bot holati"
                                )

                            elseif low == "!admins" then
                                checking_admins = true
                                online_admins_table = {}
                                sendInput("/admins")
                                sendTG("рџ”Ќ Adminlar tekshirilmoqda...")
                                newTask(function()
                                    wait(2500)
                                    checking_admins = false
                                    sendTG("вњ… Adminlar yangilandi. Jami: `" .. #online_admins_table .. "` ta")
                                end)

                            elseif low == "!forma" then
                                local lines = {}
                                for nick, cnt in pairs(form_senders) do
                                    table.insert(lines, "вЂў `" .. nick .. "` вЂ” `" .. cnt .. "` ta")
                                end
                                if #lines > 0 then
                                    sendTG("рџ“‹ *Forma yuborgan adminlar:*\n" .. table.concat(lines, "\n"))
                                else
                                    sendTG("рџ“‹ Hozircha forma yuborgan admin yo\'q.")
                                end

                            elseif low == "/stats" or low == "!stats" then
                                local msg = "рџ“Љ *OXIRGI 7 KUNLIK HISOBOT:*\n\n"
                                local now = os.time()
                                for i = 6, 0, -1 do
                                    local d      = now - (i * 86400)
                                    local d_str  = os.date("%d.%m", d)
                                    local d_name = days_map[os.date("%A", d)] or ""
                                    local rp     = cfg.daily_logs[d_str .. "_rep"] or 0
                                    local soat   = cfg.daily_logs[d_str .. "_soat"] or 0
                                    if i == 0 then
                                        msg = msg .. "рџџў *" .. d_str .. " (" .. d_name .. ") [Bugun]:* Rep `" .. rp .. "` | Soat `" .. soat .. "`\n"
                                    else
                                        msg = msg .. "рџ“… *" .. d_str .. " (" .. d_name .. "):* Rep `" .. rp .. "` | Soat `" .. soat .. "`\n"
                                    end
                                end
                                sendTG(msg)

                            elseif low == "!reset" then
                                cfg.daily_logs = {}
                                cfg.daily_logs.start_time = os.time()
                                pcall(function() ini.save(cfg, "settings\\config.txt") end)
                                sendTG("вњ… *Hisobotlar tozalandi!*")

                            elseif txt:match("^!pause%s+(%d+)") then
                                local mins = tonumber(txt:match("^!pause%s+(%d+)"))
                                sleep_end_time = os.time() + (mins * 60)
                                disconnect()
                                stopWandering()
                                sendTG("рџ›Њ Bot `" .. mins .. "` daqiqaga uxlaydi.")
                                newTask(function()
                                    while os.time() < sleep_end_time do wait(1000) end
                                    if sleep_end_time ~= 0 then
                                        sleep_end_time = 0
                                        connect()
                                        sendTG("рџџў Qayta ulanmoqda...")
                                    end
                                end)

                            elseif txt:match("^!a%s+(.+)") then
                                local msg_text = txt:match("^!a%s+(.+)")
                                sendInput("/a " .. msg_text)
                                sendTG("вњ… Admin chatga yuborildi: `" .. msg_text .. "`")
                            elseif low == "!faqupdate" then
                                updateFAQFromWeb()

                            elseif txt:match("^!test%s+(.+)") then
                                local test_q = txt:match("^!test%s+(.+)")
                                local reply  = getSmartReply(test_q, "Test")
                                if reply then
                                    sendTG("вњ… `" .. test_q .. "`\nв†’ `" .. reply:sub(1, 300) .. "`")
                                else
                                    local fallback = getFallbackReply(test_q)
                                    sendTG("вњ… `" .. test_q .. "`\nв†’ Fallback: `" .. fallback .. "`")
                                end

                            elseif low == "!status" then
                                local sp_st  = is_spectating and "рџџў SP da" or "вљ« SP yo\'q"
                                local wan_st = is_wandering and "рџџў Yurmoqda" or "рџ”ґ To\'xtagan"
                                local idle   = os.time() - last_activity
                                sendTG(
                                    "рџ“Љ *Bot Holati (v4.5):*\n" ..
                                    "рџ‘Ѓ SP: " .. sp_st .. "\n" ..
                                    "рџљ¶ Wandering: " .. wan_st .. "\n" ..
                                    "вЏ± Oxirgi harakat: `" .. idle .. "` soniya oldin\n" ..
                                    "рџ¤– AI: " .. (ai_busy and "рџ”ґ Band" or "рџџў Tayyor")
                                )
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- SAMP EVENTLAR
-- =================================================
function sampev.onSendPlayerSync(data)
    if is_hiding then return end
    if is_wandering then
        data.keysData = 1
        last_activity = os.time()
        if math.random(1, 100) > 95 then
            current_speed = (current_speed == 0.05) and 0.15 or 0.05
            angle = angle + (math.random() - 0.5)
        end
        local bx, by, bz = getBotPosition()
        if bx then
            local dist = math.sqrt((bx - center_x)^2 + (by - center_y)^2)
            if dist > 15 then
                angle = math.atan2(center_y - by, center_x - bx)
            end
            data.position.x = bx + math.cos(angle) * current_speed
            data.position.y = by + math.sin(angle) * current_speed
            setBotPosition(data.position.x, data.position.y, bz)
        end
        return { data }
    end
end

function sampev.onServerMessage(color, text)
    local clean       = text:gsub("{......}", "")
    local lower_clean = clean:lower()

    -- Telegram capture
    if tg_capture_timer and os.clock() <= tg_capture_timer then
        if not clean:match("%[%d+%]:") and not clean:match("SMS:") and not clean:match("yozdi:") then
            sendTG("рџ“© *Server:*\n`" .. clean .. "`")
            tg_capture_timer = nil
        end
    end

    -- ===== MP =====
    if lower_clean:find("hozir mp bo'ladi") or lower_clean:find("hozir mp boladi") or
       lower_clean:find("mp boshlan") or lower_clean:find("ishtirok etish uchun") or
       lower_clean:find("tadbiri boshlan") then
        is_mp_active = true
        sendTG("рџ“ў *MP Boshlandi!*")
    elseif lower_clean:find("g'olib bo'ldi") or lower_clean:find("g'olib bolgan") or
           lower_clean:find("golib bolgan") or lower_clean:find("tadbiri tugadi") then
        is_mp_active = false
        sendTG("рџ›‘ *MP Tugadi!*")
    end

    -- ===== BOSHQARUV VAQTI =====
    if clean:find("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa") then
        local daqiqa = clean:match("Bugungi boshqaruv vaqti:%s*(%d+)%s*daqiqa")
        local soat   = math.floor(tonumber(daqiqa) / 60)
        local today  = os.date("%d.%m")
        cfg.daily_logs[today .. "_soat"] = soat
        ini.save(cfg, "settings\\config.txt")
        sendTG("рџ“Љ Boshqaruv vaqti: `" .. daqiqa .. "` daqiqa = `" .. soat .. "` soat.")
    end

    -- ===== SHIKOYAT SP NAVBATI =====
    if clean:find("Shikoyat") and clean:find("ID:%s*(%d+)") then
        local target_id = clean:match("ID:%s*(%d+)")
        table.insert(sp_queue, target_id)
        sendTG("рџ“ќ Shikoyat: `" .. target_id .. "` ID navbatga qo'shildi!")
    end

    -- ===== ADMINLAR RO'YXATI =====
    if checking_admins then
        local aname, aid, alvl = clean:match("([%a_]+)%[(%d+)%]%s*|%s*(%d+)%s*darajasi")
        if aname then
            table.insert(online_admins_table, { name = aname, id = aid, lvl = alvl })
        end
    end

    -- ===== BOSHQA ADMIN JAZO BERSA =====
    local a_name, a_cmd, a_args = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(/[%w]+)%s+(.+)")
    if not a_name then
        a_name, a_cmd, a_args = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(/[%w]+)%s+(.+)")
    end
    if not a_name then
        a_name, a_cmd, a_args = clean:match("(%a+_%a+) used (/[%w]+) on (.+)")
    end
    if a_name and a_cmd and a_name ~= bot_name and not red_admins[a_name] then
        if allowed_cmds[a_cmd:lower()] then
            local fl, ln = a_name:match("^(%a)%a+_(%a+)$")
            if fl and ln then
                local cp = fl .. "." .. ln
                local cc, ca = a_cmd, a_args
                newTask(function()
                    wait(1500)
                    sendInput(cc .. " " .. ca .. " // " .. cp)
                    wait(1500)
                    sendInput("/a +")
                    sendTG("рџ”Ё Jazo:\n`" .. cc .. " " .. ca .. "`")
                end)
            end
        end
    end

    -- ===== ADMIN CHAT =====
    local adm_name, adm_text = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(.+)")
    if not adm_name then
        adm_name, adm_text = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(.+)")
    end
    if adm_name and adm_name ~= bot_name and not red_admins[adm_name] then
        if adm_text and not allowed_cmds[adm_text:lower():match("^(%S+)") or ""] then
            local lower_adm  = adm_text:lower()
            local talking    = false
            local short_name = bot_name:match("^(%w+)_")
            if short_name then short_name = short_name:lower() end
            if (short_name and lower_adm:find(short_name)) or lower_adm:find("bot") then
                talking = true
            elseif active_chat_admin == adm_name and
                   (os.time() - active_chat_time) <= chat_timeout_seconds then
                talking = true
            end
            if talking then
                active_chat_admin = adm_name
                active_chat_time  = os.time()
                sendTG("рџ’¬ *Admin (" .. adm_name .. "):*\n_" .. adm_text .. "_")
                newTask(function()
                    wait(math.random(1500, 2500))
                    local ai_reply = getAIChatReply(adm_name .. " sizga yozdi: " .. adm_text)
                    if ai_reply then
                        sendInput("/a " .. ai_reply)
                        sendTG("рџ¤– *AI Javob:*\n_" .. ai_reply .. "_")
                    end
                end)
            end
        end
    end

    -- ===== SMS =====
    if clean:match("^SMS") or clean:match("yozdi:") then
        local sname, sid = clean:match("(%a+_%a+)%[(%d+)%]")
        if sname and sid and isRPNick(sname) and
           not red_admins[sname] and sname ~= bot_name then
            sendTG("вњ‰пёЏ *SMS (" .. sname .. "):*\n_" .. clean .. "_")
            newTask(function()
                local umsg = clean
                    :gsub(sname .. "%[%d+%]", "")
                    :gsub("SMS:", "")
                    :gsub("yozdi:", "")
                wait(math.random(2000, 4000))
                local ai_reply = getAIChatReply("O'yinchi SMS yozdi: " .. umsg)
                if ai_reply then sendInput("/pm " .. sid .. " " .. ai_reply) end
            end)
        end
    end

        -- ===== ADMINLAR BERGAN JAVOBLARNI UMUMIY BAZAGA YIG'ISH =====
    local tid, ans = nil, nil
    tid, ans = clean:match("<ADM>.-%[%d+%]%s+.-%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)")
    if not tid then
        tid, ans = clean:match("%[A%].-%[%d+%]%s+%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)")
    end
    if not tid then
        tid, ans = clean:match("/ans%s+(%d+)%s+(.+)")
    end
    if tid and ans then
        local ans_admin = clean:match("(%u%a+_%u%a+)%[%d+%]") or clean:match("(%u%a+_%u%a+)")
        tid = tostring(tid)
        if pending_reports[tid] then
            if ans_admin ~= bot_name then
                local savol = pending_reports[tid]:lower()
                    :gsub("[%p%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
                local javob = ans
                    :gsub("https?://[%S]+", "")
                    :gsub("%s+", " ")
                    :match("^%s*(.-)%s*$") or ans
                if savol and savol ~= "" and javob and javob ~= "" then
                    bot_memory[savol] = {
                        answer = javob,
                        admin  = ans_admin or "Noma'lum",
                        time   = os.time()
                    }
                    saveMemory()
                    print("[BAZA] O'rgandi (" .. tostring(ans_admin) .. "): " .. savol)
                end
            end
            pending_reports[tid] = nil
        end
    end

    -- ===== FORMA YUBORUVCHILAR =====
    if lower_clean:find("forma") or lower_clean:find("ariza") then
        local f_name = clean:match("(%u%a+_%u%a+)")
        if f_name and f_name ~= bot_name then
            form_senders[f_name] = (form_senders[f_name] or 0) + 1
            sendTG(
                "рџ“‹ *Forma yubordi:* `" .. f_name .. "`\n" ..
                "рџ”ў Jami: `" .. form_senders[f_name] .. "` ta\n" ..
                "_" .. clean .. "_"
            )
        end
    end

-- ===== REPORTLAR =====
    if clean:find("%[Hisobotlar soni:") then
        local rep_name = clean:match("([%a_]+)%[%d+%]:")
        local rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.-)%s*%[Hisobotlar")
        if not rep_id then
            rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.+)")
            if rep_text then rep_text = rep_text:gsub("%[Hisobotlar.-%]", "") end
        end
        if rep_id and rep_text then
            rep_name = rep_name or "Noma'lum"
            rep_id   = tostring(rep_id)
            rep_text = rep_text:match("^%s*(.-)%s*$") or rep_text
            pending_reports[rep_id] = rep_text

            local lower_rep = rep_text:lower():match("^%s*(.-)%s*$")
            local is_plus   = (lower_rep:match("^[+%s]+$") ~= nil)

            if lower_rep:find("ag'dar") or lower_rep:find("to'ntar") then
                newTask(function() wait(1500); sendInput("/flip " .. rep_id) end)
            end
            if lower_rep:find("remont") or lower_rep:find("buzildi") or lower_rep:find("fix") then
                newTask(function()
                    wait(2000)
                    if math.random(1, 100) <= 50 then sendInput("/fixcar " .. rep_id) end
                end)
            end

            if is_plus then
                sendTG("в„№пёЏ `" .. rep_name .. " [" .. rep_id .. "]` `+` yubordi (E'tiborsiz).")
            else
                newTask(function()
                    if is_mp_active then
                        wait(math.random(4000, 7000))
                        table.insert(report_queue, {
                            id    = rep_id,
                            reply = "Assalomu aleykum, iltimos kuting.",
                            name  = rep_name,
                            text  = rep_text
                        })
                        return
                    end

                    local tlen  = string.len(rep_text)
                    local delay = 6000 + (tlen * 150)
                    if delay < 6000  then delay = math.random(6000, 8000) end
                    if delay > 15000 then delay = math.random(13000, 15000) end
                    delay = delay + math.random(-500, 1000)
                    wait(delay)

                    local final_reply = getSmartReply(rep_text, rep_name)

                    if not final_reply then
                        local prompt = string.format([[
Siz SA-MP serverida "%s" ismli administrorsiz.
O'yinchi savoli: "%s"
FAQAT bitta gap, o'zbek tilida javob bering.
Hech qanday link yoki URL yozmang!
Shikoyat bo'lsa: "kuzatishni boshladim" deng.
Mashina muammosi bo'lsa: "spidometrdagi evakuator tugmasini bosing" deng.
Manzil so'rasa: "planshetni ochib navigator tugmasini bosing" deng.
Javob "Assalomu alaykum" dan boshlansin.
]], bot_name, rep_text)

                        final_reply = askGemini(prompt, rep_text)

                        if final_reply then
                            final_reply = final_reply
                                :gsub("https?://[%S]+", "")
                                :gsub("%s+", " ")
                                :match("^%s*(.-)%s*$")
                        end

                        if not final_reply or final_reply == "" then
                            final_reply = getFallbackReply(rep_text)
                        end

                        if final_reply and final_reply:find("kuzat") then
                            local eid = rep_text:match("(%d+)")
                            if eid then table.insert(sp_queue, eid) end
                        end
                    end

                    table.insert(report_queue, {
                        id    = rep_id,
                        reply = final_reply,
                        name  = rep_name,
                        text  = rep_text
                    })
                end)
            end
        end
    end

    if clean:find("yangiliklari uchun ariza paydo bo'ldi") and clean:find("/acceptgnews") then
        newTask(function()
            wait(1000)
            sendInput("/acceptgnews")
            sendTG("вњ… Yangiliklar arizasi tasdiqlandi!")
        end)
    end
end

-- =================================================
--           DIALOG HANDLER
-- =================================================

function sampev.onShowDialog(id, style, title, button1, button2, text)
    local clean_title = title:gsub("{......}", "")
    local clean_text  = text:gsub("{......}", "")
    local lower_title = clean_title:lower()

    if id == last_dialog_id and (os.clock() - last_dialog_time) < 2.0 then return false end
    last_dialog_id   = id
    last_dialog_time = os.clock()

    if lower_title:find("xush") or lower_title:find("РґРѕР±СЂРѕ") or
       lower_title:find("yangilik") or lower_title:find("РЅРѕРІРѕСЃС‚Рё") or
       lower_title:find("grand mobile") then
        sendDialogResponse(id, 1, 0, ""); return false
    end

    if lower_title:find("avtorizatsiya") or lower_title:find("РїР°СЂРѕР»СЊ") then
        sendDialogResponse(id, 1, 0, cfg.settings.password)
        if not is_logged_in then
            is_logged_in = true
            newTask(function()
                wait(4000); spawn()
                wait(2000); spawn()
                wait(3000)
                sendInput("/az"); wait(1500)
                sendInput("/acceptgnews"); wait(1500)
                sendInput("/sp")
                sendTG("рџ“° O'yinga kirdi!")
                startWandering()
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

-- =================================================
--           ULANISH EVENTLARI
-- =================================================

function onConnectionClosed()
    stopWandering()
    is_logged_in  = false
    is_spectating = false
    sendTG("вќЊ Bot serverdan uzildi.")
    newTask(function()
        wait(15000)
        connect()
        sendTG("рџџў Qayta ulanmoqda...")
    end)
end

function onExit()
    ini.save(cfg, "settings\\config.txt")
end

-- =================================================
--           ASOSIY YUKLASH
-- =================================================

function onLoad()
    local update_ok, update_msg = pcall(updater.checkAndUpdate)
    if update_ok and update_msg then
        sendTG(update_msg)
    end
    if not checkLicense(true) then
        print("[LITSENZIYA] Ruxsat berilmagan nick yoki GitHub mavjud emas. Bot ishga tushmadi.")
        return
    end
    if isRPNick(bot_name) then
        loadMemory()
        loadFAQFromFile()
        telegramPolling()
        checkUpdates()

        if os.time() - faq_last_update > FAQ_UPDATE_INTERVAL then
            newTask(function()
                wait(20000) -- bot avval to'liq ishga tushib olsin
                updateFAQFromWeb()
            end)
        end

        newTask(function()
            while true do
                wait(1000)

                local idle = os.time() - last_activity

                -- ===== SP VA WANDERING BOSHQARUVI =====
                if is_spectating then
                    -- 120 soniyada yangi SP ga o'tadi, CHIQMAYDI
                    if os.time() - sp_timer > 120 then
                        spectateRandomPlayer()
                    end
                elseif #sp_queue > 0 then
                    -- Navbatdagi shikoyat SP
                    local tid = table.remove(sp_queue, 1)
                    sendInput("/sp " .. tid)
                    is_spectating = true
                    sp_timer      = os.time()
                    last_activity = os.time()
                    stopWandering()
                    sendTG("рџ‘Ѓ SP: `" .. tid .. "` ID kuzatilmoqda.")
                elseif not is_wandering then
                    -- Na SP, na wandering вЂ” 5 sekunddan keyin wandering
                    if idle > 5 then
                        startWandering()
                    end
                else
                    -- Wandering yoqiq вЂ” 20 sekunddan keyin SP ga o'tish
                    if os.time() - wander_timer > 20 then
                        stopWandering()
                        spectateRandomPlayer()
                    end
                end

                -- ===== REPORT NAVBATI =====
                if #report_queue > 0 then
                    local task = table.remove(report_queue, 1)
                    sendInput("/ans " .. task.id .. " " .. task.reply)

                    local today = os.date("%d.%m")
                    cfg.daily_logs[today .. "_rep"] = (tonumber(cfg.daily_logs[today .. "_rep"]) or 0) + 1
                    ini.save(cfg, "settings\\config.txt")

                    wait(500)
                    sendInput("/re " .. task.id)
                    sendTG(
                        "вњ… *Javob Berildi:*\n" ..
                        "рџ‘¤ `" .. task.name .. " [" .. task.id .. "]`\n" ..
                        "вќ“ `" .. task.text .. "`\n" ..
                        "рџ¤– `" .. task.reply .. "`"
                    )
                    wait(1500)
                end
            end
        end)

        print("[BOT] " .. bot_name .. " v4.5 Ishga tushdi!")
        sendTG(
            "рџџў *Bot Ishga Tushdi! (v4.5)*\n" ..
            "рџ‘¤ Ism: `" .. bot_name .. "`"
        )
    else
        print("[XATO] Bot nomi noto'g'ri: " .. bot_name)
    end
end
-- === KOD TUGASHI ===
