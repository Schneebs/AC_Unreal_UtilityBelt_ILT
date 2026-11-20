-- ILT tool: XP Calc. Reads attribute costs from "/xp all", raises attributes with
-- "/attr <abbr> <n>", and optionally auto-upgrades (XPCalculator.AutoUpgrade*), as
-- UB ILT's XPCalculator.cs does: priority order, one level at a time, waiting for
-- "Your base X is now N!" before the next.

local XP_ATTRS = {
    { key = "Strength", abbr = "str", auto = "XPCalculator.AutoUpgradeStrength", chat = "strength" },
    { key = "Endurance", abbr = "end", auto = "XPCalculator.AutoUpgradeEndurance", chat = "endurance" },
    { key = "Coordination", abbr = "coo", auto = "XPCalculator.AutoUpgradeCoordination", chat = "coordination" },
    { key = "Quickness", abbr = "qui", auto = "XPCalculator.AutoUpgradeQuickness", chat = "quickness" },
    { key = "Focus", abbr = "foc", auto = "XPCalculator.AutoUpgradeFocus", chat = "focus" },
    { key = "Self", abbr = "sel", auto = "XPCalculator.AutoUpgradeSelf", chat = "self" },
    { key = "MaxHealth", abbr = "hea", auto = "XPCalculator.AutoUpgradeHealth", chat = "health", base = "base_health" },
    { key = "MaxStamina", abbr = "sta", auto = "XPCalculator.AutoUpgradeStamina", chat = "stamina", base = "base_stamina" },
    { key = "MaxMana", abbr = "man", auto = "XPCalculator.AutoUpgradeMana", chat = "mana", base = "base_mana" },
}

local xp = { getting_until = 0, status = "", auto_next = 0, waiting = nil, wait_until = 0 }

local function xp_attr(name)
    local l = string.lower(name or "")
    for _, a in ipairs(XP_ATTRS) do
        if string.lower(a.key) == l or a.chat == l then return a end
    end
end

local function xp_refresh()
    if game.now < xp.getting_until then return end
    xp.getting_until = game.now + 5
    game_send("/xp all")
end

local function xp_unassigned(snapshot)
    local q = snapshot.char_quads or {}
    return tonumber(q["2"] or q[2]) or 0, tonumber(q["1"] or q[1]) or 0
end

local function xp_chat(lines)
    for _, line in ipairs(lines) do
        -- "[XP] Your XP cost for next 1 Strength level is: 5,535,144,505"
        if starts_with(line, "[XP] Your XP cost for next 1 ") then
            local rest = string.sub(line, 30)
            local sp = string.findplain(rest, " ")
            local at = string.findplain(rest, "level is: ")
            local a = sp and xp_attr(string.sub(rest, 1, sp - 1))
            local cost = at and leading_number(string.sub(rest, at + 10))
            if a and cost then
                local d = data_get("xp")
                d.costs = d.costs or {}
                d.costs[a.key] = cost
                d.updated = game.unix
                data_changed()
            end
        -- "Your base Strength is now 377!" / "Your base Maximum Stamina is now 648!"
        elseif starts_with(line, "Your base ") and string.contains(line, " is now ") then
            local rest = string.sub(line, 11)
            if starts_with(rest, "Maximum ") then rest = string.sub(rest, 9) end
            local at = string.findplain(rest, " is now ")
            local a = at and xp_attr(string.sub(rest, 1, at - 1))
            local v = at and leading_number(string.sub(rest, at + 8))
            if a and v then
                local d = data_get("xp")
                d.values = d.values or {}
                d.values[a.key] = v
                data_changed()
                if xp.waiting == a.key then
                    xp.waiting = nil
                    xp.auto_next = game.now + 1      -- refresh costs, then try the next level
                    xp_refresh()
                end
            end
        end
    end
end

