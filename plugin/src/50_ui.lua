-- The UtilityBelt window: retail UB's settings, tool by tool, with an editor per
-- setting (checkbox, number, text, color), a filter across all tools, and the retail
-- import. The client allows 256 controls per window, so settings are paged.

local PAGE_SIZE = 24

local entry_index = {}      -- entry -> position in settings.list (control IDs use it)
for i, entry in ipairs(settings.list) do entry_index[entry] = i end

local tool_names = {}
for _, tool in ipairs(settings.tools) do
    if #tool.settings > 0 then tool_names[#tool_names + 1] = tool.name end
end

local function is_color(entry)
    return entry.type == "int" and string.contains(string.lower(entry.short), "color")
end

-- Retail stores colors as signed 32-bit ARGB; the color control uses #RRGGBBAA.
local function argb_to_hex(n)
    n = math.tointeger(n) or 0
    if n < 0 then n = n + 0x100000000 end
    local a, r, g, b = (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255
    return string.format("#%02X%02X%02X%02X", r, g, b, a)
end

local function hex_to_argb(hex)
    hex = tostring(hex or "")
    if string.sub(hex, 1, 1) == "#" then hex = string.sub(hex, 2) end
    if #hex == 6 then hex = hex .. "FF" end
    local v = #hex == 8 and tonumber(hex, 16) or nil
    if not v then return nil end
    local r, g, b, a = (v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255
    local n = (a << 24) | (r << 16) | (g << 8) | b
    if n >= 0x80000000 then n = n - 0x100000000 end
    return n
end

-- Entries shown for the current tool or filter.
local function ui_entries()
    local out = {}
    local f = string.lower(trim(ub_ui.filter or ""))
    if f ~= "" then
        for _, entry in ipairs(settings.list) do
            if string.contains(string.lower(entry.name), f) or string.contains(string.lower(entry.summary or ""), f) then
                out[#out + 1] = entry
            end
        end
        return out
    end
    for _, tool in ipairs(settings.tools) do
        if tool.name == ub_ui.tool then
            for _, entry in ipairs(tool.settings) do out[#out + 1] = entry end
        end
    end
    return out
end

local function editor_for(entry, id)
    local value = settings_get(entry)
    local t = entry.type
    if t == "bool" then
        return { id = id, type = "checkbox", text = "", value = value == true, tooltip = entry.summary }
    elseif is_color(entry) then
        return { id = id, type = "color", text = "", value = argb_to_hex(value), tooltip = entry.summary }
    elseif t == "int" then
        return { id = id, type = "number", value = value or 0, step = 1, tooltip = entry.summary }
    elseif t == "float" then
        return { id = id, type = "number", value = value or 0, step = 0.01, tooltip = entry.summary }
    elseif t == "string" or t == "enum" then
        return { id = id, type = "input", text = "", value = tostring(value or ""), tooltip = entry.summary }
    elseif t == "list" then
        local items = {}
        for _, v in ipairs(type(value) == "table" and value or {}) do items[#items + 1] = tostring(v) end
        return { id = id, type = "input", text = "", value = table.concat(items, ", "),
                 tooltip = (entry.summary or "") .. " (comma separated)" }
    end
    local shown = settings_display(entry, value)
    return { id = id, type = "text", text = #shown > 60 and (string.sub(shown, 1, 57) .. "...") or shown,
             wrap = false, ellipsis = true, tooltip = shown .. "\nChange this with /ub opt or in retail UtilityBelt." }
end

-- Applies change/click events from the window. Returns true when something changed.
local function ui_events(snapshot)
    local changed = false
    for _, e in ipairs(snapshot.events or {}) do
        local id = e.id or ""
        if e.type == "change" and id == "ub_tool" then
            ub_ui.tool, ub_ui.page, ub_ui.filter = e.value, 1, ""
        elseif e.type == "change" and id == "ub_filter" then
            ub_ui.filter, ub_ui.page = tostring(e.value or ""), 1
        elseif e.type == "click" and id == "ub_prev" then
            ub_ui.page = math.max(1, ub_ui.page - 1)
        elseif e.type == "click" and id == "ub_next" then
            ub_ui.page = ub_ui.page + 1
        elseif e.type == "click" and id == "ub_clear_filter" then
            ub_ui.filter, ub_ui.page = "", 1
        elseif string.sub(id, 1, 5) == "ub_s_" and e.type == "change" then
            local entry = settings.list[tonumber(string.sub(id, 6))]
            if entry then
                local v
                if entry.type == "bool" then v = e.value == true
                elseif is_color(entry) then v = hex_to_argb(e.value)
                elseif entry.type == "int" then v = tonumber(e.value); v = v and (math.tointeger(math.floor(v + 0.5)) or v)
                elseif entry.type == "float" then v = tonumber(e.value)
                else v = settings_parse(entry, e.value or "") end
                if v ~= nil then settings_put(entry, v); changed = true end
            end
        elseif string.sub(id, 1, 5) == "ub_r_" and e.type == "click" then
            local entry = settings.list[tonumber(string.sub(id, 6))]
            if entry then settings_put(entry, nil); changed = true end
        end
    end
    return changed
end

local function ui_build(snapshot)
    if not ub_ui.tool then ub_ui.tool = tool_names[1] end
    local entries = ui_entries()
    local pages = math.max(1, (#entries + PAGE_SIZE - 1) // PAGE_SIZE)
    if ub_ui.page > pages then ub_ui.page = pages end
    local first = (ub_ui.page - 1) * PAGE_SIZE + 1

    local rows = {}
    for i = first, math.min(#entries, first + PAGE_SIZE - 1) do
        local entry = entries[i]
        local n = entry_index[entry]
        local changed = settings_raw(entry) ~= nil
        local label = ub_ui.filter ~= "" and entry.name or entry.short
        local row = {
            { id = "ub_l_" .. n, type = "text", text = label, wrap = false, ellipsis = true, bold = changed,
              tooltip = entry.name .. "\n" .. (entry.summary or "") .. (entry.store == "state" and "\n(per-character state)" or "") },
            editor_for(entry, "ub_s_" .. n),
        }
        if changed then
            row[#row + 1] = { id = "ub_r_" .. n, type = "button", text = "Reset", auto_width = true,
                              tooltip = "Back to the default: " .. settings_display(entry, entry.default) }
        end
        rows[#rows + 1] = { id = "ub_row_" .. n, type = "row", children = row }
    end
    if #rows == 0 then
        rows[1] = { id = "ub_none", type = "text", text = "No settings match \"" .. ub_ui.filter .. "\"." }
    end

    local selected_tool
    for _, tool in ipairs(settings.tools) do if tool.name == ub_ui.tool then selected_tool = tool end end
    local header = {}
    if ub_ui.filter ~= "" then
        header[1] = { id = "ub_tool_summary", type = "text", text = #entries .. " settings match \"" .. ub_ui.filter .. "\"", wrap = true }
    elseif selected_tool then
        local note = selected_tool.summary or ""
        if selected_tool.leaftide and not leaftide_active(snapshot.server) then
            note = note .. " (Leaftide tool: active on InfiniteLeaftide, or set Plugin.ForceLeaftideFeatures.)"
        end
        header[1] = { id = "ub_tool_summary", type = "text", text = note, wrap = true }
    end

    local settings_page = {
        { id = "ub_pick", type = "row", children = {
            { id = "ub_tool", type = "select", text = "Tool", value = ub_ui.tool, options = tool_names },
            { id = "ub_filter", type = "input", text = "Filter", value = ub_ui.filter,
              tooltip = "Search every tool's settings by name or description" },
        } },
    }
    for _, h in ipairs(header) do settings_page[#settings_page + 1] = h end
    settings_page[#settings_page + 1] = { id = "ub_list", type = "column", children = rows }
    settings_page[#settings_page + 1] = { id = "ub_pager", type = "row", compact = true, children = {
        { id = "ub_prev", type = "button", text = "< Prev", enabled = ub_ui.page > 1 },
        { id = "ub_page", type = "text", text = "Page " .. ub_ui.page .. " of " .. pages },
        { id = "ub_next", type = "button", text = "Next >", enabled = ub_ui.page < pages },
        { id = "ub_clear_filter", type = "button", text = "Clear filter", enabled = ub_ui.filter ~= "" },
    } }

    local about_page = {
        { id = "ub_version", type = "text", text = "UtilityBelt " .. UB_VERSION .. " for AC:Unreal", bold = true },
        { id = "ub_port_note", type = "text", wrap = true,
          text = "UB tools are being ported one at a time. Your settings are kept here, by their retail names, so each tool uses them as soon as it is ported." },
        { id = "ub_cmd_note", type = "text", wrap = true,
          text = "Commands: /plugin utilitybelt opt list | get <option> | set <option> <value> | toggle <option>, and /plugin utilitybelt help." },
        { id = "ub_retail_status", type = "text", text = retail.status, wrap = true },
        { id = "ub_retail_import", type = "button", text = "Import from retail",
          tooltip = "Replace this character's settings with its retail UtilityBelt settings (run UB Manager's Import first)",
          enabled = retail.pending == nil },
    }

    return {
        { id = "ub_tabs", type = "tabs", children = {
            { id = "ub_tab_settings", type = "column", text = "Settings", children = settings_page },
            { id = "ub_tab_about", type = "column", text = "Import / About", children = about_page },
        } },
    }
end
