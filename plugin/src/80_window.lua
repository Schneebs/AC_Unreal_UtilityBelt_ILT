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
        row[#row + 1] = w_button(tab_id(prefix, name), name, { color = selected == name and "yellow" or nil, bold = selected == name })
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
        w_text("ub_np_kept", "Its retail settings are kept and can be edited now; the tool will use them once it's ported."),
        w_button("ub_goto_" .. info.tool, "Open " .. info.tool .. " settings"),
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
        w_text("ub_main_note", "Retail's switches. The tools behind them aren't ported yet, so for now they only save the setting.", { color = "yellow" }),
    }
    for _, r in ipairs(toggle_grid("ub_main_t", UB_MAIN_TOGGLES)) do rows[#rows + 1] = r end
    rows[#rows + 1] = w_text("ub_main_alt", "In AC:Unreal, Waypoint covers Arrow and the maps, and Hunt Ledger covers the XP meter.")
    return rows
end

local function ilt_main_page(snapshot)
    local rows = {}
    if not leaftide_active(snapshot.server) then
        rows[#rows + 1] = w_tool_note("ub_ilt_gate", "ILT tools are for InfiniteLeaftide. On another server (such as a test server), turn on Plugin.ForceLeaftideFeatures.")
        rows[#rows + 1] = w_setting_check("Plugin.ForceLeaftideFeatures", "Force Leaftide features on this server")
    end
    rows[#rows + 1] = w_text("ub_ilt_note", "These switches save their settings; the tools behind them aren't ported yet (they use items or spells, which needs UtilityBelt to act alongside UCM).", { color = "yellow" })
    for _, r in ipairs(toggle_grid("ub_ilt_t", ILT_MAIN_TOGGLES)) do rows[#rows + 1] = r end
    rows[#rows + 1] = w_row("ub_ilt_actions", {
        w_button("ub_ilt_chunk", "Chunk Aeth", { enabled = false, tooltip = "Not ported yet (uses items)" }),
        w_button("ub_ilt_chunkc", "Chunk Corr", { enabled = false, tooltip = "Not ported yet (uses items)" }),
        w_button("ub_ilt_clap", "Auto-Clap", { enabled = false, tooltip = "Not ported yet (uses items)" }),
    })
    rows[#rows + 1] = w_text("ub_ilt_working", "Working now: QB, Bank, Trans, XP Calc, Augs and Enl.", { color = "green" })
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

local function window_build(snapshot)
    local root = {
        w_row("ub_groups", {
            w_button("ub_grp_UB", "UtilityBelt", { color = win.group == "UB" and "yellow" or nil, bold = win.group == "UB" }),
            w_button("ub_grp_ILT", "ILT", { color = win.group == "ILT" and "yellow" or nil, bold = win.group == "ILT" }),
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
            root[#root + 1] = w_tool_note("ub_ilt_warn", "Not on InfiniteLeaftide: these commands only work on ILT servers (see ILT > Main).")
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
    return root
end