-- Auto-upgrade, one level at a time, in priority order.
local function xp_auto_tick(snapshot)
    if opt("XPCalculator.AutoUpgradeEnabled") ~= true then xp.waiting = nil; return end
    if xp.waiting then
        if game.now > xp.wait_until then
            xp.waiting = nil
            xp.status = "Auto-upgrade: no confirmation, retrying next cycle"
            xp.auto_next = game.now + math.max(1, opt("XPCalculator.AutoUpgradeInterval") or 5) * 60
        end
        return
    end
    if game.now < xp.auto_next or game.now < xp.getting_until then return end
    local d = data_get("xp")
    if not d.updated or game.unix - d.updated > 60 then
        xp_refresh()
        xp.auto_next = game.now + 4
        return
    end
    local unassigned = xp_unassigned(snapshot)
    local order = split_commas(tostring(opt("XPCalculator.AutoUpgradePriority") or ""))
    for _, name in ipairs(order) do
        local a = xp_attr(name)
        local cost = a and d.costs and d.costs[a.key]
        if a and cost and opt(a.auto) == true and unassigned >= cost then
            game_send("/attr " .. a.abbr .. " 1")
            xp.waiting, xp.wait_until = a.key, game.now + 6
            xp.status = "Auto-upgrading " .. a.key .. " +1 (cost " .. short_number(cost) .. ")"
            return
        end
    end
    xp.status = "Auto-upgrade: nothing affordable"
    xp.auto_next = game.now + math.max(1, opt("XPCalculator.AutoUpgradeInterval") or 5) * 60
end

local function xp_page(snapshot)
    local d = data_get("xp")
    local unassigned, total = xp_unassigned(snapshot)
    local rows = {
        w_row("ub_xp_top", {
            w_label("ub_xp_level", "Current Level: " .. tostring(snapshot.level or "?")),
            w_label("ub_xp_total", "Total XP: " .. short_number(total)),
            w_label("ub_xp_unassigned", "Unassigned: " .. short_number(unassigned)),
        }),
        w_row("ub_xp_auto", {
            w_setting_check("XPCalculator.AutoUpgradeEnabled", "Enable Auto-Upgrade"),
            { id = "ub_xp_interval", type = "number", text = "Every (min)", min = 1, max = 120, step = 1,
              value = opt("XPCalculator.AutoUpgradeInterval") or 5 },
        }),
        w_row("ub_xp_head", {
            w_label("ub_xp_h1", "Attribute", { bold = true }), w_label("ub_xp_h2", "Next level", { bold = true }),
            w_label("ub_xp_h3", "Auto", { bold = true }), w_label("ub_xp_h4", "Raise", { bold = true }),
        }),
    }
    for _, a in ipairs(XP_ATTRS) do
        local value = (d.values and d.values[a.key]) or (a.base and snapshot[a.base]) or nil
        local cost = d.costs and d.costs[a.key]
        rows[#rows + 1] = w_row("ub_xp_r_" .. a.abbr, {
            w_label("ub_xp_n_" .. a.abbr, a.key .. " (" .. (value and tostring(value) or "?") .. ")"),
            w_label("ub_xp_c_" .. a.abbr, cost and short_number(cost) or "?",
                    { color = (cost and unassigned >= cost) and "green" or nil, tooltip = cost and format_number(cost) or "Press Refresh XP" }),
            w_setting_check(a.auto, "", "Auto-upgrade " .. a.key),
            w_row("ub_xp_b_" .. a.abbr, {
                w_button("ub_xp_p1_" .. a.abbr, "+1"), w_button("ub_xp_p10_" .. a.abbr, "+10"),
            }, { compact = true }),
        })
    end
    rows[#rows + 1] = w_row("ub_xp_bottom", {
        w_button("ub_xp_refresh", game.now < xp.getting_until and "Please Wait..." or "Refresh XP", { auto_width = true }),
        w_label("ub_xp_updated", "Last Updated: " .. format_ago(d.updated)),
    })
    rows[#rows + 1] = w_text("ub_xp_priority", "Auto-upgrade priority: " .. tostring(opt("XPCalculator.AutoUpgradePriority") or "")
        .. " (change with /plugin utilitybelt opt set XPCalculator.AutoUpgradePriority ...)")
    if xp.status ~= "" then rows[#rows + 1] = w_text("ub_xp_status", xp.status) end
    return rows
end

local function xp_events(snapshot)
    for _, e in ipairs(snapshot.events or {}) do
        local id = e.id or ""
        if e.type == "click" then
            if id == "ub_xp_refresh" then xp_refresh() end
            for _, a in ipairs(XP_ATTRS) do
                if id == "ub_xp_p1_" .. a.abbr then game_send("/attr " .. a.abbr .. " 1") end
                if id == "ub_xp_p10_" .. a.abbr then game_send("/attr " .. a.abbr .. " 10") end
            end
        elseif e.type == "change" and id == "ub_xp_interval" then
            local n = tonumber(e.value)
            if n then opt_set("XPCalculator.AutoUpgradeInterval", math.tointeger(math.floor(n + 0.5)) or 5) end
        end
    end
end
