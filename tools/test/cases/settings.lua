-- Settings store, /ub opt commands and the settings window. Saved settings come from
-- state; edits are saved back in retail's sparse settings.json shape.
local clock = 0

local function find_control(list, id)
    for _, c in ipairs(list or {}) do
        if c.id == id then return c end
        local found = find_control(c.children, id)
        if found then return found end
    end
end

-- Finds the first control whose id starts with prefix.
local function find_prefix(list, prefix)
    for _, c in ipairs(list or {}) do
        if type(c.id) == "string" and string.sub(c.id, 1, #prefix) == prefix then return c end
        local found = find_prefix(c.children, prefix)
        if found then return found end
    end
end

local saved = { ub_settings = { Plugin = { Debug = true }, GearBrowser = { Future = 1 } }, other = "kept" }

local function snap(events, state, dt)
    clock = clock + (dt or 1)
    return { time = clock, server = "Schneenanigans", character_name = "Reawakener",
             state = state or saved, events = events or {} }
end

local function notices(out)
    local lines = {}
    for _, r in ipairs(out and out.requests or {}) do
        if r.service == "notice" then lines[#lines + 1] = r.text end
    end
    return table.concat(lines, "\n")
end

local function has(text, part) return string.find(text, part, 1, true) ~= nil end

local last_state = saved
local function remember(out)
    if out and out.state then last_state = out.state end
end

local editor_id

return {
    name = "settings and /ub opt",
    steps = {
        {
            snapshot = function() return snap() end,
            check = function(out, t)
                t.ok(out.requests == nil, "saved settings: no retail import request")
                t.ok(has(out.status, "Settings loaded"), "status says settings are loaded")
                t.ok(out.state == nil, "nothing to save yet")
            end,
        },
        {
            snapshot = function() return snap({ { type = "command", text = "opt get Plugin.Debug" } }) end,
            check = function(out, t)
                t.ok(has(notices(out), "Plugin.Debug = True"), "opt get shows the saved value like retail")
            end,
        },
        {
            snapshot = function() return snap({ { type = "command", text = "/ub opt set jumper.attempts 5" } }) end,
            check = function(out, t)
                remember(out)
                local s = out.state and out.state.ub_settings or {}
                t.ok(s.Jumper and s.Jumper.Attempts == 5, "opt set saves the value (names are case-insensitive)")
                t.ok(s.GearBrowser and s.GearBrowser.Future == 1, "unknown settings from newer UB builds are kept")
                t.ok(out.state and out.state.other == "kept", "other state is kept")
                t.ok(has(notices(out), "Jumper.Attempts = 5"), "opt set echoes the new value")
            end,
        },
        {
            snapshot = function() return snap({ { type = "command", text = "opt set Jumper.Attempts 3" } }, last_state) end,
            check = function(out, t)
                remember(out)
                local s = out.state and out.state.ub_settings or {}
                t.ok(s.Jumper == nil, "a value equal to the default is removed, as retail does")
            end,
        },
        {
            snapshot = function() return snap({ { type = "command", text = "opt toggle Plugin.Debug" } }, last_state) end,
            check = function(out, t)
                remember(out)
                local s = out.state and out.state.ub_settings or {}
                t.ok(s.Plugin == nil, "toggle back to the default prunes the empty tool table")
                t.ok(has(notices(out), "Plugin.Debug = False"), "toggle echoes")
            end,
        },
        {
            snapshot = function() return snap({ { type = "command", text = "opt set Jumper.Attempts lots" },
                                                { type = "command", text = "opt get No.Such.Setting" } }, last_state) end,
            check = function(out, t)
                local text = notices(out)
                t.ok(has(text, "Unable to set Jumper.Attempts"), "bad values are rejected")
                t.ok(has(text, "Invalid option: No.Such.Setting"), "unknown names are reported")
                t.ok(out.state == nil, "nothing saved on errors")
            end,
        },
        {
            snapshot = function() return snap({ { type = "click", id = "ub_t_Settings" }, { type = "change", id = "ub_filter", value = "jumper.attempts" } }, last_state) end,
            check = function(out, t)
                local editor = find_prefix(out.ui, "ub_s_")
                t.ok(editor and editor.type == "number" and editor.value == 3, "filter shows the setting with a number editor")
                editor_id = editor and editor.id
            end,
        },
        {
            snapshot = function() return snap({ { type = "change", id = editor_id, value = 7 } }, last_state) end,
            check = function(out, t)
                remember(out)
                local s = out.state and out.state.ub_settings or {}
                t.ok(s.Jumper and s.Jumper.Attempts == 7, "window edits are saved")
                local reset = find_prefix(out.ui, "ub_r_")
                t.ok(reset ~= nil, "a changed setting offers Reset")
            end,
        },
        {
            snapshot = function() return snap({ { type = "command", text = "opt list" } }, last_state) end,
            check = function(out, t)
                t.ok(has(notices(out), "All Settings: "), "opt list starts with a count")
                for _, r in ipairs(out.requests or {}) do
                    t.ok(#r.text <= 500, "each notice fits the 500-character limit")
                end
                t.ok(#(out.requests or {}) <= 4, "at most four requests per callback")
            end,
        },
        {
            snapshot = function() return snap({}, last_state, 0.3) end,
            check = function(out, t)
                t.ok(out.requests == nil, "the next callback within 0.6 s sends nothing")
            end,
        },
        {
            snapshot = function() return snap({ { type = "change", id = "ub_tool", value = "OverlayMap" } }, last_state) end,
            check = function(out, t)
                t.ok(out.requests ~= nil and #out.requests > 0, "queued list lines keep flowing")
                t.ok(#out.requests <= 4, "still at most four per callback")
                local color = find_prefix(out.ui, "ub_s_")
                local any_color
                local function scan(list)
                    for _, c in ipairs(list or {}) do
                        if c.type == "color" then any_color = c end
                        scan(c.children)
                    end
                end
                scan(out.ui)
                t.ok(any_color and string.sub(any_color.value, 1, 1) == "#" and #any_color.value == 9, "color settings use the color picker (#RRGGBBAA)")
            end,
        },
    },
}
