-- Retail import: loads retail UtilityBelt settings that UB Manager copied into this
-- plugin's profile library (Profiles/utilitybelt/Library/r_*) into the settings store.
--   r_index/index (ub_index) -> find this server's world
--   <world group>/_index (ub_characters) -> find this character's file
--   <world group>/<file> (ub_settings) -> replace the character's settings
-- Runs automatically on a character's first login (no saved settings yet) and when
-- the player presses Import from retail. The settings are then saved in the
-- character's plugin state; later edits (window or /ub opt) are saved the same way.

local RETAIL_TIMEOUT = 10          -- seconds to wait for a service result
local PATCH_MAX_NODES = 30000      -- client limits for profile_patch trees
local PATCH_MAX_STRING = 4000      -- bytes (client limit 4,096)
local PATCH_MAX_ARRAY = 2048
local PATCH_MAX_DEPTH = 11         -- below the client's twelve nesting levels

local retail = {
    phase = "start",       -- start | index | characters | settings | done
    pending = nil,         -- { id = ..., sent = time }
    next_id = 0,
    status = "Retail import: waiting for login",
    world = nil, group = nil, character = nil, file = nil,
    remembered = false,    -- true when reapplying a match saved in state
}

local function normalize(name)
    local s = string.lower(name or "")
    local out = {}
    for i = 1, #s do
        local c = string.sub(s, i, i)
        if c ~= " " and c ~= "-" and c ~= "_" then out[#out + 1] = c end
    end
    return table.concat(out)
end

local function retail_request(operation, group, name, field)
    retail.next_id = retail.next_id + 1
    local id = "ub_retail_" .. retail.next_id
    local r = { id = id, service = "profiles", operation = operation, group = group, name = name }
    if field then r.field = field end
    return id, r
end

-- Copies a value within the client's profile_patch limits; counts what had to be dropped.
local function sanitize(value, depth, budget)
    local t = type(value)
    if t == "string" then
        if #value > PATCH_MAX_STRING then budget.dropped = budget.dropped + 1; return nil end
        budget.nodes = budget.nodes + 1
        return value
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then budget.dropped = budget.dropped + 1; return nil end
        budget.nodes = budget.nodes + 1
        return value
    elseif t == "boolean" then
        budget.nodes = budget.nodes + 1
        return value
    elseif t ~= "table" then
        return nil
    end
    if depth > PATCH_MAX_DEPTH or budget.nodes >= PATCH_MAX_NODES then budget.dropped = budget.dropped + 1; return nil end
    budget.nodes = budget.nodes + 1
    local out = {}
    if #value > 0 then
        for i = 1, math.min(#value, PATCH_MAX_ARRAY) do
            local v = sanitize(value[i], depth + 1, budget)
            if v ~= nil then out[#out + 1] = v end
        end
        if #value > PATCH_MAX_ARRAY then budget.dropped = budget.dropped + (#value - PATCH_MAX_ARRAY) end
    else
        for k, v in pairs(value) do
            if type(k) == "string" then
                local copy = sanitize(v, depth + 1, budget)
                if copy ~= nil then out[k] = copy end
            end
        end
    end
    return out
end

-- Starts a fresh match (button press or first login with no saved match).
local function retail_begin()
    retail.phase, retail.pending, retail.remembered = "index", nil, false
    retail.world, retail.group, retail.character, retail.file = nil, nil, nil, nil
    retail.status = "Retail import: reading index"
end

-- One step per callback. Returns a partial output table (requests, state, profile_patch).
local function retail_tick(snapshot, wants_import)
    local out = {}
    local now = snapshot.time or 0
    local state = snapshot.state or {}
    local saved = state.ub_retail
    local character = snapshot.character_name

    if wants_import then retail_begin() end

    if retail.phase == "start" then
        if not character or character == "" then return out end
        if settings.loaded then
            retail.phase = "done"
            retail.status = "Settings loaded for " .. character
        elseif type(saved) == "table" and saved.group and saved.file then
            -- Reapply a match remembered by plugin versions before 0.3 (no saved settings).
            retail.phase, retail.remembered = "settings", true
            retail.world, retail.group, retail.character, retail.file = saved.world, saved.group, saved.character, saved.file
            retail.status = "Retail import: loading settings for " .. tostring(saved.character)
        else
            retail_begin()
        end
    end

    -- Collect the result for the pending request, if it arrived.
    local result
    if retail.pending then
        for _, e in ipairs(snapshot.events or {}) do
            if e.type == "result" and e.id == retail.pending.id then result = e end
        end
        if not result then
            if now - retail.pending.sent > RETAIL_TIMEOUT then
                retail.phase, retail.pending = "done", nil
                retail.status = "Retail import: no reply from the profile service; try Import from retail again"
            end
            return out
        end
        retail.pending = nil
        -- The client rate-limits all of a plugin's service requests together: resend.
        if not result.ok and string.contains(string.lower(tostring(result.error or "")), "rate limit") then
            result = nil
        end
    end

    if retail.phase == "index" then
        if not result then
            local id, r = retail_request("read", "r_index", "index", "ub_index")
            retail.pending = { id = id, sent = now }
            out.requests = { r }
            return out
        end
        if not result.ok or type(result.data) ~= "table" then
            retail.phase = "done"
            retail.status = "Retail import: no retail data found. Run UB Manager's Import first."
            return out
        end
        local server = normalize(snapshot.server)
        for _, w in ipairs(result.data.worlds or {}) do
            if type(w) == "table" and normalize(w.name) == server then retail.world, retail.group = w.name, w.group end
        end
        if not retail.group then
            retail.phase = "done"
            retail.status = "Retail import: no retail world matches server " .. tostring(snapshot.server)
            return out
        end
        retail.phase = "characters"
        result = nil
    end

    if retail.phase == "characters" then
        if not result then
            local id, r = retail_request("read", retail.group, "_index", "ub_characters")
            retail.pending = { id = id, sent = now }
            out.requests = { r }
            return out
        end
        if not result.ok or type(result.data) ~= "table" then
            retail.phase = "done"
            retail.status = "Retail import: could not read the character list for " .. tostring(retail.world)
            return out
        end
        local map = result.data
        retail.file = map[character]
        if not retail.file then
            local want = string.lower(character or "")
            for name, file in pairs(map) do
                if string.lower(name) == want then retail.character, retail.file = name, file end
            end
        else
            retail.character = character
        end
        if not retail.file then
            retail.phase = "done"
            retail.status = "Retail import: " .. tostring(character) .. " has no retail data on " .. tostring(retail.world)
            return out
        end
        retail.phase = "settings"
        result = nil
    end

    if retail.phase == "settings" then
        if not result then
            local id, r = retail_request("read", retail.group, retail.file, "ub_settings")
            retail.pending = { id = id, sent = now }
            out.requests = { r }
            return out
        end
        retail.phase = "done"
        if not result.ok or type(result.data) ~= "table" then
            retail.status = "Retail import: " .. tostring(retail.character) .. " has no retail settings (it uses UB defaults on retail too)"
            return out
        end
        local budget = { nodes = 0, dropped = 0 }
        settings_replace(sanitize(result.data, 1, budget) or {})
        if not retail.remembered then
            local new_state = {}
            for k, v in pairs(state) do new_state[k] = v end
            new_state.ub_retail = {
                world = retail.world, group = retail.group, character = retail.character,
                file = retail.file, imported = snapshot.unix_time,
            }
            out.state = new_state
        end
        retail.status = "Retail settings applied from " .. tostring(retail.world) .. "/" .. tostring(retail.character)
            .. (budget.dropped > 0 and (" (" .. budget.dropped .. " oversized values skipped)") or "")
    end
    return out
end
