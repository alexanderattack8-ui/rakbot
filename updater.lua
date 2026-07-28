-- admin.lua uchun avtomatik updater
local requests = require("requests")
local json = require("cjson")
local os = require("os")

local BASE_URL = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/"
local VERSION_URL = BASE_URL .. "version.json"
local SCRIPT_URL = BASE_URL .. "admin.lua"
local HASH_URL = BASE_URL .. "admin.lua.sha256"
local CURRENT_VERSION = 4.5
local TARGET = "scripts\\admin.lua"
local BACKUP = "scripts\\admin.lua.backup"
local TEMP = "scripts\\admin.lua.update.tmp"

local function get(url)
    local ok, res = pcall(function()
        return requests.get(url, { timeout = 12 })
    end)
    if ok and res and res.status_code == 200 and type(res.text) == "string" then
        return res.text
    end
    return nil
end

local function digest(data)
    local ok, mod = pcall(require, "sha256")
    if not ok or not mod then return nil end
    if type(mod) == "function" then return mod(data) end
    if type(mod.digest) == "function" then return mod.digest(data) end
    if type(mod.sha256) == "function" then return mod.sha256(data) end
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
    f:write(data)
    f:close()
    return true
end

local function versionNumber(text)
    local ok, data = pcall(json.decode, text or "")
    if not ok or type(data) ~= "table" then return nil end
    return tonumber(data.version)
end

function checkAndUpdate()
    local raw = get(VERSION_URL)
    local remote = versionNumber(raw)
    if not remote or remote <= CURRENT_VERSION then return nil end

    local body = get(SCRIPT_URL)
    local expected = get(HASH_URL)
    if not body or not expected then
        return "вљ пёЏ Yangilanish topildi, lekin fayl yoki hash yuklanmadi."
    end
    local actual = digest(body)
    expected = expected:match("^%s*([0-9a-fA-F]+)")
    if not actual or not expected or actual:lower() ~= expected:lower() then
        return "вљ пёЏ Yangilanish hash tekshiruvidan o'tmadi, fayl almashtirilmadi."
    end

    local old = readAll(TARGET)
    if not old then
        return "вљ пёЏ Eski admin.lua topilmadi, yangilash bekor qilindi."
    end
    if not writeAll(TEMP, body) then
        return "вљ пёЏ Vaqtinchalik yangilanish fayli yozilmadi."
    end
    local check = readAll(TEMP)
    if not check or check ~= body then
        os.remove(TEMP)
        return "вљ пёЏ Yuklangan fayl tekshiruvdan o'tmadi."
    end
    if not writeAll(BACKUP, old) then
        os.remove(TEMP)
        return "вљ пёЏ Backup yaratilmadi, yangilash bekor qilindi."
    end
    os.remove(TARGET)
    local moved = os.rename(TEMP, TARGET)
    if not moved then
        writeAll(TARGET, old)
        os.remove(TEMP)
        return "вљ пёЏ admin.lua almashtirilmadi, backup tiklandi."
    end
    return "вњ… *Yangi versiya avtomatik yuklandi:* v" .. tostring(remote) .. "\nBotni bir marta restart qiling."
end

return { checkAndUpdate = checkAndUpdate }
