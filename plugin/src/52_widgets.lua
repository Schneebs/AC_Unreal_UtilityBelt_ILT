-- Small constructors for window controls, so tab pages read like retail's layouts.

local function w_text(id, text, extra)
    local c = { id = id, type = "text", text = tostring(text or ""), wrap = true }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function w_label(id, text, extra)
    local c = { id = id, type = "text", text = tostring(text or ""), wrap = false, ellipsis = true }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function w_button(id, text, extra)
    local c = { id = id, type = "button", text = text }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

-- Drops nil entries (e.g. a w_setting_check for a setting the schema lacks).
local function w_compact(children)
    local keys = {}
    for k, _ in pairs(children or {}) do if type(k) == "number" then keys[#keys + 1] = k end end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = children[k] end
    return out
end

local function w_row(id, children, extra)
    local c = { id = id, type = "row", children = w_compact(children) }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function w_column(id, children, extra)
    local c = { id = id, type = "column", children = w_compact(children) }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

local function w_section(id, text, children)
    return { id = id, type = "section", text = text, expanded = true, children = children }
end

-- A checkbox bound to a retail setting (id "ub_opt_<setting name>").
local function w_setting_check(name, text, tooltip)
    local entry = settings.by_name[string.lower(name)]
    if not entry then return nil end
    return { id = "ub_opt_" .. entry.name, type = "checkbox", text = text or entry.short,
             value = settings_get(entry) == true, tooltip = tooltip or entry.summary }
end

-- Applies changes from w_setting_check controls.
local function w_setting_events(snapshot)
    for _, e in ipairs(snapshot.events or {}) do
        if e.type == "change" and type(e.id) == "string" and starts_with(e.id, "ub_opt_") then
            local entry = settings.by_name[string.lower(string.sub(e.id, 8))]
            if entry and entry.type == "bool" then settings_put(entry, e.value == true) end
        end
    end
end

-- Header lines shared by tool pages: summary, Leaftide gate, "not ported" note.
local function w_tool_note(id, text)
    return w_text(id, text, { color = "yellow" })
end

-- Paged list helper: returns (first, last, pages) and clamps the page number.
local function w_page_bounds(count, page, size)
    local pages = math.max(1, (count + size - 1) // size)
    if page > pages then page = pages end
    if page < 1 then page = 1 end
    local first = (page - 1) * size + 1
    return first, math.min(count, first + size - 1), pages, page
end

local function w_pager(prefix, page, pages)
    return w_row(prefix .. "_pager", {
        w_button(prefix .. "_prev", "< Prev", { enabled = page > 1 }),
        w_label(prefix .. "_pageinfo", "Page " .. page .. " of " .. pages),
        w_button(prefix .. "_next", "Next >", { enabled = page < pages }),
    }, { compact = true })
end

-- Updates a page number from pager clicks.
local function w_pager_event(e, prefix, page)
    if e.type ~= "click" then return page end
    if e.id == prefix .. "_prev" then return math.max(1, page - 1) end
    if e.id == prefix .. "_next" then return page + 1 end
    return page
end
