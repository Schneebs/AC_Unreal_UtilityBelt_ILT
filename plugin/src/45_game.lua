-- Shared game plumbing for the tools: server commands (the chat service sends one
-- line per second), received server chat (chat_events, filtered by the manifest's
-- chat_subscriptions), saved per-character tool data, and number/time formatting.

local SEND_INTERVAL = 1.1

local game = {
    sends = {},          -- server commands waiting to be sent
    last_send = -1000,
    next_send_id = 0,
    now = 0,             -- snapshot.time (seconds, monotonic)
    unix = 0,            -- snapshot.unix_time (seconds)
}

-- Queues a server command such as "/b" or "/attr str 1".
local function game_send(text)
    game.sends[#game.sends + 1] = text
end

-- Returns at most one chat/send request when the 1-per-second limit allows.
local function game_send_tick(now)
    if #game.sends == 0 or now - game.last_send < SEND_INTERVAL then return nil end
    game.last_send = now
    game.next_send_id = game.next_send_id + 1
    return { id = "ub_send_" .. game.next_send_id, service = "chat", operation = "send", text = table.remove(game.sends, 1) }
end

-- Server lines only (players can type anything, including fake "[BANK]" lines).
local function game_server_lines(snapshot)
    local lines = {}
    for _, e in ipairs(snapshot.chat_events or {}) do
        if e.sender_type == nil or e.sender_type == "server" then
            local text = trim(tostring(e.raw_text or e.text or ""))
            -- Drop trailing newlines the server includes on some lines.
            while #text > 0 and (string.sub(text, -1) == "\n" or string.sub(text, -1) == "\r") do text = string.sub(text, 1, -2) end
            if text ~= "" then lines[#lines + 1] = text end
        end
    end
    return lines
end

local function starts_with(s, prefix) return string.sub(s, 1, #prefix) == prefix end

-- Saved per-character tool data (bank balances, transactions, aug targets...).
-- Lives in settings.data and is written with the settings to plugin state.
settings.data = settings.data or {}

local function data_get(key)
    if type(settings.data[key]) ~= "table" then settings.data[key] = {} end
    return settings.data[key]
end

local function data_changed() settings.dirty = true end

-- Parses "1,234", "1.5k", "2m", "3b" or "4t" (bank amounts). Returns an integer or nil.
local function parse_amount(text)
    local s = string.lower(trim(tostring(text or "")))
    local mult = 1
    local last = string.sub(s, -1)
    if last == "k" then mult = 1e3 elseif last == "m" then mult = 1e6 elseif last == "b" then mult = 1e9 elseif last == "t" then mult = 1e12 end
    if mult > 1 then s = string.sub(s, 1, -2) end
    local digits = {}
    for i = 1, #s do
        local c = string.sub(s, i, i)
        if c ~= "," then digits[#digits + 1] = c end
    end
    local n = tonumber(table.concat(digits))
    if not n or n <= 0 then return nil end
    n = math.floor(n * mult + 0.5)
    return math.tointeger(n) or n
end

-- Leading integer of a string after removing commas ("1,234 (bank)" -> 1234).
local function leading_number(s)
    local out, started = {}, false
    for i = 1, #s do
        local c = string.sub(s, i, i)
        if c >= "0" and c <= "9" then out[#out + 1] = c; started = true
        elseif c == "," and started then -- skip
        elseif c == " " and not started then -- skip
        else break end
    end
    return tonumber(table.concat(out))
end

-- 1234567 -> "1.2M" (retail FormatLargeNumber style).
local function short_number(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    local function f(v, suffix) return string.format("%.1f%s", v, suffix) end
    if a >= 1e15 then return f(n / 1e15, "Q") end
    if a >= 1e12 then return f(n / 1e12, "T") end
    if a >= 1e9 then return f(n / 1e9, "B") end
    if a >= 1e6 then return f(n / 1e6, "M") end
    if a >= 1e3 then return f(n / 1e3, "K") end
    return tostring(math.tointeger(n) or n)
end

-- UTC date from unix seconds (no os.date in the sandbox). Returns "YYYY-MM-DD HH:MM".
local function format_utc(unix)
    unix = math.floor(tonumber(unix) or 0)
    local days = unix // 86400
    local secs = unix - days * 86400
    -- Civil-from-days (Howard Hinnant's algorithm).
    local z = days + 719468
    local era = (z >= 0 and z or z - 146096) // 146097
    local doe = z - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local mp = (5 * doy + 2) // 153
    local d = doy - (153 * mp + 2) // 5 + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return string.format("%04d-%02d-%02d %02d:%02d", y, m, d, secs // 3600, (secs % 3600) // 60)
end

-- "2d 3h 15m" style durations (retail GetFriendlyTimeDifference).
local function format_duration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local d, h, m, s = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60, seconds % 60
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    if m > 0 then return string.format("%dm %ds", m, s) end
    return string.format("%ds", s)
end

local function format_ago(unix)
    if not unix or unix <= 0 then return "Never" end
    local diff = game.unix - unix
    if diff < 60 then return "just now" end
    if diff < 86400 * 2 then return format_duration(diff) .. " ago" end
    return format_utc(unix) .. " UTC"
end

-- A setting's value by full name (nil when the name isn't in the schema).
local function opt(name)
    local entry = settings.by_name[string.lower(name)]
    if entry then return settings_get(entry) end
    return nil
end

local function opt_set(name, value)
    local entry = settings.by_name[string.lower(name)]
    if entry then settings_put(entry, value) end
end
