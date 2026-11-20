-- The UtilityBelt window: retail UB's main notebook and the ILT notebook as two tab
-- groups in one window (AC:Unreal gives a plugin a single window). The client counts
-- every control toward its 256 limit and doesn't report native tab switches, so the
-- tab bars are buttons and only the open page is built.

local UB_TABS = { "Main", "Settings", "Quests", "AutoTinker", "Aliases", "Events", "Chat Log", "Import" }
local ILT_TABS = { "Main", "QB", "Bank", "Trans", "XP Calc", "Augs", "Enl", "Pets", "Tracking", "Split", "Jewelry" }

-- Tabs whose tool isn't ported yet: its settings tool and why it's waiting.
local NOT_PORTED = {
    AutoTinker = { tool = "AutoTinker", why = "It applies salvage to items. Using items needs UtilityBelt to act alongside UCM, which waits on a client change." },
    Aliases = { tool = "Aliases", why = "Aliases run UB meta expressions, which come with the expression engine port." },
    Events = { tool = "GameEvents", why = "Game events run UB meta expressions, which come with the expression engine port." },
    ["Chat Log"] = { tool = "ChatLogger", why = "Planned: AC:Unreal already gives the plugin chat, so this is a straightforward port." },
    Pets = { tool = "Pets", why = "Summoning pets uses items, which needs UtilityBelt to act alongside UCM (client change pending)." },
    Tracking = { tool = "StatusHUD", why = "Planned next: item conversions are tracked from chat, which the plugin can read." },
    Split = { tool = "Leaftide", why = "Imbuing uses salvage on items, which needs UtilityBelt to act alongside UCM (client change pending)." },
    Jewelry = { tool = "Leaftide", why = "Imbuing uses salvage on items, which needs UtilityBelt to act alongside UCM (client change pending)." },
}

local win = { group = "UB", ub = "Main", ilt = "Main" }

