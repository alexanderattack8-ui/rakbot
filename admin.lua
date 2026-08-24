-- === KOD BOSHLANISHI (admin.lua v5.3 - To'liq va Yangilangan) ===
require("addon")
local updater = require("updater")
local sampev = require("samp.events")
local ini = require("inicfg")
local requests = require("requests")
local json = require("cjson")

math.randomseed(os.time())
local atan2 = math.atan2 or math.atan 

-- ================= VERSIYA =================
local script_version = 5.3
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

local bot_name = tostring(cfg.settings.bot_name):match("^%s*(.-)%s*$") or ""
local bot_token = tostring(cfg.settings.token):match("^%s*(.-)%s*$") or ""
local bot_chatid = tostring(cfg.settings.chatid):match("^%s*(.-)%s*$") or ""
local gemini_key = tostring(cfg.settings.gemini_key):match("^%s*(.-)%s*$") or ""

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
        line = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
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
    if checkLicense(false) then return true end
    print("[LITSENZIYA] Ishlash to'xtatildi: " .. license_fail_reason)
    return false
end

-- ================= FAYL YO'LLARI =================
local memory_file = "settings\\memory_base.json" 
local old_memory_file = "settings\\" .. bot_name:lower() .. "_memory.json" 
local faq_file = "settings\\faq_base.json"

-- ================= O'ZGARUVCHILAR =================
local bot_memory = {}
local faq_base = {}
local pending_reports = {}
local report_queue = {}
local sp_queue = {}
local pending_admin_mirrors = {} -- Forma kutish ro'yxati

local is_spectating = false
local sp_timer = 0
local is_wandering = false
local wander_timer = 0
local last_activity = os.time()
local angle = 0
local center_x = 0
local center_y = 0
local current_speed = 0.05
local is_hiding = false
local sleep_end_time = 0

local tg_capture_timer = nil
local is_mp_active = false
local ai_busy = false
local is_logged_in = false
local last_login_time = 0 

local active_chat_admin = nil
local active_chat_time = 0
local chat_timeout_seconds = 60
local last_dialog_id = -1
local last_dialog_time = 0

local checking_admins = false
local online_admins_table = {}
local current_stat_id = nil
local faq_last_update = tonumber(cfg.faq_meta.last_update) or 0
local faq_updating = false
local base_ok = true
local base_error_sent = false
local form_senders = {}

local FAQ_UPDATE_INTERVAL = 7 * 86400
local PENDING_TTL = 1800 

local days_map = {
    Monday = "Dushanba",
    Tuesday = "Seshanba",
    Wednesday = "Chorshanba",
    Thursday = "Payshanba",
    Friday = "Juma",
    Saturday = "Shanba",
    Sunday = "Yakshanba"
}

-- ================= KATTA ADMINLAR =================
local red_admins = {
    ["Maga_By"] = true,
    ["Ivan_Vasilyev"] = true,
    ["John_Medvedev"] = true,
    ["Ace_Alonso"] = true
}

-- ================= FAQ BO'LIMLARI =================
local faq_sections = {
    { name = "Yordam markazi", url = "https://support.grnd.gg/ru/" }
}

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
    ["yeching"] = "Assalomu aleykum, administrator bunday jarayonlarga aralashmaydi.",
    ["pul bering"] = "Assalomu aleykum, keyingi off-top uchun jazo qo'llaniladi.",
    ["qayerda"] = REP_NAVI,
    ["topib ber"] = REP_NAVI,
    ["qanday boraman"] = REP_NAVI,
    ["qanday ishlayman"] = "Assalomu alaykum, bu RP jarayon, o'zingiz bilib olishingiz kerak.",
    ["divot"] = "Assalomu alaykum, savolingizni ko'rib chiqmoqdaman."
}

-- ================= RUXSAT ETILGAN BUYRUQLAR =================
local allowed_cmds = {
    ["/ban"] = true, ["/offban"] = true,
    ["/warn"] = true, ["/offwarn"] = true,
    ["/kick"] = true, ["/mute"] = true,
    ["/rmute"] = true, ["/offmute"] = true,
    ["/unmute"] = true, ["/offunmute"] = true,
    ["/jail"] = true, ["/unjail"] = true,
    ["/freeze"] = true, ["/unfreeze"] = true,
    ["/slap"] = true, ["/slay"] = true,
    ["/spec"] = true, ["/unspec"] = true,
    ["/setworld"] = true, ["/goto"] = true,
    ["/gethere"] = true, ["/bring"] = true,
    ["/akick"] = true, ["/aban"] = true,
    ["/amute"] = true, ["/awarn"] = true
}

-- =================================================
-- YORDAMCHI FUNKSIYALAR
-- =================================================
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
    if not str then return false end
    for _, w in ipairs(list) do
        if w ~= "" and str:find(w, 1, true) then return true end
    end
    return false
end

function isRPNick(name)
    if type(name) ~= "string" then return false end
    return string.match(name, "^%u%a+_%u%a+$") ~= nil
