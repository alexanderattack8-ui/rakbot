-- Safe release updater for admin.lua
local requests = require("requests")
local json = require("cjson")
local os = require("os")

local UPDATE_BASE = "https://raw.githubusercontent.com/alexanderattack8-ui/rakbot/main/"
local VERSION_URL = UPDATE_BASE .. "version.json"
local SCRIPT_URL = UPDATE_BASE .. "admin.lua"
local SHA256_URL = UPDATE_BASE .. "admin.lua.sha256"
local CURRENT_VERSION = 4.5
local TARGET_FILE = "admin.lua"
local BACKUP_FILE = "admin.lua.backup"

local function get(url)
    local ok, res = pcall(function() return requests.get(url, { timeout = 10 }) end)
    if not ok or not res or res.status_code ~= 200 then return nil end
    return res.text
end

local function sha256(data)
    local ok, crypt = pcall(require, "sha256")
    if ok and crypt then
        if type(crypt) == "function" then return crypt(data) end
        if type(crypt.digest) == "function" then return crypt.digest(data) end
        if type(crypt.sha256) == "function" then return crypt.sha256(data) end
    end
    return nil
end

function checkAndUpdate()
    local raw = get(VERSION_URL)
    if not raw then return false end
    local ok, info = pcall(json.decode, raw)
    if not ok or type(info) ~= "table" then return false end
    local remote = tonumber(info.version)
    if not remote or remote <= CURRENT_VERSION then return false end
    local body = get(SCRIPT_URL)
    local expected = get(SHA256_URL)
    if not body or not expected then return false end
    local digest = sha256(body)
    if not digest then
        print("[UPDATER] SHA-256 moduli yo'q, yangilash bekor qilindi.")
        return false
    end
    expected = expected:match("^%s*([0-9a-fA-F]+)")
    if not expected or digest:lower() ~= expected:lower() then
        print("[UPDATER] Hash mos kelmadi, yangilash bekor qilindi.")
        return false
    end
    local old = io.open(TARGET_FILE, "rb")
    if not old then return false end
    local old_data = old:read("*a"); old:close()
    local backup = io.open(BACKUP_FILE, "wb")
    if not backup then return false end
    backup:write(old_data); backup:close()
    local out = io.open(TARGET_FILE, "wb")
    if not out then return false end
    out:write(body); out:close()
    print("[UPDATER] Yangilandi: v" .. tostring(remote) .. ". Restart kerak.")
    return true
end

return { checkAndUpdate = checkAndUpdate }
