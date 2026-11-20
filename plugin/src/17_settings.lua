-- Settings store: retail UtilityBelt's settings, by the same names (Plugin.Debug,
-- Looter.Enabled, OverlayMap.DrawFloors.Color...). Values live in a nested table
-- shaped exactly like retail settings.json, holding only non-default values, so
-- retail files import and export unchanged. Keys the schema doesn't know (settings
-- from newer UB builds) are kept as they are.
--
-- Persistence: per-character plugin state (state.ub_settings, state.ub_charstate),
-- written through settings_state(). The client saves state at most every 5 seconds.

local settings = {
    values = {},        -- store = "setting" (retail settings.json)
    charstate = {},     -- store = "state"   (retail state.json, per character)
    dirty = false,
    loaded = false,     -- true once values came from state or a retail import
    by_name = {},       -- lower-case full name -> schema entry
    list = {},          -- schema entries in tool order
    tools = {},         -- { name, summary, leaftide, settings = {entries} }
}

for _, tool in ipairs(UB_SCHEMA) do
    settings.tools[#settings.tools + 1] = tool
    for _, entry in ipairs(tool.settings) do
        entry.tool = tool.name
        entry.short = string.sub(entry.name, #tool.name + 2)
        settings.by_name[string.lower(entry.name)] = entry
        settings.list[#settings.list + 1] = entry
    end
end

local function split_dots(name)
    local parts, start = {}, 1
    while true do
        local i = string.findplain(name, ".", start)
        if not i then parts[#parts + 1] = string.sub(name, start); return parts end
        parts[#parts + 1] = string.sub(name, start, i - 1)
        start = i + 1
    end
end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep_copy(x) end
    return t
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then
        -- 1 and 1.0 are equal; JSON round trips may change number subtypes.
        return false
    end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deep_equal(v, b[k]) then return false end end
    for k, _ in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function store_for(entry)
    return entry.store == "state" and settings.charstate or settings.values
end

-- Raw stored value (nil when the setting is at its default).
local function settings_raw(entry)
    local node = store_for(entry)
    local parts = split_dots(entry.name)
    for i = 1, #parts do
        if type(node) ~= "table" then return nil end
        node = node[parts[i]]
    end
    return node
end

local function settings_get(entry)
    local v = settings_raw(entry)
    if v == nil then return deep_copy(entry.default) end
    return v
end

-- Stores a value; a value equal to the default is removed, as retail does.
local function settings_put(entry, value)
    local root = store_for(entry)
    local parts = split_dots(entry.name)
    local node, path = root, {}
    for i = 1, #parts - 1 do
        if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
        path[#path + 1] = { node, parts[i] }
        node = node[parts[i]]
    end
    if value == nil or deep_equal(value, entry.default) then
        node[parts[#parts]] = nil
        -- Prune empty parent tables.
        for i = #path, 1, -1 do
            local parent, key = path[i][1], path[i][2]
            if next(parent[key]) == nil then parent[key] = nil else break end
        end
    else
        node[parts[#parts]] = value
    end
    settings.dirty = true
end

local function trim(s)
    local a, b = 1, #s
    while a <= b and (string.sub(s, a, a) == " " or string.sub(s, a, a) == "\t") do a = a + 1 end
    while b >= a and (string.sub(s, b, b) == " " or string.sub(s, b, b) == "\t") do b = b - 1 end
    return string.sub(s, a, b)
end

local function split_commas(s)
    local out, start = {}, 1
    while true do
        local i = string.findplain(s, ",", start)
        local piece = trim(string.sub(s, start, i and i - 1 or #s))
        if piece ~= "" then out[#out + 1] = piece end
        if not i then return out end
        start = i + 1
    end
end

-- Parses text typed by the player into the setting's type. Returns value or nil, error.
local function settings_parse(entry, text)
    local t = entry.type
    text = trim(tostring(text))
    if t == "bool" then
        local l = string.lower(text)
        if l == "true" or l == "1" or l == "on" or l == "yes" then return true end
        if l == "false" or l == "0" or l == "off" or l == "no" then return false end
        return nil, "expected true or false"
    elseif t == "int" then
        local n = tonumber(text)
        if not n and string.sub(text, 1, 1) == "#" then
            -- Colors may be typed as #RRGGBB or #AARRGGBB like retail's color picker.
            local hex = string.sub(text, 2)
            n = tonumber(hex, 16)
            if n and #hex == 6 then n = n + 0xFF000000 end
            if n and n >= 0x80000000 then n = n - 0x100000000 end
        end
        if not n or n ~= math.floor(n) then return nil, "expected a whole number" end
        return math.tointeger(n) or n
    elseif t == "float" then
        local n = tonumber(text)
        if not n then return nil, "expected a number" end
        return n
    elseif t == "string" or t == "enum" then
        return text
    elseif t == "list" then
        return split_commas(text)
    end
    return nil, "this setting can only be changed in retail UtilityBelt for now"
end

-- Display like retail (C# booleans are True/False).
local function settings_display(entry, value)
    if value == nil then value = settings_get(entry) end
    local t = type(value)
    if t == "boolean" then return value and "True" or "False" end
    if t == "table" then
        local parts = {}
        if #value > 0 or next(value) == nil then
            for _, v in ipairs(value) do parts[#parts + 1] = tostring(v) end
            return "[" .. table.concat(parts, ", ") .. "]"
        end
        local keys = {}
        for k, _ in pairs(value) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do parts[#parts + 1] = k .. ": " .. tostring(value[k]) end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    if t == "number" and math.type(value) == "float" and value == math.floor(value) then
        return tostring(math.tointeger(value))
    end
    return tostring(value)
end

local function settings_full_display(entry)
    return entry.name .. " = " .. settings_display(entry)
end

-- Replaces all profile settings (retail import).
local function settings_replace(values)
    settings.values = type(values) == "table" and deep_copy(values) or {}
    settings.loaded, settings.dirty = true, true
end

-- Loads saved values on the first callback for a character.
local function settings_load(state)
    if settings.loaded then return end
    if type(state.ub_settings) == "table" then
        settings.values = deep_copy(state.ub_settings)
        settings.loaded = true
    end
    if type(state.ub_charstate) == "table" then settings.charstate = deep_copy(state.ub_charstate) end
end

-- Returns a full state table to save when anything changed, else nil.
local function settings_state(state)
    if not settings.dirty then return nil end
    settings.dirty = false
    local out = {}
    for k, v in pairs(state or {}) do out[k] = v end
    out.ub_settings = deep_copy(settings.values)
    out.ub_charstate = deep_copy(settings.charstate)
    return out
end

-- Leaftide tools are active on InfiniteLeaftide, or anywhere with Plugin.ForceLeaftideFeatures.
local function leaftide_active(server)
    local s = string.lower(server or "")
    local compact = {}
    for i = 1, #s do
        local c = string.sub(s, i, i)
        if c ~= " " then compact[#compact + 1] = c end
    end
    if table.concat(compact) == "infiniteleaftide" then return true end
    local force = settings.by_name["plugin.forceleaftidefeatures"]
    return force ~= nil and settings_get(force) == true
end