end

function startWandering()
    local bx, by, bz = getBotPosition()
    if bx then
        center_x = bx
        center_y = by
    end
    angle = math.random() * math.pi * 2
    current_speed = 0.05
    is_wandering = true
    is_spectating = false
    last_activity = os.time()
    wander_timer = os.time()
end

function stopWandering()
    is_wandering = false
end

local function prunePending()
    local now = os.time()
    for k, v in pairs(pending_reports) do
        if type(v) ~= "table" or not v.time or (now - v.time) > PENDING_TTL then
            pending_reports[k] = nil
        end
    end
end

-- =================================================
-- XOTIRA FUNKSIYALARI
-- =================================================
function bazaXato(reason)
    base_ok = false
    if base_error_sent then return end
    base_error_sent = true
    sendTG("[XATO] *Baza ishlamayapti!*\n`" .. tgSafe(reason) .. "`")
end

function bazaTuzuk()
    base_ok = true
    base_error_sent = false
end

function memAnswer(v)
    if type(v) == "table" then 
        if v[1] then -- Agar massiv shaklida ko'p javob bo'lsa (random)
            local rand_idx = math.random(1, #v)
            return v[rand_idx].answer
        elseif v.answer then -- Eski bitta javob formati
            return v.answer 
        end
    end
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
        bazaXato("FAQ bazasi o'qilmadi (" .. tostring(err) .. ")")
    end
    local count = 0
    for _ in pairs(faq_base) do count = count + 1 end
    print("[BAZA] FAQ: " .. count .. " ta maqola")
end

function getFAQReply(text)
    if not text or text == "" then return nil end
    local lower = normText(text)
    if lower == "" then return nil end
    for key, data in pairs(faq_base) do
        if lower == key then return memAnswer(data) end
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
    if best_score >= 2 and best then return memAnswer(best) end
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

function extractArticleTitleAndBody(html)
    if not html then return nil, nil end
    local best_title, best_body = nil, nil

    for ld in html:gmatch('<script[^>]-application/ld%+json[^>]->(.-)</script>') do
        local ok, data = pcall(json.decode, ld)
        if ok and type(data) == "table" then
            local node = data
            if node[1] then node = node[1] end
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
        title = title:gsub("%s*|.*$", ""):match("^%s*(.-)%s*$")
    end
    title = title or best_title

    local body_html = html:match("<article[^>]*>(.-)</article>")
        or html:match('<div[^>]-class="[^"]-article[^"]-"[^>]*>(.-)</div>%s*</div>')
    if body_html then
        local body = stripHTML(body_html)
        if body:len() > 10 then return title, body end
    end

    return title, best_body
end

function translateToUzbek(text, is_title)
    if not text or text:match("^%s*$") then return text end
    if gemini_key == "" then return nil end

    local limit = is_title and 100 or 900
    local prompt = "Quyidagi matnni ruschadan o'zbek tiliga tarjima qil. FAQAT tarjima matnini qaytar, hech qanday izoh, kirish so'zi yoki tirnoq ishlatma."

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
            out = out:gsub('^"(.*)"$', "%1")
            return out:match("^%s*(.-)%s*$")
        end
    end
    return nil
end

function updateFAQFromWeb(manual)
    if faq_updating then return end
    if gemini_key == "" then
        sendTG("[FAQ] gemini_key yo'q, tarjima qilib bo'lmaydi.")
        return
    end
    faq_updating = true
    newTask(function()
        local new_faq = {}
        local total_ok, total_fail, section_fail = 0, 0, 0

        local pages, seen_page = {}, {}
        local function addPage(url, name)
            if url and not seen_page[url] and #pages < 40 then
                seen_page[url] = true
                table.insert(pages, { url = url, name = name })
            end
        end
        for _, section in ipairs(faq_sections) do addPage(section.url, section.name) end

        local articles, seen_article = {}, {}
        local function addArticle(url, name)
            if not url then return end
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
        else
            bazaXato("FAQ saytdan yuklanmadi (bo'lim xato: " .. section_fail .. ", maqola xato: " .. total_fail .. ")")
        end
        faq_last_update = os.time()
        cfg.faq_meta.last_update = faq_last_update
        pcall(function() ini.save(cfg, "settings\\config.txt") end)
        faq_updating = false
        if manual then
            sendTG("[FAQ] Yangilandi. Muvaffaqiyatli: `" .. total_ok .. "` | Xato: `" .. total_fail .. "`")
        end
    end)
end

-- =================================================
-- AI FUNKSIYALARI
-- =================================================
function askGemini(system_prompt, user_text)
    if gemini_key == "" or ai_busy then return nil end
    ai_busy = true
    local safe = tostring(user_text or ""):gsub('"', ''):gsub('\\', '')
    local payload = {
        contents = { { parts = { { text = system_prompt .. "\n\nMatn: " .. safe } } } },
        generationConfig = { temperature = 0.6, maxOutputTokens = 80 }
    }
    local headers = { ["Content-Type"] = "application/json" }
    local url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. gemini_key
    local ok, response = pcall(function()
        return requests.post(url, { headers = headers, data = json.encode(payload), timeout = 6.0 })
    end)
    ai_busy = false
    if ok and response and response.status_code == 200 then
        local okd, data = pcall(json.decode, response.text)
        if okd and data and data.candidates and data.candidates[1] and
           data.candidates[1].content and data.candidates[1].content.parts and
           data.candidates[1].content.parts[1] then
            local out = data.candidates[1].content.parts[1].text:gsub("\n", " ")
            return out
        end
    end
    return nil
end

function getAIChatReply(text, chat_type)
    local prompt = ""
    if chat_type == "admin" then
        prompt = string.format(
            "Siz serverda '%s' ismli administratorsiz. Sizning hamkasbingiz (boshqa admin) hozir admin-chatda siz haqingizda gapirdi. O'zingizni AI emasdek tutib, qisqa, aniq va do'stona o'zbek tilida (maksimum 1-2 gap) javob qaytaring.",
            bot_name
        )
    else
        prompt = string.format(
            "Siz serverning administratori '%s' siz. O'yinchi sizga SMS yozdi. Qisqa, tabiiy va do'stona ohangda o'zbek tilida (1 gap) javob bering. Link yozmang.",
            bot_name
        )
    end
    return askGemini(prompt, text)
end

-- =================================================
-- AQLLI JAVOB TIZIMI
-- =================================================
function getSmartReply(text, sender_name)
    if not text or text == "" then return nil end
    local lower_text = normText(text)
    if lower_text == "" then return nil end

    if lower_text:find("rp") and (lower_text:find("nik") or lower_text:find("nick")) then
        local target_name = text:match("(%u%a+_%u%a+)") or sender_name
        if target_name and target_name ~= "Noma'lum" then
            if isRPNick(target_name) then return "Assalomu alaykum, ha, bu RP nik."
            else return "Assalomu alaykum, yo'q, bu Non-RP (NRP) nik." end
        end
    end

    for key, reply in pairs(auto_replies_norm) do
        if key ~= "" and lower_text:find(key, 1, true) then return reply end
    end

    local faq_reply = getFAQReply(text)
    if faq_reply then
        local clean = tostring(faq_reply):gsub("https?://[%S]+", ""):gsub("%s+", " ")
        clean = clean:match("^%s*(.-)%s*$")
        if clean and clean:len() > 10 then return "Assalomu alaykum, " .. clean:sub(1, 200) end
    end

    local function searchMemory(priority_trusted)
        local function isTrusted(val)
            if type(val) == "table" then
                if val[1] then
                    for _, item in ipairs(val) do if item.trusted then return true end end
                    return false
                else
                    return val.trusted or false
                end
            end
            return false
        end

        if bot_memory[lower_text] then
            local v = bot_memory[lower_text]
            if priority_trusted and not isTrusted(v) then return nil end
            return memAnswer(v)
        end
        if lower_text:len() >= 5 then
            for question, value in pairs(bot_memory) do
                local q = normText(question)
                if priority_trusted and not isTrusted(value) then goto continue_inner end
                if q:len() >= 5 and (lower_text:find(q, 1, true) or q:find(lower_text, 1, true)) then
                    return memAnswer(value)
                end
                ::continue_inner::
            end
        end
        local words = {}
        for w in lower_text:gmatch("%S+") do
            if w:len() > 3 then table.insert(words, w) end
        end
        local best_mem, best_mem_score = nil, 0
        for question, value in pairs(bot_memory) do
            if priority_trusted and not isTrusted(value) then goto continue_score end
            local score = 0
            for _, w in ipairs(words) do
                if question:find(w, 1, true) then score = score + 1 end
            end
            if score > best_mem_score then
                best_mem_score = score
                best_mem = memAnswer(value)
            end
            ::continue_score::
        end
        if best_mem_score >= 2 and best_mem then return best_mem end
        return nil
    end

    local trusted_reply = searchMemory(true)
    if trusted_reply then return trusted_reply end
    local normal_reply = searchMemory(false)
    if normal_reply then return normal_reply end

    return nil
end

function getFallbackReply(rep_text)
    local lower_rep = tostring(rep_text or ""):lower()
    if lower_rep:find("qayer") or lower_rep:find("topib") or lower_rep:find("manzil") or lower_rep:find("navigator") then return REP_NAVI
    elseif lower_rep:find("moshin") or lower_rep:find("tuzat") or lower_rep:find("remont") or lower_rep:find("evakuator") then return REP_EVAK
    elseif lower_rep:find("shikoyat") or lower_rep:find("aldadi") or lower_rep:find("urdi") or lower_rep:find("dm ") then return REP_SHIK
    elseif lower_rep:find("ban") or lower_rep:find("warn") or lower_rep:find("mute") or lower_rep:find("jazo") then return REP_WARN
    elseif lower_rep:find("pul") or lower_rep:find("mol") or lower_rep:find("buyum") then return "Assalomu alaykum, administrator o'yinchi mulkiga aralashmaydi."
    elseif lower_rep:find("uy") or lower_rep:find("biznes") then return "Assalomu alaykum, ko'chmas mulk bo'yicha tegishli bo'limga murojaat qiling."
    elseif lower_rep:find("ish") or lower_rep:find("kasb") then return "Assalomu alaykum, ish haqida ma'lumot olish uchun /works buyrug'ini yozing."
    else return "Assalomu alaykum, savolingizni ko'rib chiqmoqdaman." end
end

-- =================================================
-- TELEGRAM FUNKSIYALARI
-- =================================================
local tg_recent = {}
local TG_DEDUPE = 90

function sendTG(text, force)
    if bot_token == "" or bot_chatid == "" then return end
    local msg = tostring(text)
    local now = os.time()
    for k, t in pairs(tg_recent) do
        if now - t > 600 then tg_recent[k] = nil end
    end
    if not force then
        if tg_recent[msg] and (now - tg_recent[msg]) < TG_DEDUPE then return end
    end
    tg_recent[msg] = now
    local payload = { chat_id = bot_chatid, text = msg, parse_mode = "Markdown" }
    local headers = { ["Content-Type"] = "application/json" }
    newTask(function()
        pcall(function()
            requests.post("https://api.telegram.org/bot" .. bot_token .. "/sendMessage",
                { headers = headers, data = json.encode(payload), timeout = 5 })
        end)
    end)
end

function checkUpdates()
    newTask(function()
        local ok, res = pcall(function() return requests.get(update_info_url, { timeout = 5 }) end)
        if ok and res and res.status_code == 200 then
            local okd, data = pcall(json.decode, res.text)
            if okd and data and tonumber(data.version) and tonumber(data.version) > script_version then
                sendTG("[UPDATE] Yangi versiya mavjud: `v" .. tostring(data.version) .. "` (hozirgi `v" .. tostring(script_version) .. "`)")
            end
        end
    end)
end

-- =================================================
-- SP FUNKSIYASI
-- =================================================
function spectateRandomPlayer()
    local players = {}
    for i = 0, 500 do
        if i ~= getBotId() then
            local ok, name = pcall(getPlayerName, i)
            if ok and type(name) == "string" and name ~= "" and name ~= "Unknown" then
                local is_admin = false
                if red_admins[name] then is_admin = true end
                for _, adm in ipairs(online_admins_table) do
                    if tonumber(adm.id) == i or adm.name == name then is_admin = true; break end
                end
                if not is_admin then table.insert(players, i) end
            end
        end
    end
    local target = (#players > 0) and players[math.random(1, #players)] or math.random(1, 50)
    sendInput("/sp " .. target)
    is_spectating = true
    sp_timer = os.time()
    last_activity = os.time()
    stopWandering()
end

-- =================================================
-- TELEGRAM POLLING
-- =================================================
function telegramPolling()
    if bot_token == "" or bot_chatid == "" then return end
    local update_id = 0
    newTask(function()
        while true do
            wait(5000)
            if license_stopped then return end
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
                            elseif low == "!cmd" then
                                sendTG("*MENYU (v" .. tostring(script_version) .. ")*\n\n`/stats` - Hisobot\n`!reset` - Tozalash\n`!admins` - Onlayn adminlar\n`!forma` - Forma yuborganlar\n`!pause [daq]` - Uxlash\n`!a [matn]` - Admin chat\n`!test [savol]` - Javob testi\n`!faqupdate` - FAQ yangilash\n`!status` - Bot holati")
                            elseif low == "!admins" then
                                checking_admins = true
                                online_admins_table = {}
                                sendInput("/admins")
                                sendTG("[ADM] Adminlar tekshirilmoqda...")
                                newTask(function()
                                    wait(2500)
                                    checking_admins = false
                                    if #online_admins_table == 0 then
                                        sendTG("[ADM] Hozircha onlayn admin topilmadi.", true)
                                    else
                                        table.sort(online_admins_table, function(a, b) return (tonumber(a.lvl) or 0) > (tonumber(b.lvl) or 0) end)
                                        local lines = {}
                                        for _, adm in ipairs(online_admins_table) do
                                            table.insert(lines, "- `" .. tgSafe(adm.name) .. "` [" .. tostring(adm.id) .. "] - " .. tostring(adm.lvl) .. "-daraja")
                                        end
                                        sendTG("*Onlayn adminlar:*\n" .. table.concat(lines, "\n"), true)
                                    end
                                end)
                            elseif low == "!forma" then
                                local lines = {}
                                for nick, cnt in pairs(form_senders) do table.insert(lines, "- `" .. tgSafe(nick) .. "` - `" .. cnt .. "` ta") end
                                sendTG(#lines > 0 and "*Forma yuborganlar:*\n" .. table.concat(lines, "\n") or "Forma yuborgan admin yo'q.")
                            elseif low == "/stats" or low == "!stats" then
                                local msg = "*OXIRGI 7 KUNLIK HISOBOT:*\n\n"
                                local now = os.time()
                                for i = 6, 0, -1 do
                                    local d_str = os.date("%d.%m", now - (i * 86400))
                                    local rp = cfg.daily_logs[d_str .. "_rep"] or 0
                                    local jami_daqiqa = tonumber(cfg.daily_logs[d_str .. "_daqiqa"])
                                    local soat_str = jami_daqiqa and (math.floor(jami_daqiqa / 60) .. "s " .. (jami_daqiqa % 60) .. "d") or ((cfg.daily_logs[d_str .. "_soat"] or 0) .. "s")
                                    msg = msg .. "*" .. d_str .. ":* Rep `" .. rp .. "` | " .. soat_str .. "\n"
                                end
                                sendTG(msg)
                            elseif low == "!reset" then
                                cfg.daily_logs = { start_time = os.time() }
                                pcall(function() ini.save(cfg, "settings\\config.txt") end)
                                sendTG("*Hisobotlar tozalandi!*")
                            elseif txt:match("^!pause%s+(%d+)") then
                                local mins = tonumber(txt:match("^!pause%s+(%d+)")) or 0
                                if mins > 0 then
                                    sleep_end_time = os.time() + (mins * 60)
                                    stopWandering(); disconnect()
                                    sendTG("[PAUSE] Bot `" .. mins .. "` daqiqaga uxlaydi.")
                                    newTask(function()
                                        while os.time() < sleep_end_time do wait(1000) end
                                        if sleep_end_time ~= 0 then
                                            sleep_end_time = 0
                                            connect()
                                            sendTG("[NET] Qayta ulanmoqda...")
                                        end
                                    end)
                                end
                            elseif txt:match("^!a%s+(.+)") then
                                sendInput("/a " .. txt:match("^!a%s+(.+)"))
                            elseif low == "!faqupdate" then
                                sendTG("[FAQ] Yangilash boshlandi...")
                                updateFAQFromWeb(true)
                            elseif low == "!status" then
                                local idle = os.time() - last_activity
                                sendTG("*Bot Holati (v" .. tostring(script_version) .. "):*\nSP: " .. (is_spectating and "Ha" or "Yo'q") .. "\nYurmoqda: " .. (is_wandering and "Ha" or "Yo'q") .. "\nOxirgi harakat: `" .. idle .. "` soniya oldin\nAI: " .. (ai_busy and "Band" or "Tayyor"))
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- =================================================
-- SAMP EVENTLAR
-- =================================================
function sampev.onSendPlayerSync(data)
    if license_stopped or is_hiding then return end
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
            if dist > 15 then angle = atan2(center_y - by, center_x - bx) end
            data.position.x = bx + math.cos(angle) * current_speed
            data.position.y = by + math.sin(angle) * current_speed
            setBotPosition(data.position.x, data.position.y, bz)
        end
        return { data }
    end
end

function sampev.onServerMessage(color, text)
    if license_stopped then return end
    local clean = tostring(text):gsub("{......}", "")
    local lower_clean = clean:lower()

    if tg_capture_timer and os.clock() <= tg_capture_timer then
        if not clean:match("%[%d+%]:") and not clean:match("SMS:") and not clean:match("yozdi:") then
            sendTG("*Server:*\n`" .. tgSafe(clean) .. "`")
            tg_capture_timer = nil
        end
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
        pcall(function() ini.save(cfg, "settings\\config.txt") end)
    end

    if clean:find("Shikoyat") then
        local target_id = clean:match("ID:%s*(%d+)")
        if target_id then table.insert(sp_queue, target_id) end
    end

    if checking_admins then
        local aname, aid, alvl = clean:match("([%a_]+)%[(%d+)%]%s*|%s*(%d+)%s*darajasi")
        if aname then table.insert(online_admins_table, { name = aname, id = aid, lvl = alvl }) end
    end

    -- =================================================
    -- 1. BOSHQA ADMIN FORMANI QABUL QILGANINI TEKSHIRISH
    -- =================================================
    local adm_chat_name, adm_chat_text = clean:match("<ADM>.-(%a+_%a+)%[%d+%]:%s*(.+)")
    if not adm_chat_name then
        adm_chat_name, adm_chat_text = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(.+)")
    end
    
    if adm_chat_name and adm_chat_text and adm_chat_name ~= bot_name then
        local text_lower = adm_chat_text:lower():match("^%s*(.-)%s*$")
        if text_lower == "+" or text_lower:match("^%+%s+%d+") or text_lower == "qabul" or text_lower == "olindi" then
            local specific_id = text_lower:match("^%+%s+(%d+)")
            if specific_id and pending_admin_mirrors[specific_id] then
                pending_admin_mirrors[specific_id].cancelled = true
            else
                for k, v in pairs(pending_admin_mirrors) do v.cancelled = true end
            end
        end
    end

    -- =================================================
    -- 2. SERVER JAZONI E'LON QILGANINI KUZATISH
    -- =================================================
    local punished_id = clean:match("o'yinchini jazoladi.-%[(%d+)%]") or
                        clean:match("jazo berdi.-%[(%d+)%]") or
                        clean:match("used /[%w]+ on.-%[(%d+)%]") or
                        clean:match("kicked.-%[(%d+)%]") or
                        clean:match("banned.-%[(%d+)%]") or
                        clean:match("warned.-%[(%d+)%]") or
                        clean:match("jailed.-%[(%d+)%]") or
                        clean:match("muted.-%[(%d+)%]")
    
    if punished_id and pending_admin_mirrors[punished_id] then
        pending_admin_mirrors[punished_id].cancelled = true
    end

    -- =================================================
    -- 3. FORMANI USHLASH VA KUTISH MANTIG'I
    -- =================================================
    local a_name, a_cmd, a_args = clean:match("<ADM>%s*%(%d+%)%s*(%a+_%a+)%[%d+%]:%s*(/[%w]+)%s+(.+)")
    if not a_name then a_name, a_cmd, a_args = clean:match("%[A%] (%a+_%a+)%[%d+%]:%s*(/[%w]+)%s+(.+)") end

    if a_name and a_cmd and a_args and a_name ~= bot_name and not red_admins[a_name] then
        if allowed_cmds[a_cmd:lower()] then
            local fl, ln = a_name:match("^(%a)%a+_(%a+)$")
            if fl and ln then
                local cp = fl .. "." .. ln
                local cc, ca = a_cmd, a_args
                local target_id = ca:match("^(%d+)")
                
                if target_id then
                    pending_admin_mirrors[target_id] = { cancelled = false }
                    
                    newTask(function()
                        wait(math.random(1500, 3500)) 
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

    -- ADMIN CHAT AI QISMI
    if adm_chat_name and adm_chat_text and adm_chat_name ~= bot_name and not red_admins[adm_chat_name] then
        local first_word = adm_chat_text:lower():match("^(%S+)") or ""
        if not allowed_cmds[first_word] then
            local lower_adm = adm_chat_text:lower()
            local talking = false
            local short_name = bot_name:match("^(%w+)_")
            if short_name then short_name = short_name:lower() end
            if (short_name and lower_adm:find(short_name, 1, true)) or lower_adm:find("bot", 1, true) or (active_chat_admin == adm_chat_name and (os.time() - active_chat_time) <= chat_timeout_seconds) then
                talking = true
            end
            if talking then
                active_chat_admin = adm_chat_name
                active_chat_time = os.time()
                
                -- Telegramga zudlik bilan TREVOGA xabar yuborish
                sendTG("🚨 *DIQQAT! Admin chatda sizni chaqirishmoqda!* 🚨\n👤 *Admin:* `" .. tgSafe(adm_chat_name) .. "`\n💬 *Matn:* `" .. tgSafe(adm_chat_text) .. "`", true)

                local a_nm, a_tx = adm_chat_name, adm_chat_text
                newTask(function()
                    wait(math.random(1500, 2500))
                    local ai_reply = getAIChatReply(a_nm .. " siz haqingizda yozdi: " .. a_tx, "admin")
                    if ai_reply then
                        sendInput("/a " .. ai_reply)
                        sendTG("*AI Javob:*\n" .. tgSafe(ai_reply))
                    end
                end)
            end
        end
    end

    -- SMS AI QISMI
    if clean:match("^SMS") or clean:match("yozdi:") then
        local sname, sid = clean:match("(%a+_%a+)%[(%d+)%]")
        if sname and sid and isRPNick(sname) and not red_admins[sname] and sname ~= bot_name then
            sendTG("*SMS (" .. tgSafe(sname) .. "):*\n" .. tgSafe(clean))
            local s_nm, s_id, s_msg = sname, sid, clean
            newTask(function()
                local umsg = s_msg:gsub(s_nm .. "%[%d+%]", ""):gsub("SMS:", ""):gsub("yozdi:", "")
                wait(math.random(2000, 4000))
                local ai_reply = getAIChatReply("O'yinchi SMS yozdi: " .. umsg, "sms")
                if ai_reply then sendInput("/pm " .. s_id .. " " .. ai_reply) end
            end)
        end
    end

    -- REPORT JAVOBLARINI O'RGANISH VA KUTISH
    local tid, ans = clean:match("<ADM>.-%[%d+%]%s+.-%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)")
    if not tid then tid, ans = clean:match("%[A%].-%[%d+%]%s+%[(%d+)%]%s+ga%s+javob%s+berdi:%s*(.+)") end
    if not tid then tid, ans = clean:match("/ans%s+(%d+)%s+(.+)") end
    if not tid then tid, ans = clean:match("Admin%s+.-%[(%d+)%]:%s*(.+)") end
    if not tid then tid, ans = clean:match("%[Report%]%s*.-%[(%d+)%]%s+javob:%s*(.+)") end
    
    if tid and ans then
        local ans_admin = clean:match("(%u%a+_%u%a+)%[%d+%]") or clean:match("(%u%a+_%u%a+)")
        tid = tostring(tid)
        local pend = pending_reports[tid]
        if pend and pend.text then
            local is_bot_ans = (ans_admin == bot_name)
            local is_red_ans = (ans_admin and red_admins[ans_admin])

            if not is_bot_ans then
                local savol = normText(pend.text)
                local javob = ans:gsub("https?://[%S]+", ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ans
                
                -- Hamma javoblarni yig'ib massiv qilish qismi
                if savol ~= "" and javob ~= "" then
                    if not bot_memory[savol] then bot_memory[savol] = {} end
                    if type(bot_memory[savol]) == "table" and bot_memory[savol].answer then
                        local old_ans = bot_memory[savol]
                        bot_memory[savol] = { old_ans }
                    end
                    table.insert(bot_memory[savol], { answer = javob, admin = ans_admin or "?", time = os.time(), trusted = is_red_ans or false })
                    saveMemory()
                end
            end

            if is_red_ans then
                for i = #report_queue, 1, -1 do
                    if tostring(report_queue[i].id) == tid then table.remove(report_queue, i) end
                end
            end
            pending_reports[tid] = nil
        end
    end

    if lower_clean:find("forma") or lower_clean:find("ariza") then
        local f_name = clean:match("(%u%a+_%u%a+)")
        if f_name and f_name ~= bot_name then
            form_senders[f_name] = (form_senders[f_name] or 0) + 1
        end
    end

    local closed_id = clean:match("Report%s+#?(%d+)%s+yopildi") or clean:match("%[(%d+)%]%s+report.*yopildi") or clean:match("^/re%s+(%d+)$")
    if closed_id then
        closed_id = tostring(closed_id)
        for i = #report_queue, 1, -1 do
            if tostring(report_queue[i].id) == closed_id then table.remove(report_queue, i) end
        end
        pending_reports[closed_id] = nil
    end

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
            rep_text = rep_text:match("^%s*(.-)%s*$") or rep_text
            prunePending()
            pending_reports[rep_id] = { text = rep_text, time = os.time() }

            local lower_rep = rep_text:lower():match("^%s*(.-)%s*$") or ""
            local is_plus = (lower_rep:match("^[+%s]+$") ~= nil)

            if lower_rep:find("ag'dar") or lower_rep:find("to'ntar") then
                newTask(function() wait(1500); sendInput("/flip " .. rep_id) end)
            end
            if lower_rep:find("remont") or lower_rep:find("buzildi") or lower_rep:find("fix") then
                newTask(function()
                    wait(2000)
                    if math.random(1, 100) <= 50 then sendInput("/fixcar " .. rep_id) end
                end)
            end

            if not is_plus then
                local q_id, q_name, q_text = rep_id, rep_name, rep_text
                newTask(function()
                    if is_mp_active then
                        wait(math.random(4000, 7000))
                        table.insert(report_queue, { id = q_id, reply = "Assalomu aleykum, iltimos kuting.", name = q_name, text = q_text })
                        return
                    end

                    -- O'rtacha 10 soniya kutish
                    local delay = math.random(9000, 11000) 
                    wait(delay)

                    local final_reply = getSmartReply(q_text, q_name)
                    if not final_reply then
                        -- So'kinish filtr
                        local bad_words = {"skn", "jlb", "dalba", "haqorat", "kot", "qoto", "jala", "skay"}
                        local is_bad = false
                        for _, bw in ipairs(bad_words) do
                            if q_text:lower():find(bw) then is_bad = true; break end
                        end
                        
                        if is_bad then
                            sendTG("⚠️ *DIQQAT! So'kinish/Offtop report keldi:*\n👤 O'yinchi: `" .. tgSafe(q_name) .. "`\n💬 Matn: `" .. tgSafe(q_text) .. "`", true)
                        end

                        local prompt = string.format([[Siz SA-MP serverida "%s" ismli administratorsiz. O'yinchi savoli: "%s". Agar savolda so'kinish, offtop yoki haqorat bo'lsa "Iltimos so'kinmang, aks holda jazo qo'llaniladi" deb javob bering. Agar oddiy savol bo'lsa, bitta gapda o'zbek tilida, "Assalomu alaykum" deb boshlab javob bering.]], bot_name, q_text)
                        
                        final_reply = askGemini(prompt, q_text)
                        if final_reply then
                            final_reply = final_reply:gsub("https?://[%S]+", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
                        end
                        if not final_reply or final_reply == "" then final_reply = getFallbackReply(q_text) end
                    end

                    if final_reply and final_reply:find("kuzat") then
                        local eid = q_text:match("(%d+)")
                        if eid then table.insert(sp_queue, eid) end
                    end
                    table.insert(report_queue, { id = q_id, reply = final_reply, name = q_name, text = q_text })
                end)
            end
        end
    end

    if clean:find("yangiliklari uchun ariza paydo bo'ldi") and clean:find("/acceptgnews") then
        newTask(function() wait(1000); sendInput("/acceptgnews") end)
    end
end

-- =================================================
-- DIALOG HANDLER
-- =================================================
local dialog_pass_keys = { "avtorizatsiya", "parol", "\\239\\224\\240\\238\\235\\252", "\\208\\191\\208\\176\\209\\128\\208\\190\\208\\187\\209\\140" }
local dialog_welcome_keys = { "xush", "yangilik", "grand mobile", "\\228\\238\\225\\240\\238" }

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if license_stopped then return end
    local clean_title = tostring(title):gsub("{......}", "")
    local clean_text = tostring(text):gsub("{......}", "")
    local lower_title = clean_title:lower()
    local is_input = (style == 1 or style == 3)

    if id == last_dialog_id and (os.clock() - last_dialog_time) < 2.0 then return false end
    last_dialog_id = id
    last_dialog_time = os.clock()

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
                wait(4000); spawn(); wait(2000); spawn(); wait(3000)
                sendInput("/az"); wait(1500)
                sendInput("/acceptgnews"); wait(1500)
                sendInput("/sp")
                sendTG("[OK] O'yinga kirdi!")
                startWandering()
            end)
        end
        return false
    end

    if clean_title:find("Arizani tasdiqlash") then
        local auth_code = clean_text:match("kalitni kiriting:%s*(%d%d%d%d)")
        if auth_code then sendDialogResponse(id, 1, 0, auth_code); return false end
    end

    if is_input and not current_stat_id and not clean_title:find("Arizani tasdiqlash") then
        local code = clean_text:match("(%d%d%d%d%d)")
        if code then sendDialogResponse(id, 1, 0, code); return false end
    end

    if current_stat_id then sendDialogResponse(id, 0, 0, ""); return false end
end

-- =================================================
-- ULANISH EVENTLARI
-- =================================================
function onConnectionClosed()
    stopWandering()
    is_logged_in = false
    is_spectating = false
    sendTG("[NET] Bot serverdan uzildi.")
    if license_stopped or sleep_end_time > os.time() then return end
    newTask(function()
        wait(15000)
        if license_stopped or sleep_end_time > os.time() then return end
        connect()
    end)
end

function onExit() pcall(function() ini.save(cfg, "settings\\config.txt") end) end

-- =================================================
-- ASOSIY YUKLASH
-- =================================================
function onLoad()
    pcall(updater.checkAndUpdate, script_version)

    if not isRPNick(bot_name) then print("[XATO] Bot nomi noto'g'ri (RP): " .. tostring(bot_name)); return end
    if not checkLicense(true) then print("[LITSENZIYA] Bot ishga tushmadi: " .. tostring(license_fail_reason)); license_stopped = true; return end

    loadMemory()
    loadFAQFromFile()
    telegramPolling()
    checkUpdates()

    if os.time() - faq_last_update > FAQ_UPDATE_INTERVAL then newTask(function() wait(20000); updateFAQFromWeb(false) end) end

    newTask(function()
        local tick = 0
        while true do
            wait(1000)
            tick = tick + 1

            if tick % 300 == 0 then
                if not licenseGuard() then
                    license_stopped = true
                    stopWandering()
                    pcall(disconnect)
                    return
                end
                prunePending()
            end

            if sleep_end_time > os.time() then
            else
                local idle = os.time() - last_activity

                if is_spectating then
                    if os.time() - sp_timer > 120 then spectateRandomPlayer() end
                elseif #sp_queue > 0 then
                    local tid = table.remove(sp_queue, 1)
                    sendInput("/sp " .. tid)
                    is_spectating = true
                    sp_timer = os.time()
                    last_activity = os.time()
                    stopWandering()
                elseif not is_wandering then
                    if idle > 5 then startWandering() end
                else
                    if os.time() - wander_timer > 20 then
                        stopWandering()
                        spectateRandomPlayer()
                    end
                end

                if #report_queue > 0 then
                    local task = table.remove(report_queue, 1)
                    local reply = task.reply
                    if not reply or reply == "" then reply = getFallbackReply(task.text) end
                    sendInput("/ans " .. tostring(task.id) .. " " .. reply)

                    local today = os.date("%d.%m")
                    cfg.daily_logs[today .. "_rep"] = (tonumber(cfg.daily_logs[today .. "_rep"]) or 0) + 1
                    pcall(function() ini.save(cfg, "settings\\config.txt") end)

                    wait(500)
                    sendInput("/re " .. tostring(task.id))
                    wait(1500)
                end
            end
        end
    end)

    print("[BOT] " .. bot_name .. " v" .. tostring(script_version) .. " Ishga tushdi!")
    sendTG("*Bot Ishga Tushdi! (v" .. tostring(script_version) .. ")*", true)
end
-- === KOD TUGASHI ===
