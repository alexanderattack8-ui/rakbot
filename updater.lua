-- admin.lua uchun avtomatik updater (v2 - TUZATILGAN)
-- FIX: require("os") olib tashlandi - os standart global kutubxona.
local requests = require("requests")
local json = require("cjson")

local BASE_URL = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/"
local VERSION_URL = BASE_URL .. "version.json"
local SCRIPT_URL = BASE_URL .. "admin.lua"
local HASH_URL = BASE_URL .. "admin.lua.sha256"

-- FIX: avval bu yerda 4.5 qattiq yozilgan edi va admin.lua ning haqiqiy versiyasi bilan
-- sinxron emasdi (admin.lua 4.7 bo'lsa ham updater 4.5 deb o'ylardi va cheksiz yangilardi).
-- Endi versiya admin.lua dan parametr sifatida keladi.
local FALLBACK_VERSION = 4.7

local TARGET = "scripts\\admin.lua"
local BACKUP = "scripts\\admin.lua.backup"
local MIN_SIZE = 5000 -- to'liq admin.lua shundan kichik bo'lishi mumkin emas

local function log(msg)
    print("[UPDATER] " .. tostring(msg))
end

-- FIX: GitHub raw keshlab qolardi (eski fayl kelardi) + bitta urinishda uzilib qolardi.
-- Endi kesh buzuvchi parametr va 3 marta urinish bor.
local function get(url)
    for attempt = 1, 3 do
        local sep = url:find("?", 1, true) and "&" or "?"
        local full = url .. sep .. "nocache=" .. tostring(os.time()) .. tostring(attempt)
        local ok, res = pcall(function()
            return requests.get(full, {
                timeout = 15,
                headers = { ["Cache-Control"] = "no-cache", ["Pragma"] = "no-cache" }
            })
        end)
        if ok and res and res.status_code == 200 and type(res.text) == "string" and res.text ~= "" then
            return res.text
        end
        if attempt < 3 and wait then wait(1500) end
    end
    return nil
end

-- FIX: avval require("sha256") bo'lmasa ham hash tekshiruvi majburiy edi va
-- yangilanish DOIM "hash tekshiruvidan o'tmadi" bilan bekor bo'lardi.
-- Endi hash bor bo'lsa tekshiriladi, bo'lmasa loadstring bilan sintaksis tekshiriladi.
local function digest(data)
    for _, name in ipairs({ "sha256", "sha2", "crypto.sha256" }) do
        local ok, mod = pcall(require, name)
        if ok and mod then
            if type(mod) == "function" then
                local ok2, out = pcall(mod, data)
                if ok2 and type(out) == "string" then return out end
            elseif type(mod) == "table" then
                for _, fn in ipairs({ "digest", "sha256", "hash", "sum" }) do
                    if type(mod[fn]) == "function" then
                        local ok2, out = pcall(mod[fn], data)
                        if ok2 and type(out) == "string" then return out end
                    end
                end
            end
        end
    end
    return nil
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeAll(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    local ok = pcall(function() f:write(data) end)
    f:close()
    return ok and true or false
end

local function versionNumber(text)
    if type(text) ~= "string" then return nil end
    local ok, data = pcall(json.decode, text)
    if ok and type(data) == "table" and tonumber(data.version) then
        return tonumber(data.version)
    end
    -- FIX: version.json buzuq bo'lsa ham raqamni ajratib olishga harakat qiladi
    return tonumber(tostring(text):match('"version"%s*:%s*"?([%d%.]+)"?'))
end

-- FIX: eng muhim yangi tekshiruv - yuklangan fayl haqiqatan to'liq va yaroqli Lua ekanligi.
-- Yarim yuklangan yoki HTML xato sahifasi kelib qolsa bot butunlay ishlamay qolardi.
local function validate(body)
    if type(body) ~= "string" then return false, "fayl bo'sh" end
    if #body < MIN_SIZE then return false, "fayl juda kichik (" .. #body .. " bayt)" end
    if body:match("^%s*<") then return false, "Lua emas, HTML sahifa keldi" end
    if not body:find("function onLoad", 1, true) then return false, "onLoad topilmadi" end
    if not body:find("sampev.onServerMessage", 1, true) then return false, "onServerMessage topilmadi" end
    local chunk, err
    if loadstring then
        chunk, err = loadstring(body, "admin_update")
    elseif load then
        chunk, err = load(body, "admin_update")
    end
    if chunk == nil and err then
        return false, "sintaksis xato: " .. tostring(err)
    end
    return true
end

function checkAndUpdate(current_version)
    local current = tonumber(current_version) or FALLBACK_VERSION

    local remote = versionNumber(get(VERSION_URL))
    if not remote then
        log("version.json o'qilmadi")
        return nil
    end
    if remote <= current then return nil end

    local body = get(SCRIPT_URL)
    if not body then
        return "[UPDATE] Yangi versiya v" .. tostring(remote) .. " topildi, lekin fayl yuklanmadi."
    end

    local ok_valid, why = validate(body)
    if not ok_valid then
        return "[UPDATE] Yuklangan fayl yaroqsiz, almashtirilmadi: " .. tostring(why)
    end

    -- Hash tekshiruvi: modul va hash fayli bo'lsa qat'iy tekshiriladi, bo'lmasa o'tkazib yuboriladi.
    local expected = get(HASH_URL)
    if expected then
        expected = tostring(expected):match("%x%x%x%x%x%x%x%x+")
    end
    local actual = digest(body)
    if expected and actual then
        if actual:lower() ~= expected:lower() then
            return "[UPDATE] Hash mos kelmadi, fayl almashtirilmadi."
        end
    elseif expected and not actual then
        log("sha256 moduli yo'q, hash tekshiruvi o'tkazib yuborildi (sintaksis tekshiruvi o'tdi)")
    end

    local old = readAll(TARGET)
    if not old then
        return "[UPDATE] Eski admin.lua topilmadi (" .. TARGET .. "), yangilash bekor qilindi."
    end
    if old == body then
        log("fayl allaqachon yangi, faqat version.json oldinda")
        return nil
    end
    if not writeAll(BACKUP, old) then
        return "[UPDATE] Backup yaratilmadi, yangilash bekor qilindi."
    end

    -- FIX: avval os.remove + os.rename ishlatilgan. Windows'da ishlayotgan skript fayli
    -- band bo'lsa rename yiqilardi va admin.lua butunlay yo'qolib ketishi mumkin edi.
    -- Endi joyida qayta yozilib, darhol qayta o'qib tekshiriladi.
    if not writeAll(TARGET, body) then
        writeAll(TARGET, old)
        return "[UPDATE] admin.lua yozilmadi, eski fayl saqlanib qoldi."
    end
    local check = readAll(TARGET)
    if check ~= body then
        writeAll(TARGET, old)
        return "[UPDATE] Yozilgan fayl tekshiruvdan o'tmadi, backup tiklandi."
    end

    return "[UPDATE] *Yangi versiya yuklandi:* v" .. tostring(remote) ..
        "\nBotni bir marta restart qiling (backup: admin.lua.backup)."
end

return { checkAndUpdate = checkAndUpdate }
