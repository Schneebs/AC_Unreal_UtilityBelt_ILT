-- ILT tools: Augs (advanced augmentation cost calculator, levels from "/aug") and
-- Enl (enlightenment materials calculator). Cost models and tiers are UB ILT's
-- Augs.cs and Enlightenment.cs; retail sums level by level, here each tier is an
-- arithmetic series (same totals, within the client's per-callback work limit).

local AUG_ORDER = { "Creature", "Item", "Life", "War", "Void", "Duration", "Specialization", "Summon", "Melee", "Missile" }
local AUG_LABEL = { Specialization = "SPEC" }
local AUG_MODEL = {
    Creature = { base = 750000, pct = 130, coin = 3, caps = { 2750, 4000, 4750, 5250 } },
    Item = { base = 1000000, pct = 165, coin = 18, caps = { 1250, 2000, 3000, 3500 } },
    Life = { base = 975000, pct = 195, coin = 12, caps = { 1000, 2000, 3000, 3750 } },
    War = { base = 750000, pct = 140, coin = 5, caps = { 1750, 2500, 3000, 3750 } },
    Void = { base = 800000, pct = 160, coin = 5, caps = { 1750, 2500, 3000, 3750 } },
    Duration = { base = 400000, pct = 120, coin = 5, caps = { 1000, 2000, 2500, 3000 } },
    Specialization = { base = 3000000, pct = 200, coin = 5, caps = { 1750, 2500, 3000, 3750 } },
    Summon = { base = 500000, pct = 125, coin = 5, caps = { 1750, 2500, 3000, 3750 } },
    Melee = { base = 750000, pct = 140, coin = 5, caps = { 1750, 2500, 3000, 3750 } },
    Missile = { base = 750000, pct = 140, coin = 5, caps = { 1750, 2500, 3000, 3750 } },
}
local AUG_MULT = { 1, 4, 8, 16, 24 }

local augs = { getting = false, got_first = false, heartbeat = 0, status = "" }
local enl = { page = 1 }

-- Sum of (base + (i - 1) * inc) for i = a..b.
local function series(base, inc, a, b)
    if b < a then return 0 end
    local n = b - a + 1
    return n * base + inc * ((a - 1) + (b - 1)) * n / 2
end

-- Retail GetCumulativeCost: levels below cap1 cost x1, then x4, x8, x16, and x24.
local function aug_cumulative(name, level)
    local m = AUG_MODEL[name]
    if not m or level <= 0 then return 0 end
    local inc = m.base * (m.pct / 100)
    local bounds = { 1, m.caps[1], m.caps[2], m.caps[3], m.caps[4] }
    local total = 0
    for t = 1, 5 do
        local a = bounds[t]
        local b = (t < 5) and (bounds[t + 1] - 1) or level
        if b > level then b = level end
        if a <= b then total = total + AUG_MULT[t] * series(m.base, inc, a, b) end
    end
    return total
end

local function aug_values(name)
    local d = data_get("augs")
    d.current = d.current or {}
    d.target = d.target or {}
    local cur = tonumber(d.current[name]) or 0
    local tgt = tonumber(d.target[name]) or cur
    local inc = math.max(0, tgt - cur)
    local lum = inc > 0 and (aug_cumulative(name, tgt) - aug_cumulative(name, cur)) or 0
    return cur, tgt, inc, lum, inc * AUG_MODEL[name].coin
end

local function augs_refresh()
    if augs.getting then return end
    augs.getting, augs.got_first, augs.heartbeat, augs.status = true, false, game.now, "Loading..."
    game_send("/aug")
end

local function augs_chat(lines)
    if not augs.getting then return end
    for _, line in ipairs(lines) do
        if string.contains(line, "Advanced Augmentation Levels:") then
            augs.got_first, augs.heartbeat = true, game.now
        elseif augs.got_first then
            -- "Creature: 1,234" (a word, a colon, digits with commas)
            local colon = string.findplain(line, ":")
            if colon and colon > 1 then
                local name = string.sub(line, 1, colon - 1)
                local value_text = trim(string.sub(line, colon + 1))
                local word = true
                for i = 1, #name do
                    local c = string.sub(name, i, i)
                    if not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_") then word = false end
                end
                local v = leading_number(value_text)
                if word and v then
                    for _, n in ipairs(AUG_ORDER) do
                        if string.lower(n) == string.lower(name) then
                            local d = data_get("augs")
                            d.current = d.current or {}
                            d.target = d.target or {}
                            d.current[n] = v
                            if (tonumber(d.target[n]) or 0) < v then d.target[n] = v end
                            d.updated = game.unix
                            data_changed()
                        end
                    end
                    augs.heartbeat = game.now
                end
            end
        end
    end
    if augs.got_first and game.now - augs.heartbeat > 2 then
        augs.getting, augs.status = false, ""
    elseif not augs.got_first and game.now - augs.heartbeat > 15 then
        augs.getting, augs.status = false, "Timeout (15s) reading /aug"
    end
end

local function augs_share_text()
    local parts, tl, tc = {}, 0, 0
    for _, n in ipairs(AUG_ORDER) do
        local cur, tgt, inc, lum, coin = aug_values(n)
        if inc > 0 then parts[#parts + 1] = n .. " " .. cur .. "->" .. tgt end
        tl, tc = tl + lum, tc + coin
    end
    if #parts == 0 then return "Augs: no targets set" end
    return "Augs: " .. table.concat(parts, ", ") .. " | Lum " .. short_number(tl) .. " | Coins " .. format_number(tc)
end

local function augs_page()
    local rows = {
        w_row("ub_aug_head", {
            w_label("ub_aug_h1", "Aug", { bold = true }), w_label("ub_aug_h2", "Current", { bold = true }),
            w_label("ub_aug_h3", "Target", { bold = true }), w_label("ub_aug_h4", "+", { bold = true }),
            w_label("ub_aug_h5", "Lum", { bold = true }), w_label("ub_aug_h6", "Coins", { bold = true }),
        }),
    }
    local tc, tt, ti, tl, tco = 0, 0, 0, 0, 0
    for _, n in ipairs(AUG_ORDER) do
        local cur, tgt, inc, lum, coin = aug_values(n)
        tc, tt, ti, tl, tco = tc + cur, tt + tgt, ti + inc, tl + lum, tco + coin
        rows[#rows + 1] = w_row("ub_aug_r_" .. n, {
            w_label("ub_aug_n_" .. n, AUG_LABEL[n] or string.upper(n)),
            { id = "ub_aug_c_" .. n, type = "number", value = cur, min = 0, max = 100000, step = 1 },
            { id = "ub_aug_t_" .. n, type = "number", value = tgt, min = 0, max = 100000, step = 1 },
            w_label("ub_aug_i_" .. n, tostring(inc)),
            w_label("ub_aug_l_" .. n, short_number(lum), { tooltip = format_number(lum) }),
            w_label("ub_aug_o_" .. n, format_number(coin)),
        })
    end
    rows[#rows + 1] = w_row("ub_aug_total", {
        w_label("ub_aug_tn", "TOTAL", { bold = true }), w_label("ub_aug_tc", format_number(tc), { bold = true }),
        w_label("ub_aug_tt", format_number(tt), { bold = true }), w_label("ub_aug_ti", format_number(ti), { bold = true }),
        w_label("ub_aug_tl", short_number(tl), { bold = true, tooltip = format_number(tl) }),
        w_label("ub_aug_to", format_number(tco), { bold = true }),
    })
    rows[#rows + 1] = w_row("ub_aug_btns", {
        w_button("ub_aug_refresh", augs.getting and "Loading..." or "Refresh Current", { enabled = not augs.getting }),
        w_button("ub_aug_reset", "Reset Target"),
    }, { compact = true })
    if augs.status ~= "" then rows[#rows + 1] = w_text("ub_aug_status", augs.status) end
    rows[#rows + 1] = { id = "ub_aug_copy", type = "input", text = "Share", value = augs_share_text(),
                        tooltip = "Select and copy (plugins can't write to the clipboard)" }
    return rows
end

local function augs_events(snapshot)
    for _, e in ipairs(snapshot.events or {}) do
        local id = e.id or ""
        if e.type == "click" and id == "ub_aug_refresh" then augs_refresh()
        elseif e.type == "click" and id == "ub_aug_reset" then
            local d = data_get("augs")
            d.target = {}
            for _, n in ipairs(AUG_ORDER) do d.target[n] = (d.current or {})[n] or 0 end
            data_changed()
        elseif e.type == "change" and (starts_with(id, "ub_aug_c_") or starts_with(id, "ub_aug_t_")) then
            local n, v = string.sub(id, 10), tonumber(e.value)
            if AUG_MODEL[n] and v then
                local d = data_get("augs")
                local key = starts_with(id, "ub_aug_c_") and "current" or "target"
                d[key] = d[key] or {}
                d[key][n] = math.max(0, math.tointeger(math.floor(v + 0.5)) or 0)
                data_changed()
            end
        end
    end
end

-- Enlightenment ------------------------------------------------------------------

local ENL_PAGE = 12
local ENL_MAX_RANGE = 500

local function enl_level_cost(level)
    if level >= 151 then
        return 0, level - 5, (level >= 301 and level * 2000000000 or level * 1000000000)
    elseif level >= 6 then
        return level - 5, 0, (level >= 50 and level * 100000000 or 0)
    end
    return 0, 0, 0
end

-- Counts come from typed-in numbers (saved per character): reading the whole
-- inventory every callback cost too much frame time for one tab.
local function enl_available(snapshot)
    local d = data_get("enl")
    local tokens, meds, parts = tonumber(d.have_tokens) or 0, tonumber(d.have_meds) or 0, tonumber(d.have_parts) or 0
    return {
        lum = tonumber(data_get("bank").Luminance) or 0,
        tokens = tokens,
        meds = meds + math.min(parts, tokens),
        parts = parts,
    }
end

local function enl_levels(snapshot)
    local d = data_get("enl")
    local char_level = tonumber((snapshot.char_ints or {})["390"])
    local cur = tonumber(d.current) or char_level or 150
    local tgt = tonumber(d.target) or (cur + 5)
    return cur, tgt
end

local function enl_page(snapshot)
    local cur, tgt = enl_levels(snapshot)
    local last = math.min(tgt, cur + ENL_MAX_RANGE)
    local avail = enl_available(snapshot)
    local need_tokens, need_meds, need_lum = 0, 0, 0
    local left_tokens, left_meds, left_lum = avail.tokens, avail.meds, avail.lum
    local affordable, blocked_by = 0, nil
    local levels = {}
    for level = cur + 1, last do
        local t, m, l = enl_level_cost(level)
        need_tokens, need_meds, need_lum = need_tokens + t, need_meds + m, need_lum + l
        levels[#levels + 1] = { level, t, m, l }
        if not blocked_by then
            if left_tokens < t then blocked_by = "Tokens"
            elseif left_meds < m then blocked_by = "Medallions"
            elseif left_lum < l then blocked_by = "Luminance"
            else
                left_tokens, left_meds, left_lum = left_tokens - t, left_meds - m, left_lum - l
                affordable = affordable + 1
            end
        end
    end
    local first, last_row, pages, page = w_page_bounds(#levels, enl.page, ENL_PAGE)
    enl.page = page
    local rows = {
        w_row("ub_enl_inputs", {
            { id = "ub_enl_cur", type = "number", text = "Current", value = cur, min = 0, max = 100000, step = 1 },
            { id = "ub_enl_tgt", type = "number", text = "Target", value = tgt, min = 0, max = 100000, step = 1 },
            w_label("ub_enl_count", "(" .. math.max(0, tgt - cur) .. " levels)"),
            w_button("ub_enl_refresh", "Refresh", { auto_width = true, tooltip = "Re-read your enlightenment level and bank luminance (/b)" }),
        }),
        w_row("ub_enl_head", {
            w_label("ub_enl_h1", "Level", { bold = true }), w_label("ub_enl_h2", "Tokens", { bold = true }),
            w_label("ub_enl_h3", "Medallions", { bold = true }), w_label("ub_enl_h4", "Luminance", { bold = true }),
        }),
    }
    for i = first, last_row do
        local r = levels[i]
        rows[#rows + 1] = w_row("ub_enl_r" .. i, {
            w_label("ub_enl_l" .. i, tostring(r[1]), { color = (i <= affordable) and "green" or nil }),
            w_label("ub_enl_t" .. i, tostring(r[2])), w_label("ub_enl_m" .. i, tostring(r[3])),
            w_label("ub_enl_u" .. i, short_number(r[4]), { tooltip = format_number(r[4]) }),
        })
    end
    if #levels > ENL_PAGE then rows[#rows + 1] = w_pager("ub_enl", page, pages) end
    local function summary(id, label, need, have)
        local ok = have >= need
        return w_row(id, {
            w_label(id .. "_n", label),
            w_label(id .. "_r", "Need " .. short_number(need), { tooltip = format_number(need) }),
            w_label(id .. "_a", "Have " .. short_number(have), { tooltip = format_number(have) }),
            w_label(id .. "_s", ok and "OK" or ("Short " .. short_number(need - have)), { color = ok and "green" or "red" }),
        })
    end
    rows[#rows + 1] = w_section("ub_enl_summary", "Material Summary", {
        summary("ub_enl_s_lum", "Luminance (bank)", need_lum, avail.lum),
        summary("ub_enl_s_tok", "Enlightenment Tokens", need_tokens, avail.tokens),
        summary("ub_enl_s_med", "Medallions (+parts with tokens)", need_meds, avail.meds),
        w_row("ub_enl_have", {
            { id = "ub_enl_have_tokens", type = "number", text = "Tokens I have", value = avail.tokens, min = 0, max = 1000000, step = 1 },
            { id = "ub_enl_have_meds", type = "number", text = "Medallions", value = tonumber(data_get("enl").have_meds) or 0, min = 0, max = 1000000, step = 1 },
            { id = "ub_enl_have_parts", type = "number", text = "Parts", value = avail.parts, min = 0, max = 1000000, step = 1 },
        }),
        w_text("ub_enl_status", (affordable >= #levels and #levels > 0) and ("Status: ready for all " .. #levels .. " levels")
            or ("Status: enough for " .. affordable .. " of " .. #levels .. " levels" .. (blocked_by and (" (short on " .. blocked_by .. ")") or "")),
            { color = (affordable >= #levels and #levels > 0) and "green" or "yellow" }),
    })
    if tgt - cur > ENL_MAX_RANGE then rows[#rows + 1] = w_text("ub_enl_cap", "Showing the first " .. ENL_MAX_RANGE .. " levels.") end
    return rows
end

local function enl_events(snapshot)
    for _, e in ipairs(snapshot.events or {}) do
        local id = e.id or ""
        if e.type == "change" and starts_with(id, "ub_enl_have_") then
            local v = tonumber(e.value)
            if v then
                data_get("enl")["have_" .. string.sub(id, 13)] = math.max(0, math.tointeger(math.floor(v + 0.5)) or 0)
                data_changed()
            end
        elseif e.type == "change" and (id == "ub_enl_cur" or id == "ub_enl_tgt") then
            local v = tonumber(e.value)
            if v then
                local d = data_get("enl")
                d[id == "ub_enl_cur" and "current" or "target"] = math.max(0, math.tointeger(math.floor(v + 0.5)) or 0)
                enl.page = 1
                data_changed()
            end
        elseif e.type == "click" and id == "ub_enl_refresh" then
            local d = data_get("enl")
            d.current, d.target = nil, nil
            data_changed()
            bank_refresh()
        elseif e.type == "click" then
            enl.page = w_pager_event(e, "ub_enl", enl.page)
        end
    end
end
