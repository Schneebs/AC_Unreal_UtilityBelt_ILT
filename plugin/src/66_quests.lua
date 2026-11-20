-- Retail tool: QuestTracker (the Quests tab). Reads "/myquests" replies, split into
-- Timed, KillTask and Once like retail (Lib/Quests/QuestFlag.cs). Lines look like:
--   key - 3 solves (1700000000)"Description" 10 72000
-- AutoRequest runs /myquests once after login; QuestRefreshCooldownSeconds limits refreshes.

local QUEST_PAGE = 18
local QUEST_TABS = { "Timed", "KillTask", "Once" }

local quests = { flags = {}, count = 0, tab = "Timed", filter = "", page = 1,
                 status = "Press Refresh to read /myquests", last_request = -100000,
                 auto_done = false, login_time = nil }

local function quest_parse(line)
    local dash = string.findplain(line, " - ")
    if not dash then return nil end
    local key = string.lower(trim(string.sub(line, 1, dash - 1)))
    if key == "" or string.contains(key, " ") then return nil end
    local sv = string.findplain(line, " solves (", dash)
    if not sv then return nil end
    local solves = tonumber(trim(string.sub(line, dash + 3, sv - 1)))
    local close = string.findplain(line, ")", sv)
    if not solves or not close then return nil end
    local completed = tonumber(string.sub(line, sv + 9, close - 1)) or 0
    local q = { key = key, solves = solves, completed = completed, max = 0, rep = 0, desc = "" }
    local rest = string.sub(line, close + 1)
    if string.sub(rest, 1, 1) == "\"" then
        -- Description ends at the last '" ' before "<max> <repeat>".
        local last, from = nil, 2
        while true do
            local i = string.findplain(rest, "\" ", from)
            if not i then break end
            last, from = i, i + 1
        end
        if last then
            q.desc = string.sub(rest, 2, last - 1)
            local nums = split_words(trim(string.sub(rest, last + 2)))
            q.max = tonumber(nums[1]) or 0
            q.rep = tonumber(nums[2]) or 0
        end
    end
    return q
end

local function quest_type(q)
    local k = q.key
    local kill = string.contains(k, "killtask") or string.contains(k, "killcount") or string.contains(k, "slayerquest")
        or string.sub(k, -5) == "kills"
    if not kill then
        local g = string.findplain(k, "totalgolem")
        kill = g ~= nil and string.findplain(k, "dead", g) ~= nil
    end
    if kill and q.max >= 0 then return "KillTask" end
    if q.max == 1 and q.solves <= 1 then return "Once" end
    return "Timed"
end

local function quest_remaining(q)
    return (q.completed + q.rep) - game.unix
end

local function quests_refresh(manual)
    local cooldown = tonumber(opt("QuestTracker.QuestRefreshCooldownSeconds")) or 0
    if game.now - quests.last_request < cooldown then
        if manual then quests.status = "Wait " .. format_duration(cooldown - (game.now - quests.last_request)) .. " before refreshing again" end
        return
    end
    quests.last_request = game.now
    quests.status = "Reading /myquests..."
    game_send("/myquests")
end

local function quests_chat(lines, snapshot)
    for _, line in ipairs(lines) do
        if string.contains(line, " solves (") then
            local q = quest_parse(line)
            if q then
                if not quests.flags[q.key] then quests.count = quests.count + 1 end
                quests.flags[q.key] = q
                quests.status = quests.count .. " quest flags"
            end
        elseif line == "Quest list is empty." or string.contains(line, "\"myquests\" is not currently enabled") then
            quests.status = line
        elseif string.contains(line, "This command may only be run once every") then
            quests.status = line
        end
    end
    -- AutoRequest: once, a few seconds after login.
    if not quests.auto_done and snapshot.character_name then
        quests.login_time = quests.login_time or game.now
        if game.now - quests.login_time > 5 then
            quests.auto_done = true
            if opt("QuestTracker.AutoRequest") ~= false then quests_refresh(false) end
        end
    end
end

local function quests_list()
    local out, f = {}, string.lower(trim(quests.filter))
    for _, q in pairs(quests.flags) do
        if quest_type(q) == quests.tab and (f == "" or string.contains(q.key, f) or string.contains(string.lower(q.desc), f)) then
            out[#out + 1] = q
        end
    end
    table.sort(out, function(a, b)
        local ra, rb = quest_remaining(a), quest_remaining(b)
        local wa, wb = ra > 0, rb > 0
        if wa ~= wb then return wa end              -- waiting ones first (retail order)
        if wa and ra ~= rb then return ra < rb end  -- soonest first
        return a.key < b.key
    end)
    return out
end

local function quests_page()
    local list = quests_list()
    local first, last, pages, page = w_page_bounds(#list, quests.page, QUEST_PAGE)
    quests.page = page
    local tabs = {}
    for _, t in ipairs(QUEST_TABS) do
        tabs[#tabs + 1] = w_button("ub_qt_tab_" .. t, t, { color = quests.tab == t and "yellow" or nil, bold = quests.tab == t })
    end
    local rows = {
        w_row("ub_qt_tabs", tabs, { compact = true }),
        w_row("ub_qt_top", {
            { id = "ub_qt_filter", type = "input", text = "Filter", value = quests.filter },
            w_button("ub_qt_refresh", "Refresh", { auto_width = true }),
        }),
    }
    local third = quests.tab == "Timed" and "Next" or (quests.tab == "KillTask" and "Progress" or "Completed (UTC)")
    rows[#rows + 1] = w_row("ub_qt_head", {
        w_label("ub_qt_h1", "Quest", { bold = true }), w_label("ub_qt_h2", "Solves", { bold = true }),
        w_label("ub_qt_h3", third, { bold = true }),
    })
    for i = first, last do
        local q = list[i]
        local remaining = quest_remaining(q)
        local third_text, color
        if quests.tab == "Timed" then
            if remaining > 0 then third_text = format_duration(remaining) else third_text, color = "ready", "green" end
        elseif quests.tab == "KillTask" then
            third_text = q.solves .. " / " .. q.max
            if q.max > 0 and q.solves >= q.max then color = "green" end
        else
            third_text = q.completed > 0 and format_utc(q.completed) or "-"
        end
        rows[#rows + 1] = w_row("ub_qt_r" .. i, {
            w_label("ub_qt_n" .. i, q.key, { tooltip = q.desc ~= "" and q.desc or q.key }),
            w_label("ub_qt_s" .. i, tostring(q.solves)),
            w_label("ub_qt_x" .. i, third_text, { color = color }),
        })
    end
    if #list == 0 then rows[#rows + 1] = w_text("ub_qt_none", quests.count == 0 and "No quest data yet." or "No quests match.") end
    rows[#rows + 1] = w_text("ub_qt_status", quests.status)
    rows[#rows + 1] = w_pager("ub_qt", page, pages)
    return rows
end

local function quests_events(snapshot)
    for _, e in ipairs(snapshot.events or {}) do
        local id = e.id or ""
        if e.type == "click" then
            if id == "ub_qt_refresh" then quests_refresh(true) end
            for _, t in ipairs(QUEST_TABS) do
                if id == "ub_qt_tab_" .. t then quests.tab, quests.page = t, 1 end
            end
            quests.page = w_pager_event(e, "ub_qt", quests.page)
        elseif e.type == "change" and id == "ub_qt_filter" then
            quests.filter, quests.page = tostring(e.value or ""), 1
        end
    end
end
