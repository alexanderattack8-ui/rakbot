-- === KOD BOSHLANISHI (admin.lua v9.5 - TO'LIQ YOYILGAN VA AI FIX) ===
require("addon")
local updater = require("updater")
local sampev = require("samp.events")
local ini = require("inicfg")
local requests = require("requests")
local json = require("cjson")

math.randomseed(os.time())
local atan2 = math.atan2 or math.atan 

-- ================= VERSIYA =================
local script_version = 9.5
local script_name_file = "admin.lua"
local update_info_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/version.json"

-- ================= XAVFSIZ UZILISH VA ULANISH =================
local function botDisconnect()
    pcall(function()
        if type(disconnect) == "function" then 
            disconnect()
        elseif type(reconnect) == "function" then 
            reconnect(9999999)
        elseif type(runCommand) == "function" then 
            runCommand("!disconnect")
        end
    end)
end

local function botConnect()
    pcall(function()
        if type(connect) == "function" then 
            connect()
        elseif type(reconnect) == "function" then 
            reconnect(500)
        elseif type(runCommand) == "function" then 
            runCommand("!reconnect")
        end
    end)
end

-- ================= CONFIG =================
local cfg = ini.load({
    settings = {
        bot_name = "",
        token = "",
        chatid = "",
        password = "",
        gemini_key = "",
        report_delay = "12",
    },
    daily_logs = {
        start_time = os.time()
    },
    admin_stats = {
        data = "{}"
    },
    faq_meta = {
        last_update = 0
    }
}, "settings\\config.txt")

local bot_name = tostring(cfg.settings.bot_name):match("^%s*(.-)%s*$") or ""
local bot_token = tostring(cfg.settings.token):match("^%s*(.-)%s*$") or ""
local bot_chatid = tostring(cfg.settings.chatid):match("^%s*(.-)%s*$") or ""
local gemini_key = tostring(cfg.settings.gemini_key):match("^%s*(.-)%s*$") or ""
local report_delay = tonumber(cfg.settings.report_delay) or 12

-- Admin statistikasini xotiraga o'qish
local admin_statistics = {}
pcall(function()
    if cfg.admin_stats.data and cfg.admin_stats.data ~= "" then
        admin_statistics = json.decode(cfg.admin_stats.data)
    end
end)

local function saveAdminStats()
    pcall(function()
        cfg.admin_stats.data = json.encode(admin_statistics)
        ini.save(cfg, "settings\\config.txt")
    end)
end

-- ================= AZ ZONE KOORDINATALARI =================
local az_min_x = -745.7576
local az_max_x = -696.5170
local az_min_y = -2460.6765
local az_max_y = -2411.3794
local az_z = 1198.1488

-- ================= LITSENZIYA =================
local license_url = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/licenses.txt"
local license_check_interval = 6 * 60 * 60
local license_grace = 24 * 60 * 60 
local license_ok = false
local license_last_check = 0
local license_last_ok = 0
local license_fail_reason = "tekshirilmagan"
local license_stopped = false

local function normalizeNick(n)
    local s = tostring(n or ""):lower():gsub("%s+", "")
    return s
end

local function checkLicense(force)
    if bot_name == "" then
        license_ok = false
        license_fail_reason = "config.txt da bot_name bo'sh"
        return false
    end
    
    if not force and os.time() - license_last_check < license_check_interval then
        return license_ok
    end
    
    license_last_check = os.time()
    
    local ok, res = pcall(function()
        return requests.get(license_url, { timeout = 8 })
    end)
    
    if not ok or not res or res.status_code ~= 200 then
        if license_last_ok > 0 and os.time() - license_last_ok < license_grace then
            license_ok = true
            license_fail_reason = "GitHub javob bermadi (grace rejimi)"
            return true
        end
        license_ok = false
        license_fail_reason = "GitHub litsenziya fayli ochilmadi"
        return false
    end
    
    local wanted = normalizeNick(bot_name)
    license_ok = false
    
    for line in tostring(res.text):gmatch("[^\r\n]+") do
        line = line:gsub("#.*$", "")
        line = line:match("^%s*(.-)%s*$")
        
        if line ~= "" and normalizeNick(line) == wanted then
            license_ok = true
            break
        end
    end
    
    if license_ok then
        license_last_ok = os.time()
        license_fail_reason = "ok"
    else
        license_fail_reason = "nick litsenziyada yo'q"
    end
    
    return license_ok
end

local function licenseGuard()
    if checkLicense(false) then 
        return true 
    end
    print("[LITSENZIYA] Ishlash to'xtatildi: " .. license_fail_reason)
    return false
end

-- ================= FAYL YO'LLARI VA WEB APP =================
local memory_file = "settings\\memory_base.json" 
local old_memory_file = "settings\\" .. bot_name:lower() .. "_memory.json" 
local faq_file = "settings\\faq_base.json"
local web_log_file = "settings\\web_logs.json"

local web_logs = {}
local MAX_LOGS = 150

-- ================= O'ZGARUVCHILAR =================
local bot_memory = {}
local faq_base = {}
local pending_reports = {}
local report_queue = {}
local sp_queue = {}
local pending_admin_mirrors = {}

local is_spectating = false
local sp_timer = 0
local is_wandering = false
local wandering_enabled = true 
local waiting_for_grnd_bot_id = false 
local last_activity = os.time()

local az_target_x = 0
local az_target_y = 0
local bot_state = "idle" 
local state_timer = 0
local angle = 0
local current_speed = 0

local is_hiding = false
local sleep_end_time = 0
local is_paused = false 

local tg_capture_timer = nil
local is_mp_active = false
local ai_busy = false
local is_logged_in = false
local last_login_time = 0 
local last_heal_time = 0

local active_chat_admin = nil
local active_chat_time = 0
local chat_timeout_seconds = 60
local last_dialog_id = -1
local last_dialog_time = 0

local checking_admins = false
local checking_admins_auto = false
local online_admins_table = {}
local old_admins_table = {}
local checking_stats_for_tg = false

local current_stat_id = nil
local faq_last_update = tonumber(cfg.faq_meta.last_update) or 0
local faq_updating = false
local base_ok = true
local base_error_sent = false

local FAQ_UPDATE_INTERVAL = 7 * 86400
local PENDING_TTL = 1800 

-- ================= YUQORI ADMINLAR RO'YXATI =================
local red_admins = {
    ["John_Medvedev"] = true,
    ["Asilbek_Imanov"] = true,
    ["Ivan_Vasilyev"] = true,
    ["Felix_Hatred"] = true,
    ["Maga_By"] = true
}

-- ================= GRND RASMIY QOIDALAR BAZASI (TO'LIQ) =================
local grnd_rules_database = {
    ["1.2"] = "Akkaunt yoki shaxsni ma'muriyat/dasturchi deb ko'rsatish: 3-7 kun ban. Jiddiy holatda 31 kun ban.",
    ["1.3"] = "Qoidalardagi bo'shliqlardan foydalanishga urinish: 3-31 kun ban.",
    ["2.1"] = "O'yinchini haqorat qilish: 15-30 daqiqa Mute. Qarindoshlar haqida eslatish: 90-180 daqiqa Mute. Qarindoshlarni haqorat qilish: 3-10 kun ban.",
    ["2.2"] = "Giyohvandlik, pornografiya, ekstremizm targ'iboti: 3-14 kundan doimiy ban gacha.",
    ["2.3"] = "Har qanday reklama (sayt, guruh, kanal): 60-120 daqiqa Mute yoki 31 kun ban.",
    ["2.4"] = "Irqchilik, dinni haqorat qilish, siyosat: 60-180 daqiqa Mute yoki 1-31 kun ban.",
    ["2.5"] = "Mikrofonda musiqa, baqiriq, shovqin yaratish: 20-60 daqiqa Mute.",
    ["2.6"] = "IC va OOC nizolarini real hayotga o'tkazish, tahdid: 7 kundan doimiy bangacha.",
    ["3.1"] = "Hisobni asossiz ishlatish, valyuta so'rash: Ogohlantirish / 30 daqiqagacha Mute.",
    ["3.2"] = "Ma'muriyatni haqorat qilish, aldash: 30-60 daqiqa Mute yoki 3-31 kun ban.",
    ["3.3"] = "Ma'muriyat ishiga aralashish, provokatsiya: Ogohlantirish yoki 60 daqiqa Demorgan.",
    ["3.4"] = "Ma'muriyat harakatlarini muhokama qilish, trolling: 60 daqiqa Mute yoki 1-5 kun ban.",
    ["4.1"] = "Valyuta manipulyatsiyasi, firibgarlik, sotish/sotib olish: 3-7 kundan 31 kun/doimiy bangacha.",
    ["4.2"] = "Tahdid ostida qimmatbaho narsalarni tortib olish: 7-31 kun ban.",
    ["4.4"] = "Real pulga o'yin mulki/valyutasini sotish/sotib olish: 31 kundan doimiy bangacha ban.",
    ["4.5"] = "Kuniga 30,000,000 rubldan ortiq beg'araz pul o'tkazish: Mulkni qaytarish yoki 31 kun ban.",
    ["4.7"] = "Serverlar o'rtasida mulk/valyuta o'tkazish: 31 kun ban + mulkni qaytarish.",
    ["5.2"] = "Chit, avtokliker, makrolar, botlar va uchinchi tomon dasturlari: Bagoyuz uchun 3 kungacha ban; Avtokliker uchun 3-7 kun ban; Chit tarqatish/ishlatish uchun 7-31 kun ban.",
    ["5.3"] = "RP vaziyatidan qochish, AFKga qochish: 60 daqiqagacha Demorgan.",
    ["5.4"] = "Uy yoki kvartira kirish qismida (GZ yaqinida) odam o'ldirish: 120 daqiqa Demorgan.",
    ["gz"] = "Yashil zonada (GZ) odam o'ldirish va zarar yetkazish taqiqlanadi: 60 daqiqa Demorgan + Ogohlantirish.",
    ["db"] = "DriveBy (mashinadan turib otish yoki urib yuborish): 30 daqiqagacha Demorgan.",
    ["sk"] = "Spawn Kill (tug'ilgan joyida o'ldirish): 60-120 daqiqa Demorgan. Ommaviy SK uchun Ogohlantirish va 3 kun ban.",
    ["rk"] = "Qasos olish uchun o'ldirish (20 daqiqa ichida o'lgan joyiga qaytish): 30 daqiqagacha Demorgan.",
    ["tk"] = "Team Kill (o'z faction/oila a'zosini o'ldirish): 30 daqiqa Demorgan yoki Ogohlantirish.",
    ["dm"] = "DeathMatch (asossiz o'ldirish): 60 daqiqagacha Demorgan."
}

-- ================= FAQ BO'LIMLARI =================
local faq_sections = {
    { 
        name = "Yordam markazi", 
        url = "https://support.grnd.gg/ru/" 
    }
}

-- ================= SO'KINISHLAR LUG'ATI =================
local exact_bad_words = {
    "am", "ami", "amiga", "amini", "aminga", "amingni", "aming", "amlar",
    "kot", "koti", "kotiga", "kotini", "kotinga", "kotingni", "koting", "kotlar",
    "sik", "sikay", "sikaman", "sikamiz", "sikdi", "sikib", "sikiw", "sikish",
    "jlb", "skn", "jala", "chort", "qoto", "skay"
}

local partial_bad_words = {
    "dalbayob", "dalba", "suka", "blyat", "naxuy", "pidar", "gandon", 
    "haromi", "qanjiq", "jalab", "qotog", "ambal", "haqorat"
}

local function containsBadWord(text)
    if not text then 
        return false 
    end
    
    local lower_text = text:lower()
    local clean_text = " " .. lower_text:gsub("[%p%c]", " ") .. " "
    
    for _, bw in ipairs(exact_bad_words) do
        if clean_text:find(" " .. bw .. " ", 1, true) then
            return true
        end
    end
    
    for _, bw in ipairs(partial_bad_words) do
        if clean_text:find(" " .. bw, 1, true) then
            return true
        end
    end
    
    return false
end

-- ================= AVTOMATIK JAVOBLAR =================
local REP_EVAK = "Assalomu aleykum, spidometrdagi evakuator tugmasini bosing."
local REP_SHIK = "Assalomu aleykum, dalil bilan shikoyat yozing."
local REP_WARN = "Assalomu alaykum, planshet orqali yoki statistika bo'limidan bilib olishingiz mumkin."
local REP_NAVI = "Assalomu alaykum, planshetni ochib navigator tugmasini bosing."

local auto_replies = {
    ["qachon warn"] = REP_WARN,
    ["warn qachon"] = REP_WARN,
    ["qancha warn"] = REP_WARN,
    ["tuzatib bering"] = REP_EVAK,
    ["remont"] = REP_EVAK,
    ["buzildi"] = REP_EVAK,
    ["tutayapti"] = REP_EVAK,
    ["pochinit"] = REP_EVAK,
    ["moshinam"] = REP_EVAK,
    ["tiqilib qoldi"] = REP_EVAK,
    ["stuck"] = REP_EVAK,
    ["evakuator"] = REP_EVAK,
    ["nega qamadingiz"] = REP_SHIK,
    ["meni aybim yo'q"] = REP_SHIK,
    ["sababsiz"] = REP_SHIK,
    ["yeching"] = "Assalomu alaykum, administrator bunday jarayonlarga aralashmaydi.",
    ["pul bering"] = "Assalomu alaykum, keyingi off-top uchun jazo qo'llaniladi."
}

-- ================= RUXSAT ETILGAN BUYRUQLAR =================
local allowed_cmds = {
    ["/ban"] = true, ["/offban"] = true, ["/warn"] = true, ["/offwarn"] = true,
    ["/kick"] = true, ["/mute"] = true, ["/rmute"] = true, ["/offmute"] = true,
    ["/unmute"] = true, ["/offunmute"] = true, ["/jail"] = true, ["/unjail"] = true,
    ["/freeze"] = true, ["/unfreeze"] = true, ["/slap"] = true, ["/slay"] = true,
    ["/spec"] = true, ["/unspec"] = true, ["/spoff"] = true, ["/setworld"] = true, 
    ["/goto"] = true, ["/gethere"] = true, ["/bring"] = true, ["/akick"] = true, 
    ["/aban"] = true, ["/amute"] = true, ["/awarn"] = true
}

-- ================= YORDAMCHI FUNKSIYALAR =================
local function normText(s)
    local t = tostring(s or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ")
    return t:match("^%s*(.-)%s*$") or ""
end

local auto_replies_norm = {}
for k, v in pairs(auto_replies) do
    auto_replies_norm[normText(k)] = v
end

local function tgSafe(s)
    local t = tostring(s or ""):gsub("[`*_%[%]]", " ")
    return t
end

local function containsAny(str, list)
    if not str then 
        return false 
    end
    
    for _, w in ipairs(list) do
        if w ~= "" and str:find(w, 1, true) then 
            return true 
        end
    end
    
    return false
end

function isRPNick(name)
    if type(name) ~= "string" then 
        return false 
    end
    
    return string.match(name, "^%u%a+_%u%a+$") ~= nil
end

local function prunePending()
    local now = os.time()
    for k, v in pairs(pending_reports) do
        if type(v) ~= "table" or not v.time or (now - v.time) > PENDING_TTL then
            pending_reports[k] = nil
        end
    end
end

-- ================= AZ PATRUL (SMART MOVEMENT) =================
function getNewAZTarget()
    az_target_x = math.random() * (az_max_x - az_min_x) + az_min_x
    az_target_y = math.random() * (az_max_y - az_min_y) + az_min_y
end

function startWandering()
    getNewAZTarget()
    bot_state = "run"
    is_wandering = true
    is_spectating = false
    last_activity = os.time()
    state_timer = os.time() + math.random(3, 8)
end

function stopWandering()
    is_wandering = false
    bot_state = "idle"
end

local function getDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- ================= XOTIRA FUNKSIYALARI =================
function bazaXato(reason)
    base_ok = false
    
    if base_error_sent then 
        return 
    end
    
    base_error_sent = true
    sendTG("[XATO] *Baza xatosi!*\n`" .. tgSafe(reason) .. "`")
end

function bazaTuzuk()
    base_ok = true
    base_error_sent = false
end

function memAnswer(v)
    if type(v) == "table" then 
        if v[1] then 
            local rand_idx = math.random(1, #v)
            return v[rand_idx].answer
        elseif v.answer then 
            return v.answer 
        end
    end
    return v
end

function readJSONFile(path)
    local f = io.open(path, "r")
    
    if not f then 
        return nil, "fayl topilmadi: " .. path 
    end
    
    local data = f:read("*a")
    f:close()
    
    if not data or data == "" then 
        return nil, "fayl bo'sh: " .. path 
    end
    
    local ok, decoded = pcall(json.decode, data)
    
    if not ok or type(decoded) ~= "table" then 
        return nil, "JSON xato: " .. path 
    end
    
    return decoded
end

function loadMemory()
    bot_memory = {}
    local data, err = readJSONFile(memory_file)
    
    if data then 
        bot_memory = data 
    end

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
            
            if moved > 0 then 
                saveMemory() 
            end
        end
    end
    
    if data == nil and old_data == nil then
        local f = io.open(memory_file, "w")
        if f then 
            f:write("{}") 
            f:close() 
        end
    else
        bazaTuzuk()
    end
end

function saveMemory()
    local ok, err = pcall(function()
        local f = io.open(memory_file, "w")
        if not f then 
            error("yozib bo'lmadi: " .. memory_file, 0) 
        end
        f:write(json.encode(bot_memory))
        f:close()
    end)
    return ok
end

-- ================= FAQ FUNKSIYALARI =================
function stripHTML(html)
    if not html then 
        return "" 
    end
    
    local t = tostring(html)
    t = t:gsub("<br%s*/?>", " ")
    t = t:gsub("<li[^>]*>", "- ")
    t = t:gsub("</li>", " ")
    t = t:gsub("<p[^>]*>", " ")
    t = t:gsub("</p>", " ")
    t = t:gsub("<script.-</script>", " ")
    t = t:gsub("<style.-</style>", " ")
    t = t:gsub("<[^>]+>", "")
    t = t:gsub("&nbsp;", " ")
    t = t:gsub("&#8203;", "")
    t = t:gsub("&lt;", "<")
    t = t:gsub("&gt;", ">")
    t = t:gsub("&quot;", '"')
    t = t:gsub("&#39;", "'")
    t = t:gsub("&#x27;", "'")
    t = t:gsub("&amp;", "&")
    t = t:gsub("%s+", " ")
    
    return t:match("^%s*(.-)%s*$") or ""
end

function loadFAQFromFile()
    faq_base = {}
    local data, err = readJSONFile(faq_file)
    
    if data then
        faq_base = data
    else
        local f = io.open(faq_file, "w")
        if f then 
            f:write("{}") 
            f:close() 
        end
    end
end

function getFAQReply(text)
    if not text or text == "" then 
        return nil 
    end
    
    local lower = normText(text)
    
    if lower == "" then 
        return nil 
    end
    
    -- Qoidalar bazasidan to'g'ridan-to'g'ri qidirish
    for keyword, desc in pairs(grnd_rules_database) do
        if lower:find(keyword, 1, true) then
            return "Assalomu alaykum, GRND qoidasiga ko'ra: " .. desc
        end
    end

    for key, data in pairs(faq_base) do
        if lower == key then 
            return memAnswer(data) 
        end
    end
    
    if lower:len() >= 5 then
        for key, data in pairs(faq_base) do
            if key:len() >= 5 and (lower:find(key, 1, true) or key:find(lower, 1, true)) then
                return memAnswer(data)
            end
        end
    end
    
    local words = {}
    for w in lower:gmatch("%S+") do
        if w:len() > 3 then 
            table.insert(words, w) 
        end
    end
    
    local best = nil
    local best_score = 0
    
    for key, data in pairs(faq_base) do
        local score = 0
        for _, w in ipairs(words) do
            if key:find(w, 1, true) then 
                score = score + 1 
            end
        end
        
        if score > best_score then 
            best_score = score
            best = data 
        end
    end
    
    if best_score >= 2 and best then 
        return memAnswer(best) 
    end
    
    return nil
end

function saveFAQToFile()
    local ok, err = pcall(function()
        local f = io.open(faq_file, "w")
        
        if not f then 
            error("yozib bo'lmadi: " .. faq_file, 0) 
        end
        
        f:write(json.encode(faq_base))
        f:close()
    end)
    return ok
end

function extractArticleTitleAndBody(html)
    if not html then 
        return nil, nil 
    end
    
    local best_title = nil
    local best_body = nil

    for ld in html:gmatch('<script[^>]-application/ld%+json[^>]->(.-)</script>') do
        local ok, data = pcall(json.decode, ld)
        if ok and type(data) == "table" then
            local node = data
            if node[1] then 
                node = node[1] 
            end
            
            local title = node.headline or node.name
            local body = node.articleBody or node.description
            
            if body then
                local clean_body = stripHTML(body)
                if clean_body:len() > 10 then 
                    return title, clean_body 
                end
            end
            best_title = best_title or title
        end
    end

    local title = html:match("<title[^>]*>(.-)</title>")
    
    if title then
        title = stripHTML(title)
        title = title:gsub("%s*|.*$", "")
        title = title:match("^%s*(.-)%s*$")
    end
    
    title = title or best_title

    local body_html = html:match("<article[^>]*>(.-)</article>")
    
    if not body_html then
        body_html = html:match('<div[^>]-class="[^"]-article[^"]-"[^>]*>(.-)</div>%s*</div>')
    end
    
    if body_html then
        local body = stripHTML(body_html)
        if body:len() > 10 then 
            return title, body 
        end
    end
    
    return title, best_body
end

function translateToUzbek(text, is_title)
    if not text or text:match("^%s*$") then 
        return text 
    end
    
    if gemini_key == "" then 
        return nil 
    end

    local limit = 900
    if is_title then
        limit = 100
    end
    
    local prompt = "Quyidagi matnni ruschadan o'zbek tiliga tarjima qil. FAQAT tarjima matnini qaytar, hech qanday izoh, kirish so'zi yoki tirnoq ishlatma."
    local safe_text = text:gsub('"', '')
    safe_text = safe_text:gsub('\\', '')
    safe_text = safe_text:gsub('\n', ' ')
    safe_text = safe_text:gsub('\r', '')
    
    local payload = {
        contents = { 
            { 
                parts = { 
                    { 
                        text = prompt .. "\n\n" .. safe_text 
                    } 
                } 
            } 
        },
        generationConfig = { 
            temperature = 0.2, 
            maxOutputTokens = limit 
        }
    }
    
    local headers = { 
        ["Content-Type"] = "application/json" 
    }
    
    -- AI LINKI YANGILANDI (1.5 FLASH)
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. gemini_key

    local ok, response = pcall(function()
        return requests.post(url, { headers = headers, data = json.encode(payload), timeout = 15.0 })
    end)

    if ok and response then
        if response.status_code == 200 then
            local ok2, data = pcall(json.decode, response.text)
            
            if ok2 and data and data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts and data.candidates[1].content.parts[1] then
                local out = data.candidates[1].content.parts[1].text
                out = out:gsub('^"(.*)"$', "%1")
                return out:match("^%s*(.-)%s*$")
            end
        end
    end
    
    return nil
end

function updateFAQFromWeb(manual)
    if faq_updating then 
        return 
    end
    
    if gemini_key == "" then
        if manual then 
            sendTG("[FAQ] gemini_key yo'q, tarjima qilib bo'lmaydi.") 
        end
        return
    end
    
    faq_updating = true
    
    newTask(function()
        local new_faq = {}
        local total_ok = 0
        local total_fail = 0
        local section_fail = 0
        
        local pages = {}
        local seen_page = {}
        
        local function addPage(url, name)
            if url and not seen_page[url] and #pages < 40 then
                seen_page[url] = true
                table.insert(pages, { url = url, name = name })
            end
        end
        
        for _, section in ipairs(faq_sections) do 
            addPage(section.url, section.name) 
        end

        local articles = {}
        local seen_article = {}
        
        local function addArticle(url, name)
            if not url then 
                return 
            end
            
            local clean = url:gsub("#.*$", "")
            
            if not seen_article[clean] then
                seen_article[clean] = true
                table.insert(articles, { url = clean, section = name })
            end
        end

        local i = 1
        while i <= #pages do
            local page = pages[i]
            i = i + 1
            
            local ok, res = pcall(function() 
                return requests.get(page.url, { timeout = 10 }) 
            end)
            
            if ok and res and res.status_code == 200 then
                local body = tostring(res.text)
                
                for href in body:gmatch('href="(https://support%.grnd%.gg/ru/collections/[^"]+)"') do 
                    addPage(href, page.name) 
                end
                
                for href in body:gmatch('href="(/ru/collections/[^"]+)"') do 
                    addPage("https://support.grnd.gg" .. href, page.name) 
                end
                
                for href in body:gmatch('href="(https://support%.grnd%.gg/ru/articles/[^"]+)"') do 
                    addArticle(href, page.name) 
                end
                
                for href in body:gmatch('href="(/ru/articles/[^"]+)"') do 
                    addArticle("https://support.grnd.gg" .. href, page.name) 
                end
            else
                section_fail = section_fail + 1
            end
            
            wait(800)
        end

        for _, art in ipairs(articles) do
            wait(1500)
            
            local ok2, ares = pcall(function() 
                return requests.get(art.url, { timeout = 10 }) 
            end)
            
            if ok2 and ares and ares.status_code == 200 then
                local rus_title, rus_body = extractArticleTitleAndBody(tostring(ares.text))
                
                if rus_title and rus_body then
                    local uz_title = translateToUzbek(rus_title, true)
                    wait(1000)
                    local uz_body = translateToUzbek(rus_body, false)
                    
                    if uz_title and uz_body and uz_body ~= "" then
                        local key = normText(uz_title)
                        
                        if key ~= "" then
                            new_faq[key] = { answer = uz_body, title = uz_title, url = art.url, section = art.section }
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
            else
                total_fail = total_fail + 1
            end
        end

        if total_ok > 0 then
            faq_base = new_faq
            saveFAQToFile()
            bazaTuzuk()
        end
        
        faq_last_update = os.time()
        cfg.faq_meta.last_update = faq_last_update
        
        pcall(function() 
            ini.save(cfg, "settings\\config.txt") 
        end)
        
        faq_updating = false
        
        if manual then 
            sendTG("[FAQ] Yangilandi. Muvaffaqiyatli: `" .. total_ok .. "` | Xato: `" .. total_fail .. "`") 
        end
    end)
end

-- ================= AI FUNKSIYALARI (GEMINI 1.5 FLASH) =================
function askGemini(system_prompt, user_text)
    if gemini_key == "" or ai_busy then 
        return nil 
    end
    
    ai_busy = true
    
    local safe = tostring(user_text or "")
    safe = safe:gsub('"', '')
    safe = safe:gsub('\\', '')
    safe = safe:gsub('\n', ' ')
    safe = safe:gsub('\r', '')
    
    local payload = {
        contents = { 
            { 
                parts = { 
                    { 
                        text = system_prompt .. "\n\nMatn: " .. safe 
                    } 
                } 
            } 
        },
        generationConfig = { 
            temperature = 0.5, 
            maxOutputTokens = 90 
        }
    }
    
    local headers = { 
        ["Content-Type"] = "application/json" 
    }
    
    -- API LINK TO'LIQ YANGILANDI
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. gemini_key
    
    local ok, response = pcall(function()
        return requests.post(url, { headers = headers, data = json.encode(payload), timeout = 12.0 })
    end)
    
    ai_busy = false
    
    if ok and response then
        if response.status_code == 200 then
            local okd, data = pcall(json.decode, response.text)
            
            if okd and data and data.candidates and data.candidates[1] and data.candidates[1].content and data.candidates[1].content.parts and data.candidates[1].content.parts[1] then
                local out_text = data.candidates[1].content.parts[1].text
                out_text = out_text:gsub("\n", " ")
                return out_text
            end
        end
    end
    
    return nil
end

function getAIChatReply(text, chat_type)
    local prompt = ""
    
    if chat_type == "admin" then
        prompt = string.format("Siz serverda '%s' ismli administratorsiz. Sizning hamkasbingiz hozir admin-chatda yozdi. O'zingizni AI emasdek tutib, qisqa, aniq va do'stona o'zbek tilida javob qaytaring.", bot_name)
    else
        prompt = string.format("Siz serverning administratori '%s' siz. O'yinchi sizga SMS yozdi. Qisqa, tabiiy va do'stona ohangda o'zbek tilida (1 gap) javob bering. DIQQAT: O'yinchilarda / bilan yoziladigan buyruqlar yo'q, ularga /komanda deb maslahat bermang. Link yozmang.", bot_name)
    end
    
    return askGemini(prompt, text)
end

-- ================= AQLLI JAVOB TIZIMI =================
function getSmartReply(text, sender_name)
    if not text or text == "" then 
        return nil 
    end
    
    local lower_text = normText(text)
    
    if lower_text == "" then 
        return nil 
    end

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

    for key, reply in pairs(auto_replies_norm) do
        if key ~= "" and lower_text:find(key, 1, true) then 
            return reply 
        end
    end

    local faq_reply = getFAQReply(text)
    
    if faq_reply then
        local clean = tostring(faq_reply)
        clean = clean:gsub("https?://[%S]+", "")
        clean = clean:gsub("%s+", " ")
        clean = clean:match("^%s*(.-)%s*$")
        
        if clean and clean:len() > 10 then 
            return "Assalomu alaykum, " .. clean:sub(1, 200) 
        end
    end

    local function searchMemory(priority_trusted)
        local function isTrusted(val)
            if type(val) == "table" then
                if val[1] then
                    for _, item in ipairs(val) do 
                        if item.trusted then 
                            return true 
                        end 
                    end
                    return false
                else 
                    return val.trusted or false 
                end
            end
            return false
        end

        if bot_memory[lower_text] then
            local v = bot_memory[lower_text]
            
            if priority_trusted and not isTrusted(v) then 
                return nil 
            end
            
            return memAnswer(v)
        end
        
        if lower_text:len() >= 5 then
            for question, value in pairs(bot_memory) do
                local q = normText(question)
                
                if priority_trusted and not isTrusted(value) then 
                    goto continue_inner 
                end
                
                if q:len() >= 5 and (lower_text:find(q, 1, true) or q:find(lower_text, 1, true)) then 
                    return memAnswer(value) 
                end
                
                ::continue_inner::
            end
        end
        
        local words = {}
        
        for w in lower_text:gmatch("%S+") do
            if w:len() > 3 then 
                table.insert(words, w) 
            end
        end
        
        local best_mem = nil
        local best_mem_score = 0
        
        for question, value in pairs(bot_memory) do
            if priority_trusted and not isTrusted(value) then 
                goto continue_score 
            end
            
            local score = 0
            
            for _, w in ipairs(words) do
                if question:find(w, 1, true) then 
                    score = score + 1 
                end
            end
            
            if score > best_mem_score then
                best_mem_score = score
                best_mem = memAnswer(value)
            end
            
            ::continue_score::
        end
        
        if best_mem_score >= 2 and best_mem then 
            return best_mem 
        end
        
        return nil
    end

    local trusted_reply = searchMemory(true)
    
    if trusted_reply then 
        return trusted_reply 
    end
    
    local normal_reply = searchMemory(false)
    
    if normal_reply then 
        return normal_reply 
    end
    
    return nil
end

function getFallbackReply(rep_text)
    local lower_rep = tostring(rep_text or ""):lower()
    
    if lower_rep:find("qayer") or lower_rep:find("topib") or lower_rep:find("manzil") or lower_rep:find("navigator") then 
        return REP_NAVI
    elseif lower_rep:find("moshin") or lower_rep:find("tuzat") or lower_rep:find("remont") or lower_rep:find("evakuator") then 
        return REP_EVAK
    elseif lower_rep:find("shikoyat") or lower_rep:find("aldadi") or lower_rep:find("urdi") or lower_rep:find("dm ") then 
        return REP_SHIK
    elseif lower_rep:find("ban") or lower_rep:find("warn") or lower_rep:find("mute") or lower_rep:find("jazo") then 
        return REP_WARN
    elseif lower_rep:find("pul") or lower_rep:find("mol") or lower_rep:find("buyum") then 
        return "Assalomu alaykum, administrator o'yinchi mulkiga aralashmaydi."
    elseif lower_rep:find("uy") or lower_rep:find("biznes") then 
        return "Assalomu alaykum, ko'chmas mulk bo'yicha tegishli bo'limga murojaat qiling."
    else 
        return "Assalomu alaykum, savolingizni ko'rib chiqmoqdaman." 
    end
end

-- ================= TELEGRAM FUNKSIYALARI =================
local tg_recent = {}
local TG_DEDUPE = 90

function sendTG(text, force)
    if bot_token == "" or bot_chatid == "" then 
        return 
    end
    
    local msg = tostring(text)
    local now = os.time()
    
    for k, t in pairs(tg_recent) do 
        if now - t > 600 then 
            tg_recent[k] = nil 
        end 
    end
    
    if not force then
        if tg_recent[msg] and (now - tg_recent[msg]) < TG_DEDUPE then 
            return 
        end
    end
    
    tg_recent[msg] = now
    
    local payload = { 
        chat_id = bot_chatid, 
        text = msg, 
        parse_mode = "Markdown" 
    }
    
    local headers = { 
        ["Content-Type"] = "application/json" 
    }
    
    newTask(function()
        pcall(function() 
            requests.post("https://api.telegram.org/bot" .. bot_token .. "/sendMessage", { headers = headers, data = json.encode(payload), timeout = 5 }) 
        end)
    end)
end

function checkUpdates()
    newTask(function()
        local ok, res = pcall(function() 
            return requests.get(update_info_url, { timeout = 5 }) 
        end)
        
        if ok and res and res.status_code == 200 then
            local okd, data = pcall(json.decode, res.text)
            
            if okd and data and tonumber(data.version) and tonumber(data.version) > script_version then
                sendTG("[UPDATE] Yangi versiya mavjud: `v" .. tostring(data.version) .. "` (hozirgi `v" .. tostring(script_version) .. "`)")
            end
        end
    end)
end

function telegramPolling()
    if bot_token == "" or bot_chatid == "" then 
        return 
    end
    
    local update_id = 0
    
    newTask(function()
        while true do
            wait(5000)
            
            if license_stopped then 
                return 
            end
            
            local ok, res = pcall(function() 
                return requests.get("https://api.telegram.org/bot" .. bot_token .. "/getUpdates?offset=" .. (update_id + 1), { timeout = 5 }) 
            end)
            
            if ok and res and res.status_code == 200 then
                local okd, decoded = pcall(json.decode, res.text)
                
                if okd and decoded and decoded.ok and decoded.result and #decoded.result > 0 then
                    for _, update in ipairs(decoded.result) do
                        update_id = update.update_id
                        
                        if update.message and update.message.text and update.message.chat and tostring(update.message.chat.id) == bot_chatid then
                            local txt = update.message.text
                            local low = txt:lower()

                            if txt:match("^/[%w_]+") and low ~= "/stats" then
                                sendInput(txt)
                                sendTG("[TG] Buyruq yuborildi:\n`" .. tgSafe(txt) .. "`")
                                tg_capture_timer = os.clock() + 3.0
                                
                                if low == "/spoff" or low == "/sp" then
                                    newTask(function()
                                        wait(1000)
                                        spawn() 
                                        wait(1000)
                                        
                                        if wandering_enabled then
                                            sendInput("/az")
                                            is_spectating = false
                                            startWandering()
                                        else
                                            waiting_for_grnd_bot_id = true
                                            sendInput("/id grnd_bot")
                                        end
                                    end)
                                end
                                
                            elseif low == "!cmd" then
                                local menyu_text = "*MENYU (v" .. tostring(script_version) .. ")*\n\n"
                                menyu_text = menyu_text .. "`/stats` - Hisobot\n"
                                menyu_text = menyu_text .. "`!astats` - Adminlar statistikasi\n"
                                menyu_text = menyu_text .. "`!run` - Yugurishni yoqish yoki o'chirish\n"
                                menyu_text = menyu_text .. "`!admins` - Onlayn adminlar\n"
                                menyu_text = menyu_text .. "`!spec [id]` - O'yinchini kuzatish\n"
                                menyu_text = menyu_text .. "`!spoff` - Kuzatuvdan chiqish\n"
                                menyu_text = menyu_text .. "`!stats [id]` - O'yinchi statisikasi\n"
                                menyu_text = menyu_text .. "`!delay [sekund]` - Javob vaqtini o'zgartirish\n"
                                menyu_text = menyu_text .. "`!pause` - Cheksiz uxlash\n"
                                menyu_text = menyu_text .. "`!unpause` - Qayta ishlash\n"
                                menyu_text = menyu_text .. "`!pause [daq]` - Vaqtli uxlash\n"
                                menyu_text = menyu_text .. "`!a [matn]` - Admin chat\n"
                                menyu_text = menyu_text .. "`!status` - Bot holati"
                                sendTG(menyu_text)
                                
                            elseif low == "!run" or low == "!patrul" then
                                wandering_enabled = not wandering_enabled
                                
                                if wandering_enabled then
                                    sendTG("🏃‍♂️ *Yugurish rejimi: YOQILDI.*\nBot endi AZ zonada patrul qiladi.")
                                    newTask(function()
                                        sendInput("/spoff")
                                        wait(1000)
                                        spawn()
                                        wait(1000)
                                        sendInput("/az")
                                        is_spectating = false
                                        startWandering()
                                    end)
                                else
                                    sendTG("🛑 *Yugurish rejimi: O'CHIRILDI.*\n`grnd_bot` ID si qidirilmoqda (Anti-AFK uchun)...")
                                    stopWandering()
                                    waiting_for_grnd_bot_id = true
                                    sendInput("/id grnd_bot")
                                end
                                
                            elseif low == "!astats" then
                                local msg = "📊 *KUNLIK ADMINLAR STATISTIKASI:*\n\n"
                                local found = false
                                
                                for admn, st in pairs(admin_statistics) do
                                    found = true
                                    msg = msg .. "👤 *" .. admn .. "*:\n"
                                    msg = msg .. "  • Reportlar: `" .. (st.reports or 0) .. "`\n"
                                    msg = msg .. "  • Jazolar: `" .. (st.punishments or 0) .. "`\n\n"
                                end
                                
                                if not found then 
                                    msg = msg .. "Hozircha bugungi statistika yig'ilmadi." 
                                end
                                
                                sendTG(msg)
                                
                            elseif low == "!spoff" then
                                sendInput("/spoff")
                                newTask(function()
                                    wait(1000)
                                    spawn()
                                    wait(1000)
                                    
                                    if wandering_enabled then
                                        sendInput("/az")
                                        is_spectating = false
                                        startWandering()
                                        sendTG("✅ Kuzatuvdan chiqildi va AZ patrul davom etmoqda.")
                                    else
                                        waiting_for_grnd_bot_id = true
                                        sendInput("/id grnd_bot")
                                        sendTG("✅ Kuzatuvdan chiqildi. `grnd_bot` qidirilmoqda...")
                                    end
                                end)

                            elseif low == "!admins" then
                                checking_admins = true
                                online_admins_table = {}
                                sendInput("/admins")
                                sendTG("⏳ *Adminlar ro'yxati tekshirilmoqda...*")
                                
                                newTask(function()
                                    wait(3000)
                                    checking_admins = false
                                    
                                    if #online_admins_table > 0 then
                                        local msg = "👥 *Onlayn Adminlar:*\n"
                                        for _, a in ipairs(online_admins_table) do 
                                            msg = msg .. "▪️ `" .. a.name .. "` [" .. a.id .. "] - " .. a.lvl .. " lvl\n" 
                                        end
                                        sendTG(msg)
                                    else
                                        sendTG("Hozircha serverda onlayn adminlar yo'q yoki ro'yxat olinmadi.")
                                    end
                                end)
                                
                            elseif txt:match("^!delay%s+(%d+)") then
                                local new_delay = tonumber(txt:match("^!delay%s+(%d+)"))
                                
                                if new_delay and new_delay >= 0 then
                                    report_delay = new_delay
                                    cfg.settings.report_delay = tostring(report_delay)
                                    
                                    pcall(function() 
                                        ini.save(cfg, "settings\\config.txt") 
                                    end)
                                    
                                    sendTG("⏱ *Botning report kutish vaqti o'zgartirildi:* `" .. report_delay .. "` soniya.")
                                end
                                
                            elseif txt:match("^!spec%s+(%d+)") then
                                local spid = txt:match("^!spec%s+(%d+)")
                                sendInput("/sp " .. spid)
                                is_spectating = true
                                sp_timer = os.time()
                                stopWandering()
                                sendTG("👁 `" .. spid .. "` ID kuzatuvga olindi (Spec).")
                                
                            elseif txt:match("^!stats%s+(%d+)") then
                                local tid = txt:match("^!stats%s+(%d+)")
                                checking_stats_for_tg = true
                                sendInput("/check " .. tid)
                                sendTG("📊 `" .. tid .. "` ID bo'yicha ma'lumot so'raldi (O'yindagi javob kutilmoqda...).")
                                
                            elseif low == "/stats" or low == "!stats" then
                                local msg = "*OXIRGI 7 KUNLIK HISOBOT:*\n\n"
                                local now = os.time()
                                
                                for i = 6, 0, -1 do
                                    local d_str = os.date("%d.%m", now - (i * 86400))
                                    local rp = cfg.daily_logs[d_str .. "_rep"] or 0
                                    local jami_daqiqa = tonumber(cfg.daily_logs[d_str .. "_daqiqa"])
                                    local soat_str = ""
                                    
                                    if jami_daqiqa then
                                        soat_str = math.floor(jami_daqiqa / 60) .. "s " .. (jami_daqiqa % 60) .. "d"
                                    else
                                        soat_str = (cfg.daily_logs[d_str .. "_soat"] or 0) .. "s"
                                    end
                                    
                                    msg = msg .. "*" .. d_str .. ":* Rep `" .. rp .. "` | " .. soat_str .. "\n"
                                end
                                
                                sendTG(msg)
                                
                            elseif low == "!pause" then
                                is_paused = true
                                sleep_end_time = 0
                                stopWandering()
                                botDisconnect()
                                sendTG("⏸ *[TIZIM]* Bot to'xtatildi (Pause). Serverdan uzildi.\nYana ishga tushirish uchun `!unpause` deb yozing.")
                                
                            elseif low == "!unpause" then
                                if is_paused then
                                    is_paused = false
                                    botConnect()
                                    sendTG("▶️ *[TIZIM]* Bot qayta ishga tushirildi (Unpause). Serverga ulanmoqda...")
                                else
                                    sendTG("⚠️ Bot onsuz ham ishlab turibdi.")
                                end
                                
                            elseif txt:match("^!pause%s+(%d+)") then
                                local mins = tonumber(txt:match("^!pause%s+(%d+)")) or 0
                                
                                if mins > 0 then
                                    sleep_end_time = os.time() + (mins * 60)
                                    stopWandering()
                                    botDisconnect()
                                    sendTG("[PAUSE] Bot `" .. mins .. "` daqiqaga uxlaydi.")
                                    
                                    newTask(function()
                                        while os.time() < sleep_end_time do 
                                            wait(1000) 
                                        end
                                        
                                        if sleep_end_time ~= 0 then
                                            sleep_end_time = 0
                                            botConnect()
                                            sendTG("[NET] Qayta ulanmoqda...")
                                        end
                                    end)
                                end
                                
                            elseif txt:match("^!a%s+(.+)") then
                                sendInput("/a " .. txt:match("^!a%s+(.+)"))
                                
                            elseif low == "!status" then
                                local idle = os.time() - last_activity
                                local status_msg = "*Bot Holati (v" .. tostring(script_version) .. "):*\n"
                                
                                if is_spectating then
                                    status_msg = status_msg .. "SP: Ha\n"
                                else
                                    status_msg = status_msg .. "SP: Yo'q\n"
                                end
                                
                                if wandering_enabled then
                                    status_msg = status_msg .. "Yugurish: Yoqilgan\n"
                                else
                                    status_msg = status_msg .. "Yugurish: O'chirilgan\n"
                                end
                                
                                if is_wandering then
                                    status_msg = status_msg .. "Harakat: Yugurmoqda\n"
                                else
                                    status_msg = status_msg .. "Harakat: To'xtagan\n"
                                end
                                
                                status_msg = status_msg .. "Oxirgi harakat: `" .. idle .. "` soniya oldin\n"
                                
                                if ai_busy then
                                    status_msg = status_msg .. "AI: Band\n"
                                else
                                    status_msg = status_msg .. "AI: Tayyor\n"
                                end
                                
                                if is_paused then
                                    status_msg = status_msg .. "Pauza holati: To'xtatilgan\n"
                                else
                                    status_msg = status_msg .. "Pauza holati: Ishlamoqda\n"
                                end
                                
                                status_msg = status_msg .. "Kutish vaqti: `" .. report_delay .. "`s"
                                sendTG(status_msg)
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ================= O'YIN ICHIDAGI SINKRONIZATSIYA (AZ PATRUL) =================
function sampev.onSendPlayerSync(data)
    if license_stopped or is_hiding or is_paused then 
        return false 
    end
    
    if is_wandering and wandering_enabled then
        last_activity = os.time()
        
        local bx = data.position.x
        local by = data.position.y
        local bz = data.position.z
        
        if bx == 0 and by == 0 then 
            return { data } 
        end
        
        local dist = getDistance(bx, by, az_target_x, az_target_y)
        
        if dist < 1.5 or os.time() > state_timer then
            getNewAZTarget()
            local rand = math.random(1, 100)
            
            if rand < 25 then
                bot_state = "idle"
                state_timer = os.time() + math.random(2, 5)
            else
                if rand > 75 then
                    bot_state = "sprint"
                elseif rand > 35 then
                    bot_state = "run"
                else
                    bot_state = "walk"
                end
                
                state_timer = os.time() + math.random(5, 12)
            end
        end
        
        local want_jump = false
        
        if bot_state ~= "idle" and math.random(1, 100) > 95 then 
            want_jump = true 
        end
        
        if bot_state == "idle" then
            if want_jump then
                data.keysData = 32
            else
                data.keysData = 0
            end
            
            data.moveSpeed.x = 0
            data.moveSpeed.y = 0
            data.moveSpeed.z = 0
            current_speed = 0
        else
            local target_angle = atan2(az_target_y - by, az_target_x - bx)
            angle = target_angle + (math.random() - 0.5) * 0.15 
            
            if bot_state == "sprint" then
                if want_jump then
                    data.keysData = 40
                else
                    data.keysData = 8
                end
                current_speed = 0.25
            elseif bot_state == "run" then
                if want_jump then
                    data.keysData = 34
                else
                    data.keysData = 2
                end
                current_speed = 0.15
            else
                if want_jump then
                    data.keysData = 34
                else
                    data.keysData = 2
                end
                current_speed = 0.08
            end
            
            data.position.x = bx + math.cos(angle) * current_speed
            data.position.y = by + math.sin(angle) * current_speed
            data.position.z = az_z
        end
        
        return { data }
    end
end

-- ================= RPC KUZATUV DETEKTORI =================
function sampev.onTogglePlayerSpectating(state)
    if is_paused or license_stopped then 
        return 
    end
    
    if state then
        is_spectating = true
        stopWandering()
    else
        is_spectating = false
        newTask(function()
            wait(800)
            spawn() 
            wait(1200)
            
            if wandering_enabled then
                sendInput("/az")
                startWandering()
            else
                waiting_for_grnd_bot_id = true
                sendInput("/id grnd_bot")
            end
        end)
    end
end

-- ================= SAMP EVENTLAR (XABARLAR) =================
function sampev.onServerMessage(color, text)
    if license_stopped or is_paused then 
        return 
    end
    
    local clean = tostring(text):gsub("{......}", "")
    local lower_clean = clean:lower()

    table.insert(web_logs, { time = os.date("%H:%M:%S"), text = clean })
    
    if #web_logs > MAX_LOGS then 
        table.remove(web_logs, 1) 
    end

    -- ================= ADMINLAR STATISTIKASINI YIG'ISH =================
    local ans_admin = clean:match("(%u%a+_%u%a+)%[%d+%]")
    
    if not ans_admin then
        ans_admin = clean:match("(%u%a+_%u%a+)")
    end
    
    if clean:find("ga javob berdi:") then
        if ans_admin then
            if not admin_statistics[ans_admin] then 
                admin_statistics[ans_admin] = { 
                    reports = 0, 
                    punishments = 0 
                } 
            end
            
            admin_statistics[ans_admin].reports = admin_statistics[ans_admin].reports + 1
            saveAdminStats()
        end
    end

    if clean:find("jazoladi") or clean:find("jazo berdi") or clean:find("posadil") or clean:find("zabanil") or clean:find("kiknul") or clean:find("warn") or clean:find("mute") or clean:find("jail") or clean:find("ban") then
        if ans_admin and ans_admin ~= bot_name then
            if not admin_statistics[ans_admin] then 
                admin_statistics[ans_admin] = { 
                    reports = 0, 
                    punishments = 0 
                } 
            end
            
            admin_statistics[ans_admin].punishments = admin_statistics[ans_admin].punishments + 1
            saveAdminStats()
        end
    end

    -- ================= GRND_BOT ID QIDIRUV (ANTI-AFK UCHUN) =================
    if waiting_for_grnd_bot_id then
        if lower_clean:find("grnd_bot") then
            local b_id = clean:match("grnd_bot%s*%[(%d+)%]")
            
            if not b_id then
                b_id = clean:match("grnd_bot%s*%(%d+%)")
            end
            
            if not b_id then
                b_id = clean:match("[Ii][Dd]:%s*(%d+)")
            end
            
            if not b_id then
                b_id = clean:match("%[(%d+)%]")
            end
            
            if b_id then
                waiting_for_grnd_bot_id = false
                sendTG("✅ `grnd_bot` topildi (ID: " .. b_id .. "). Bot endi shuni kuzatib turadi.")
                
                newTask(function()
                    wait(1000)
                    sendInput("/sp " .. b_id)
                    is_spectating = true
                    sp_timer = os.time() + 999999
                end)
            end
            
        elseif lower_clean:find("topilmadi") or lower_clean:find("ne nayden") or lower_clean:find("not found") then
            waiting_for_grnd_bot_id = false
            sendTG("⚠️ `grnd_bot` serverda topilmadi! Yugurish ham o'chirilgan, bot AFK ga tushib qolishi mumkin.")
        end
    end

    -- ================= SMART ANTI-AFK SELF-HEALING =================
    if not is_paused and clean:find(bot_name) and clean:find("AFK %[%d+:%d+%]") then
        local afk_m, afk_s = clean:match(bot_name .. ".-AFK %[(%d+):(%d+)%]")
        
        if afk_m and afk_s then
            local total_sec = tonumber(afk_m) * 60 + tonumber(afk_s)
            
            if total_sec > 15 and (os.time() - last_heal_time) > 60 then
                last_heal_time = os.time()
                
                newTask(function()
                    wait(500)
                    spawn() 
                    wait(1500)
                    
                    if wandering_enabled then
                        sendInput("/az")
                        is_spectating = false
                        startWandering()
                        sendTG("⚠️ *Anti-AFK Tizimi:* Bot AFK ("..total_sec.."s) deb topildi va AZ patrul orqali tiklandi!")
                    else
                        waiting_for_grnd_bot_id = true
                        sendInput("/id grnd_bot")
                        sendTG("⚠️ *Anti-AFK Tizimi:* Bot AFK ("..total_sec.."s) deb topildi va `grnd_bot` orqali tiklanmoqda!")
                    end
                end)
            end
        end
    end

    if tg_capture_timer and os.clock() <= tg_capture_timer then
        if not clean:match("%[%d+%]:") and not clean:match("SMS:") and not clean:match("yozdi:") then
            sendTG("*Server:*\n`" .. tgSafe(clean) .. "`")
            tg_capture_timer = nil
        end
    end
    
    if checking_stats_for_tg and (clean:find("Daraja:") or clean:find("Level:") or clean:find("Hisob:") or clean:find("Ism:")) then
        sendTG("📊 *Statistika:*\n`" .. tgSafe(clean) .. "`")
        
        newTask(function() 
            wait(2000) 
            checking_stats_for_tg = false 
        end)
    end

    if lower_clean:find("hozir mp bo'ladi") or lower_clean:find("ishtirok etish uchun") then
        is_mp_active = true
        sendTG("*MP Boshlandi!*")
    elseif lower_clean:find("g'olib bo'ldi") or lower_clean:find("tadbiri tugadi") then
        is_mp_active = false
        sendTG("*MP Tugadi!*")
    end

    local daqiqa = clean:match("[Bb]ugungi boshqaruv vaqti:%s*(%d+)")
    
    if daqiqa then
        local jami_daqiqa = tonumber(daqiqa)
        local today = os.date("%d.%m")
        cfg.daily_logs[today .. "_daqiqa"] = jami_daqiqa 
        cfg.daily_logs[today .. "_soat"] = math.floor(jami_daqiqa / 60)
        
        pcall(function() 
            ini.save(cfg, "settings\\config.txt") 
        end)
    end

    if clean:find("Shikoyat") then
        local target_id = clean:match("ID:%s*(%d+)")
        
        if target_id then 
            table.insert(sp_queue, target_id) 
        end
    end

    if checking_admins or checking_admins_auto then
        local aname, aid, alvl = clean:match("([%a_]+)%[(%d+)%]%s*|%s*(%d+)%s*darajasi")
        
        if aname then 
            table.insert(online_admins_table, { name = aname, id = aid, lvl = alvl }) 
        end
    end

    -- ================= ADMIN CHAT, JAZOLAR VA AI JAVOB =================
    local adm_chat_name, adm_chat_text = clean:match("<ADM>.-(%a+_%a+)%[%d+%]:%s*(.+)")
    
    if not adm_chat_name then
        adm_chat_name, adm_chat_text = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(.+)")
    end
    
    if adm_chat_name and adm_chat_text and adm_chat_name ~= bot_name then
        local text_lower = adm_chat_text:lower():match("^%s*(.-)%s*$")
        
        if text_lower:find("^%+") or text_lower:find("^qabul") or text_lower:find("^olindi") or text_lower:find("^ok") then
            local specific_id = text_lower:match("%+.-(%d+)")
            
            if specific_id and pending_admin_mirrors[specific_id] then
                pending_admin_mirrors[specific_id].cancelled = true
            else
                for k, v in pairs(pending_admin_mirrors) do 
                    v.cancelled = true 
                end
            end
        end
    end

    local punished_id = nil
    
    if clean:match("jazoladi.-%[(%d+)%]") then
        punished_id = clean:match("jazoladi.-%[(%d+)%]")
    elseif clean:match("jazo berdi.-%[(%d+)%]") then
        punished_id = clean:match("jazo berdi.-%[(%d+)%]")
    elseif clean:match("posadil.-%[(%d+)%]") then
        punished_id = clean:match("posadil.-%[(%d+)%]")
    elseif clean:match("zabanil.-%[(%d+)%]") then
        punished_id = clean:match("zabanil.-%[(%d+)%]")
    elseif clean:match("kiknul.-%[(%d+)%]") then
        punished_id = clean:match("kiknul.-%[(%d+)%]")
    elseif clean:match("vidal.-%[(%d+)%]") then
        punished_id = clean:match("vidal.-%[(%d+)%]")
    elseif clean:match("warn.-%[(%d+)%]") then
        punished_id = clean:match("warn.-%[(%d+)%]")
    elseif clean:match("mute.-%[(%d+)%]") then
        punished_id = clean:match("mute.-%[(%d+)%]")
    elseif clean:match("jail.-%[(%d+)%]") then
        punished_id = clean:match("jail.-%[(%d+)%]")
    elseif clean:match("kick.-%[(%d+)%]") then
        punished_id = clean:match("kick.-%[(%d+)%]")
    elseif clean:match("ban.-%[(%d+)%]") then
        punished_id = clean:match("ban.-%[(%d+)%]")
    end
    
    if punished_id and pending_admin_mirrors[punished_id] then
        pending_admin_mirrors[punished_id].cancelled = true
    end

    local a_name, a_cmd, a_args = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(/[%w]+)%s+(.+)")
    
    if not a_name then 
        a_name, a_cmd, a_args = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(/[%w]+)%s+(.+)") 
    end

    if a_name and a_cmd and a_args and a_name ~= bot_name and not red_admins[a_name] then
        if allowed_cmds[a_cmd:lower()] then
            local fl, ln = a_name:match("^(%a)%a+_(%a+)$")
            
            if fl and ln then
                local cp = fl .. "." .. ln
                local cc = a_cmd
                local ca = a_args
                local target_id = ca:match("^(%d+)")
                
                if target_id then
                    pending_admin_mirrors[target_id] = { cancelled = false }
                    
                    newTask(function()
                        wait(math.random(3000, 5000)) 
                        local token = pending_admin_mirrors[target_id]
                        
                        if token and token.cancelled then
                            sendTG("[FORMA] `" .. tgSafe(target_id) .. "` ID uchun ariza boshqa admin tomonidan qabul qilindi. Bekor qilindi.")
                        else
                            sendInput(cc .. " " .. ca .. " // " .. cp)
                            wait(1000)
                            sendInput("/a + " .. target_id) 
                            sendTG("[JAZO - QABUL QILINDI]\n`" .. tgSafe(cc .. " " .. ca) .. "`")
                        end
                        
                        if pending_admin_mirrors[target_id] == token then 
                            pending_admin_mirrors[target_id] = nil 
                        end
                    end)
                end
            end
        end
    end

    if adm_chat_name and adm_chat_text and adm_chat_name ~= bot_name and not red_admins[adm_chat_name] then
        local first_word = adm_chat_text:lower():match("^(%S+)") or ""
        
        if not allowed_cmds[first_word] then
            local lower_adm = adm_chat_text:lower()
            local talking = false
            
            -- ================= YANGILANGAN ISM TANISH =================
            local my_short_names = { "azim", "azimjon", "qariya", "bot" }
            
            for _, sname in ipairs(my_short_names) do
                if lower_adm:find(sname, 1, true) then
                    talking = true
                    break
                end
            end

            if active_chat_admin == adm_chat_name and (os.time() - active_chat_time) <= chat_timeout_seconds then 
                talking = true 
            end
            
            if talking then
                active_chat_admin = adm_chat_name
                active_chat_time = os.time()
                
                -- SHU YERDA BIRINCHI TELEGRAM XABARI KETADI (100% KAFOLAT)
                sendTG("⏳ *AI o'ylamoqda...*\n👤 Admin: `" .. tgSafe(adm_chat_name) .. "`\n💬 Yozdi: `" .. tgSafe(adm_chat_text) .. "`", true)
                
                local a_nm = adm_chat_name
                local a_tx = adm_chat_text
                
                newTask(function()
                    wait(math.random(5000, 10000)) 
                    local ai_reply = getAIChatReply(a_nm .. " siz haqingizda yozdi: " .. a_tx, "admin")
                    
                    if ai_reply then
                        sendInput("/a " .. ai_reply)
                        -- === AI JAVOBI TELEGRAMGA ===
                        sendTG("🤖 *AI Javob Berdi (Admin Chat):*\n`" .. tgSafe(ai_reply) .. "`") 
                    else
                        -- === API XATOSI TELEGRAMGA ===
                        sendTG("⚠️ *AI javob bera olmadi* (API kalit xato yoki ulanishda muammo).") 
                    end
                end)
            end
        end
    end

    if clean:match("^SMS") or clean:match("yozdi:") then
        local sname, sid = clean:match("(%a+_%a+)%[(%d+)%]")
        
        if sname and sid and isRPNick(sname) and not red_admins[sname] and sname ~= bot_name then
            sendTG("*SMS (" .. tgSafe(sname) .. "):*\n" .. tgSafe(clean))
            
            local s_nm = sname
            local s_id = sid
            local s_msg = clean
            
            newTask(function()
                local umsg = s_msg:gsub(s_nm .. "%[%d+%]", "")
                umsg = umsg:gsub("SMS:", "")
                umsg = umsg:gsub("yozdi:", "")
                
                wait(math.random(2000, 4000))
                local ai_reply = getAIChatReply("O'yinchi SMS yozdi: " .. umsg, "sms")
                
                if ai_reply then 
                    sendInput("/pm " .. s_id .. " " .. ai_reply) 
                end
            end)
        end
    end

    -- DOUBLE ANSWER HIMOYA TIZIMI 
    local tid, ans = nil, nil
    
    if clean:match("<ADM>.-%[%d+%]%s+.-%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)") then
        tid, ans = clean:match("<ADM>.-%[%d+%]%s+.-%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)")
    elseif clean:match("%[A%].-%[%d+%]%s+%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)") then
        tid, ans = clean:match("%[A%].-%[%d+%]%s+%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)")
    elseif clean:match("/ans%s+(%d+)%s+(.+)") then
        tid, ans = clean:match("/ans%s+(%d+)%s+(.+)")
    elseif clean:match("Admin%s+.-%[(%d+)%]:%s*(.+)") then
        tid, ans = clean:match("Admin%s+.-%[(%d+)%]:%s*(.+)")
    elseif clean:match("%[Report%]%s*.-%[(%d+)%]%s+javob:%s*(.+)") then
        tid, ans = clean:match("%[Report%]%s*.-%[(%d+)%]%s+javob:%s*(.+)")
    end
    
    if tid and ans then
        local ans_admin = clean:match("(%u%a+_%u%a+)%[%d+%]") or clean:match("(%u%a+_%u%a+)")
        tid = tostring(tid)
        local pend = pending_reports[tid]
        
        if pend and pend.text then
            local is_bot_ans = (ans_admin == bot_name)
            local is_red_ans = false
            
            if ans_admin and red_admins[ans_admin] then
                is_red_ans = true
            end

            if not is_bot_ans then
                local savol = normText(pend.text)
                local javob = ans:gsub("https?://[%S]+", "")
                javob = javob:gsub("%s+", " ")
                javob = javob:match("^%s*(.-)%s*$") or ans
                
                if savol ~= "" and javob ~= "" then
                    if not bot_memory[savol] then 
                        bot_memory[savol] = {} 
                    end
                    
                    if type(bot_memory[savol]) == "table" and bot_memory[savol].answer then
                        local old_ans = bot_memory[savol]
                        bot_memory[savol] = { old_ans }
                    end
                    
                    local trusted_flag = false
                    
                    if is_red_ans then
                        trusted_flag = true
                    end
                    
                    local fallback_admin = "?"
                    
                    if ans_admin then
                        fallback_admin = ans_admin
                    end
                    
                    table.insert(bot_memory[savol], { answer = javob, admin = fallback_admin, time = os.time(), trusted = trusted_flag })
                    saveMemory()
                end
            end
            
            pending_reports[tid] = nil 
        end
    end

    local closed_id = nil
    
    if clean:match("Report%s+#?(%d+)%s+yopildi") then
        closed_id = clean:match("Report%s+#?(%d+)%s+yopildi")
    elseif clean:match("%[(%d+)%]%s+report.*yopildi") then
        closed_id = clean:match("%[(%d+)%]%s+report.*yopildi")
    elseif clean:match("^/re%s+(%d+)$") then
        closed_id = clean:match("^/re%s+(%d+)$")
    end
    
    if closed_id then
        closed_id = tostring(closed_id)
        pending_reports[closed_id] = nil
    end

    -- ================= REPORTNI QABUL QILISH VA KUTISH =================
    if clean:find("%[Hisobotlar soni:") then
        local rep_name = clean:match("([%a_]+)%[%d+%]:")
        local rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.-)%s*%[Hisobotlar")
        
        if not rep_id then
            rep_id, rep_text = clean:match("%[(%d+)%]:%s*(.+)")
            if rep_text then 
                rep_text = rep_text:gsub("%[Hisobotlar.-%]", "") 
            end
        end
        
        if rep_id and rep_text then
            if not rep_name then
                rep_name = "Noma'lum"
            end
            
            rep_id = tostring(rep_id)
            
            local clean_rep_text = rep_text:match("^%s*(.-)%s*$")
            
            if clean_rep_text then
                rep_text = clean_rep_text
            end
            
            prunePending()
            
            pending_reports[rep_id] = { text = rep_text, time = os.time() }
            sendTG("🔔 *YANGI REPORT KELDI!*\n👤 O'yinchi: `" .. tgSafe(rep_name) .. "` (ID: " .. rep_id .. ")\n💬 Matn: `" .. tgSafe(rep_text) .. "`")

            local lower_rep = rep_text:lower():match("^%s*(.-)%s*$") or ""
            local is_plus = (lower_rep:match("^[+%s]+$") ~= nil)
            
            local is_flipped = false
            if lower_rep:find("ag'dar") or lower_rep:find("agdar") or lower_rep:find("to'ntar") or lower_rep:find("tontar") or lower_rep:find("flip") or lower_rep:find("korjom") or lower_rep:find("g'ildirak") then
                is_flipped = true
            end
            
            local is_bad = containsBadWord(rep_text) 

            if not is_plus then
                local q_id = rep_id
                local q_name = rep_name
                local q_text = rep_text
                
                newTask(function()
                    if is_mp_active then
                        wait(math.random(4000, 7000))
                        table.insert(report_queue, { id = q_id, reply = "Assalomu aleykum, iltimos kuting.", name = q_name, text = q_text })
                        return
                    end

                    local final_reply = nil
                    
                    if is_flipped then
                        wait(math.random(1500, 3000))
                        
                        if not pending_reports[q_id] then 
                            return 
                        end 
                        
                        sendInput("/flip " .. q_id)
                        final_reply = "Assalomu alaykum, mashinangizni to'g'rilab qo'ydim. Ehtiyotkorroq haydang."
                        
                    elseif is_bad then
                        local text_len = string.len(q_text)
                        wait(math.random(2000, 4000) + (text_len * 20))
                        
                        if not pending_reports[q_id] then 
                            return 
                        end 
                        
                        final_reply = "Assalomu alaykum, server qoidalarini buzmang."
                        sendTG("⚠️ *DIQQAT! So'kinish ushlandi:*\n👤 O'yinchi: `" .. tgSafe(q_name) .. "`\n💬 Matn: `" .. tgSafe(q_text) .. "`", true)
                        
                    else
                        wait(report_delay * 1000)
                        
                        if not pending_reports[q_id] then 
                            return 
                        end 
                        
                        final_reply = getSmartReply(q_text, q_name)
                        
                        if not final_reply then
                            local prompt = string.format([[Siz SA-MP serverida "%s" ismli administratorsiz. O'yinchi savoli: "%s".
QOIDALAR:
1. Bitta gapda, qisqa o'zbek tilida javob bering. Har doim bir xil salomlashmang.
2. O'yinchilar uchun / (slash) bilan yoziladigan buyruqlar UMMUMAN YO'Q! Shuning uchun hech qachon /komanda (masalan /works, /gps, /donate) maslahat bermang.
3. Link ishlatmang.]], bot_name, q_text)
                            
                            final_reply = askGemini(prompt, q_text)
                            
                            if final_reply then 
                                final_reply = final_reply:gsub("https?://[%S]+", "")
                                final_reply = final_reply:gsub("%s+", " ")
                                final_reply = final_reply:match("^%s*(.-)%s*$") 
                            end
                            
                            if not final_reply or final_reply == "" or string.len(final_reply) < 4 then 
                                final_reply = getFallbackReply(q_text) 
                            end
                        end
                    end

                    if pending_reports[q_id] then
                        if final_reply and final_reply:find("kuzat") and not is_bad then
                            local eid = q_text:match("(%d+)")
                            
                            if eid then 
                                table.insert(sp_queue, eid) 
                            end
                        end
                        
                        table.insert(report_queue, { id = q_id, reply = final_reply, name = q_name, text = q_text })
                    end
                end)
            end
        end
    end

    if clean:find("yangiliklari uchun ariza paydo bo'ldi") and clean:find("/acceptgnews") then
        newTask(function() 
            wait(1000) 
            sendInput("/acceptgnews") 
        end)
    end
end

-- ================= DIALOG VA KIRISH MANTIG'I =================
local dialog_pass_keys = { 
    "avtorizatsiya", 
    "parol", 
    "\\239\\224\\240\\238\\235\\252", 
    "\\208\\191\\208\\176\\209\\128\\208\\190\\208\\187\\209\\140" 
}
local dialog_welcome_keys = { 
    "xush", 
    "yangilik", 
    "grand mobile", 
    "\\228\\238\\225\\240\\238" 
}

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if license_stopped then 
        return 
    end
    
    local clean_title = tostring(title):gsub("{......}", "")
    local clean_text = tostring(text):gsub("{......}", "")
    local lower_title = clean_title:lower()
    local is_input = false
    
    if style == 1 or style == 3 then
        is_input = true
    end

    if id == last_dialog_id and (os.clock() - last_dialog_time) < 2.0 then 
        return false 
    end
    
    last_dialog_id = id
    last_dialog_time = os.clock()
    
    if checking_stats_for_tg then
        sendTG("📊 *Statistika (ID: " .. id .. "):*\n`" .. tgSafe(clean_text) .. "`")
        checking_stats_for_tg = false
        sendDialogResponse(id, 1, 0, "")
        return false
    end

    if containsAny(lower_title, dialog_welcome_keys) then
        sendDialogResponse(id, 1, 0, "")
        return false
    end

    if containsAny(lower_title, dialog_pass_keys) then
        sendDialogResponse(id, 1, 0, tostring(cfg.settings.password))
        
        if not is_logged_in and (os.time() - last_login_time) > 60 then
            is_logged_in = true
            last_login_time = os.time()
            
            newTask(function()
                wait(4000)
                spawn()
                wait(2000)
                spawn()
                wait(3000)
                
                if wandering_enabled then
                    sendInput("/az") 
                    wait(1500)
                    sendInput("/acceptgnews")
                    wait(2000)
                    sendTG("🏃‍♂️ [OK] O'yinga kirdi va AZ zonada patrul boshladi!")
                    startWandering()
                else
                    sendInput("/acceptgnews")
                    wait(2000)
                    waiting_for_grnd_bot_id = true
                    sendInput("/id grnd_bot")
                    sendTG("🏃‍♂️ [OK] O'yinga kirdi, `grnd_bot` qidirilmoqda...")
                end
            end)
        end
        
        return false
    end

    if clean_title:find("Arizani tasdiqlash") then
        local auth_code = clean_text:match("kalitni kiriting:%s*(%d%d%d%d)")
        
        if auth_code then 
            sendDialogResponse(id, 1, 0, auth_code)
            return false 
        end
    end

    if is_input and not current_stat_id and not clean_title:find("Arizani tasdiqlash") then
        local code = clean_text:match("(%d%d%d%d%d)")
        
        if code then 
            sendDialogResponse(id, 1, 0, code)
            return false 
        end
    end

    if current_stat_id then 
        sendDialogResponse(id, 0, 0, "")
        return false 
    end
end

-- ================= ULANISH EVENTLARI =================
function onConnectionClosed()
    stopWandering()
    is_logged_in = false
    is_spectating = false
    sendTG("[NET] Bot serverdan uzildi.")
    
    if license_stopped or is_paused or sleep_end_time > os.time() then 
        return 
    end
    
    newTask(function()
        wait(15000)
        
        if license_stopped or is_paused or sleep_end_time > os.time() then 
            return 
        end
        
        botConnect()
    end)
end

function onExit() 
    pcall(function() 
        ini.save(cfg, "settings\\config.txt") 
    end) 
end

-- ================= ASOSIY YUKLASH =================
function onLoad()
    pcall(updater.checkAndUpdate, script_version)
    
    if not isRPNick(bot_name) then 
        print("[XATO] Bot nomi noto'g'ri (RP): " .. tostring(bot_name))
        return 
    end
    
    if not checkLicense(true) then 
        print("[LITSENZIYA] Bot ishga tushmadi: " .. tostring(license_fail_reason))
        license_stopped = true
        return 
    end

    loadMemory()
    loadFAQFromFile()
    telegramPolling()
    checkUpdates()

    if os.time() - faq_last_update > FAQ_UPDATE_INTERVAL then 
        newTask(function() 
            wait(20000) 
            updateFAQFromWeb(false) 
        end) 
    end

    newTask(function()
        local tick = 0
        while true do
            wait(1000)
            tick = tick + 1
            
            if tick % 120 == 0 and is_logged_in and not is_paused then
                checking_admins_auto = true
                online_admins_table = {}
                sendInput("/admins")
                
                newTask(function()
                    wait(3000)
                    checking_admins_auto = false
                    
                    if #online_admins_table > 0 then
                        local current_map = {}
                        local old_map = {}
                        
                        for _, a in ipairs(online_admins_table) do 
                            current_map[a.name] = true 
                        end
                        
                        for _, a in ipairs(old_admins_table) do 
                            old_map[a.name] = true 
                        end
                        
                        local joined = {}
                        local left = {}
                        
                        for _, a in ipairs(online_admins_table) do 
                            if not old_map[a.name] then 
                                table.insert(joined, a.name) 
                            end 
                        end
                        
                        for _, a in ipairs(old_admins_table) do 
                            if not current_map[a.name] then 
                                table.insert(left, a.name) 
                            end 
                        end

                        if #old_admins_table > 0 then 
                            if #joined > 0 then
                                local norm_joined = {}
                                local high_joined = {}
                                
                                for _, name in ipairs(joined) do
                                    if red_admins[name] then 
                                        table.insert(high_joined, name) 
                                    else 
                                        table.insert(norm_joined, name) 
                                    end
                                end
                                
                                if #high_joined > 0 then 
                                    sendTG("🚨 *DIQQAT! Yuqori admin o'yinga kirdi:* `" .. tgSafe(table.concat(high_joined, ", ")) .. "`", true) 
                                end
                                
                                if #norm_joined > 0 then 
                                    sendTG("🟢 *Admin kirdi:* `" .. tgSafe(table.concat(norm_joined, ", ")) .. "`", true) 
                                end
                            end
                            
                            if #left > 0 then 
                                sendTG("🔴 *Admin chiqdi:* `" .. tgSafe(table.concat(left, ", ")) .. "`", true) 
                            end
                        end
                        
                        old_admins_table = {}
                        
                        for _, a in ipairs(online_admins_table) do 
                            table.insert(old_admins_table, a) 
                        end
                    end
                end)
            end

            if tick % 2 == 0 then
                pcall(function()
                    local f = io.open(web_log_file, "w")
                    if f then 
                        f:write(json.encode(web_logs)) 
                        f:close() 
                    end
                end)
            end

            if tick % 300 == 0 then
                if not licenseGuard() then
                    license_stopped = true
                    stopWandering()
                    botDisconnect()
                    return
                end
                prunePending()
            end

            if sleep_end_time > os.time() or is_paused then
                -- Kutish jarayoni
            else
                local idle = os.time() - last_activity

                -- === KUZATISHDAN AZ ZONAGA QAYTISH YADA GRND_BOT NI QIDIRISH MANTIG'I ===
                if is_spectating then
                    -- Faqat yugurish yoqiq bo'lsagina ma'lum vaqtdan so'ng specdan o'zi chiqadi
                    if wandering_enabled and os.time() - sp_timer > 90 then 
                        sendInput("/spoff") 
                        wait(1000)
                        spawn() 
                        wait(1000)
                        sendInput("/az") 
                        is_spectating = false
                        startWandering() 
                    end
                elseif #sp_queue > 0 then
                    local tid = table.remove(sp_queue, 1)
                    sendInput("/sp " .. tid)
                    is_spectating = true
                    sp_timer = os.time()
                    last_activity = os.time()
                    stopWandering()
                elseif not is_wandering and is_logged_in then
                    -- Yugurish yoqiq bo'lsagina az patrul boshlaydi
                    if wandering_enabled and idle > 5 then 
                        sendInput("/az")
                        startWandering() 
                    end
                end

                if #report_queue > 0 then
                    local task = table.remove(report_queue, 1)
                    
                    if pending_reports[task.id] then
                        local reply = task.reply
                        
                        if not reply or reply == "" or string.len(reply) < 4 then 
                            reply = getFallbackReply(task.text) 
                        end
                        
                        sendInput("/ans " .. tostring(task.id) .. " " .. reply)
                        sendTG("✅ *Bot javob berdi:*\n👤 O'yinchi: `" .. tgSafe(task.name) .. "` (ID: " .. task.id .. ")\n❓ Savol: `" .. tgSafe(task.text) .. "`\n💬 Javob: `" .. tgSafe(reply) .. "`")

                        local today = os.date("%d.%m")
                        local current_rep = tonumber(cfg.daily_logs[today .. "_rep"]) or 0
                        cfg.daily_logs[today .. "_rep"] = current_rep + 1
                        
                        pcall(function() 
                            ini.save(cfg, "settings\\config.txt") 
                        end)

                        wait(500)
                        sendInput("/re " .. tostring(task.id))
                        wait(1500)
                    end
                end
            end
        end
    end)

    print("[BOT] " .. bot_name .. " v" .. tostring(script_version) .. " Ishga tushdi!")
    sendTG("*Bot Ishga Tushdi! (v" .. tostring(script_version) .. ")*", true)
end
-- === KOD TUGASHI ===