local function tab_id(prefix, name)
    local out = {}
    for i = 1, #name do
        local c = string.sub(name, i, i)
        if c ~= " " then out[#out + 1] = c end
    end
    return prefix .. table.concat(out)
end

local function tab_bar(prefix, tabs, selected, per_row)
    local rows, row = {}, {}
    for _, name in ipairs(tabs) do
        row[#row + 1] = w_button(tab_id(prefix, name), name, { size = 11, color = selected == name and "yellow" or nil, bold = selected == name })
        if #row == per_row then rows[#rows + 1] = w_row(prefix .. "row" .. #rows, row, { compact = true }); row = {} end
    end
    if #row > 0 then rows[#rows + 1] = w_row(prefix .. "row" .. #rows, row, { compact = true }) end
    return rows
end

local function not_ported_page(name)
    local info = NOT_PORTED[name]
    return {
        w_tool_note("ub_np_title", name .. " isn't ported yet."),
        w_text("ub_np_why", info.why),
        w_text("ub_np_kept", "Its settings are kept and editable now."),
        w_row("ub_np_btn", { w_button("ub_goto_" .. info.tool, "Open " .. info.tool .. " settings") }, { compact = true }),
    }
end

local UB_MAIN_TOGGLES = {
    { "AutoVendor.Enabled", "AutoVendor" }, { "AutoVendor.TestMode", "AutoVendor Test Mode" },
    { "AutoTrade.Enabled", "AutoTrade" }, { "AutoTrade.TestMode", "AutoTrade Test Mode" },
    { "Arrow.Enabled", "Arrow" }, { "ChatFilter.Enabled", "Chat Filter" },
    { "DungeonMaps.Enabled", "Dungeon Maps" }, { "LandscapeMaps.Enabled", "Landscape Maps" },
    { "VisualNav.Enabled", "Visual Nav" }, { "Nametags.Enabled", "Nametags" },
    { "Plugin.VideoPatch", "Video Patch" }, { "Plugin.VideoPatchFocus", "Video Patch (focus)" },
    { "NetworkUI.Enabled", "Network UI" }, { "Plugin.Debug", "Debug" },
}

local ILT_MAIN_TOGGLES = {
    { "DispelTool.AutoDispelEnabled", "Auto-Dispel" }, { "Pets.Enabled", "Heal Buddy" },
    { "SurgingStrength.Enabled", "Surging Str" }, { "Enlightenment.AutoEnlightenEnabled", "Auto-Enlighten" },
}

local function toggle_grid(prefix, toggles)
    local rows = {}
    for i = 1, #toggles, 2 do
        local a, b = toggles[i], toggles[i + 1]
        rows[#rows + 1] = w_row(prefix .. i, {
            w_setting_check(a[1], a[2]),
            b and w_setting_check(b[1], b[2]) or w_label(prefix .. "pad" .. i, ""),
        })
    end
    return rows
end

local function ub_main_page()
    local rows = {
        w_text("ub_main_note", "Retail switches. These tools aren't ported yet; switches save the setting.", { color = "yellow", size = 11 }),
    }
    for _, r in ipairs(toggle_grid("ub_main_t", UB_MAIN_TOGGLES)) do rows[#rows + 1] = r end
    rows[#rows + 1] = w_text("ub_main_alt", "Waypoint covers Arrow and the maps; Hunt Ledger covers the XP meter.", { size = 11 })
    return rows
end

local function ilt_main_page(snapshot)
    local rows = {}
    if not leaftide_active(snapshot.server) then
        rows[#rows + 1] = w_tool_note("ub_ilt_gate", "Not on InfiniteLeaftide. For a test server, force ILT features:")
        rows[#rows + 1] = w_setting_check("Plugin.ForceLeaftideFeatures", "Force Leaftide features on this server")
    end
    rows[#rows + 1] = w_text("ub_ilt_note", "Not ported yet (they use items); switches save the setting.", { color = "yellow", size = 11 })
    for _, r in ipairs(toggle_grid("ub_ilt_t", ILT_MAIN_TOGGLES)) do rows[#rows + 1] = r end
    rows[#rows + 1] = w_row("ub_ilt_actions", {
        w_button("ub_ilt_chunk", "Chunk Aeth", { enabled = false, tooltip = "Not ported yet (uses items)" }),
        w_button("ub_ilt_chunkc", "Chunk Corr", { enabled = false, tooltip = "Not ported yet (uses items)" }),
        w_button("ub_ilt_clap", "Auto-Clap", { enabled = false, tooltip = "Not ported yet (uses items)" }),
    })
    rows[#rows + 1] = w_text("ub_ilt_working", "Working now: QB, Bank, Trans, XP Calc, Augs, Enl.", { color = "green", size = 11 })
    return rows
end

local function import_page()
    return {
        w_label("ub_version", "UtilityBelt " .. UB_VERSION .. " for AC:Unreal", { bold = true }),
        w_text("ub_port_note", "UB tools are being ported one at a time. Your settings are kept here by their retail names, so each tool uses them as soon as it's ported."),
        w_text("ub_cmd_note", "Commands: /plugin utilitybelt opt list | get <option> | set <option> <value> | toggle <option>, and /plugin utilitybelt help."),
        w_text("ub_retail_status", retail.status),
        w_button("ub_retail_import", "Import from retail", {
            tooltip = "Replace this character's settings with its retail UtilityBelt settings (run UB Manager's Import first)",
            enabled = retail.pending == nil }),
    }
end

local function window_events(snapshot)
    if ub_ui.goto_settings then
        win.group, win.ub, ub_ui.goto_settings = "UB", "Settings", nil
    end
    for _, e in ipairs(snapshot.events or {}) do
        local id = e.id or ""
        if e.type == "click" then
            if id == "ub_grp_UB" then win.group = "UB" elseif id == "ub_grp_ILT" then win.group = "ILT" end
            for _, name in ipairs(UB_TABS) do if id == tab_id("ub_t_", name) then win.ub = name end end
            for _, name in ipairs(ILT_TABS) do if id == tab_id("ub_i_", name) then win.ilt = name end end
            if starts_with(id, "ub_goto_") then
                win.group, win.ub = "UB", "Settings"
                show_tool_settings(string.sub(id, 9))
            end
        end
    end
end

-- Final pass over the window: the client rejects the whole UI (and stops the plugin)
-- if any ID is empty, repeated or over 64 characters, or text/tooltips are too long.
-- Also applies the compact default font size.
local UI_FONT = 12
local SIZED = { text = true, button = true, checkbox = true, input = true, select = true, number = true, section = true }

local function ui_finalize(list, seen)
    seen = seen or {}
    for i, c in ipairs(list) do
        local id = tostring(c.id or ("ub_auto_" .. i))
        if #id > 64 then id = string.sub(id, 1, 52) .. "_" .. tostring(#id) .. "_" .. tostring(i) end
        if seen[id] then
            seen[id] = seen[id] + 1
            id = string.sub(id, 1, 56) .. "~" .. seen[id]
        end
        seen[id] = seen[id] or 1
        c.id = id
        if type(c.text) == "string" and #c.text > 4000 then c.text = string.sub(c.text, 1, 3997) .. "..." end
        if type(c.tooltip) == "string" and #c.tooltip > 1000 then c.tooltip = string.sub(c.tooltip, 1, 997) .. "..." end
        if SIZED[c.type] and c.size == nil then c.size = UI_FONT end
        if type(c.children) == "table" then ui_finalize(c.children, seen) end
    end
    return list
end

local function window_build(snapshot)
    local root = {
        w_row("ub_groups", {
            w_button("ub_grp_UB", "UtilityBelt", { size = 13, color = win.group == "UB" and "yellow" or nil, bold = win.group == "UB" }),
            w_button("ub_grp_ILT", "ILT", { size = 13, color = win.group == "ILT" and "yellow" or nil, bold = win.group == "ILT" }),
        }, { compact = true }),
    }
    local page
    if win.group == "UB" then
        for _, r in ipairs(tab_bar("ub_t_", UB_TABS, win.ub, 8)) do root[#root + 1] = r end
        if win.ub == "Main" then page = ub_main_page()
        elseif win.ub == "Settings" then page = settings_page(snapshot)
        elseif win.ub == "Quests" then page = quests_page()
        elseif win.ub == "Import" then page = import_page()
        else page = not_ported_page(win.ub) end
    else
        for _, r in ipairs(tab_bar("ub_i_", ILT_TABS, win.ilt, 6)) do root[#root + 1] = r end
        if win.ilt ~= "Main" and not leaftide_active(snapshot.server) then
            root[#root + 1] = w_tool_note("ub_ilt_warn", "Not on InfiniteLeaftide: these commands need an ILT server (see ILT > Main).")
        end
        if win.ilt == "Main" then page = ilt_main_page(snapshot)
        elseif win.ilt == "QB" then page = qb_page()
        elseif win.ilt == "Bank" then page = bank_page()
        elseif win.ilt == "Trans" then page = trans_page()
        elseif win.ilt == "XP Calc" then page = xp_page(snapshot)
        elseif win.ilt == "Augs" then page = augs_page()
        elseif win.ilt == "Enl" then page = enl_page(snapshot)
        else page = not_ported_page(win.ilt) end
    end
    root[#root + 1] = w_column("ub_page", page)
    -- A frame overlays its children, so the content goes in one column inside it.
    return ui_finalize({ { id = "ub_frame", type = "frame", color = "#0A0806D9", children = { w_column("ub_root", root) } } })
end
