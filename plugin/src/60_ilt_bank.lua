-- ILT tools: Bank (balances from "/b"), Trans (bank transaction log and transfers
-- with "/b t"), and QB (quest bonus flags from "/qb list"). Ported from UB ILT's
-- BankBalances.cs and QuestBonus.cs: same commands and the same reply parsing.

local BANK_FIELDS = {   -- order matters: "Weakly Enlightened Coins:" before "Enlightened Coins:"
    { key = "WeaklyEnlightenedCoins", label = "Weakly Enlightened Coins", short = "W Coins", code = "we" },
    { key = "EnlightenedCoins", label = "Enlightened Coins", short = "Coins", code = "e" },
    { key = "MythicalKeys", label = "Mythical Keys", short = "MK", code = "mk" },
    { key = "LegendaryKeys", label = "Legendary Keys", short = "LK", code = "k" },
    { key = "Luminance", label = "Luminance", short = "L", code = "l" },
    { key = "Pyreals", label = "Pyreals", short = "P", code = "p" },
}
local BANK_DISPLAY = { 6, 5, 4, 3, 2, 1 }     -- Pyreals first, as retail shows them
local TX_MAX = 200                            -- saved transactions (state is limited to 64 KiB)
local TX_PAGE = 14
local QB_PAGE = 20

local bank = {
    getting = false, got_first = false, heartbeat = 0, status = "",
    tx_page = 1, tx_filter = "", tx_type = "All", tx_currency = "All", tx_clear_armed = false,
    amount = "", item = "Pyreals", target = "", confirm = false, transfer_status = "Ready to transfer",
}

local qb = { getting = false, got_first = false, heartbeat = 0, section = "completed",
             flags = {}, names = {}, filter = "", page = 1, status = "Press Refresh to read /qb list" }

local function bank_refresh()
    if bank.getting then return end
    bank.getting, bank.got_first, bank.heartbeat = true, false, game.now
    bank.status = "Please wait..."
    game_send("/b")
end

local function bank_parse_line(line)
    for _, f in ipairs(BANK_FIELDS) do
        local i = string.findplain(line, f.label .. ":")
        if i then
            local v = leading_number(string.sub(line, i + #f.label + 1))
            if v then
                local data = data_get("bank")
                data[f.key] = v
                data.updated = game.unix
                data_changed()
            end
            return true
        end
    end
    return false
end

-- "Transferred 1,000 Pyreals to Name" / "Received 5 Legendary Keys from Name" (--- suffix allowed).
local function bank_parse_transaction(line)
    local kind, rest, sep
    if starts_with(line, "Transferred ") then kind, rest, sep = "Sent", string.sub(line, 13), " to "
    elseif starts_with(line, "Received ") then kind, rest, sep = "Received", string.sub(line, 10), " from "
    else return false end
    local dash = string.findplain(rest, "---")
    if dash then rest = trim(string.sub(rest, 1, dash - 1)) end
    local sp = string.findplain(rest, " ")
    if not sp then return false end
    local amount = leading_number(string.sub(rest, 1, sp - 1))
    local at = string.findplain(rest, sep, sp)
    if not amount or not at then return false end
    local currency = trim(string.sub(rest, sp + 1, at - 1))
    local player = trim(string.sub(rest, at + #sep))
    if currency == "" or player == "" or string.contains(currency, "'") then return false end
    local tx = data_get("tx")
    tx[#tx + 1] = { t = game.unix, k = kind, a = amount, c = currency, p = player }
    while #tx > TX_MAX do table.remove(tx, 1) end
    data_changed()
    return true
end

local function qb_is_flag_line(line)
    if line == "" or string.contains(line, " ") then return false end
    if string.contains(line, "command") or string.contains(line, "enabled") or string.contains(line, "list") then return false end
    if string.lower(line) == "questbonusflag" then return false end
    local all_dash = true
    for i = 1, #line do
        local c = string.sub(line, i, i)
        if c ~= "-" then all_dash = false end
        local ok = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
            or c == "_" or c == "-" or c == "!" or c == "@" or c == "(" or c == ")" or c == "?"
        if not ok then return false end
    end
    return not all_dash
end

local function qb_refresh()
    if qb.getting then return end
    qb.getting, qb.got_first, qb.heartbeat, qb.section = true, false, game.now, "completed"
    qb.flags, qb.names = {}, {}
    qb.status = "Please wait..."
    game_send("/qb list")
end

local function qb_finish(status)
    qb.getting = false
    table.sort(qb.names, function(a, b) return string.lower(a) < string.lower(b) end)
    qb.status = status
end

local function bank_chat(lines)
    for _, line in ipairs(lines) do
        if string.contains(line, "[BANK] Your balances are:") then
            bank.got_first, bank.heartbeat = true, game.now
        elseif string.contains(line, "[BANK]") and bank_parse_line(line) then
            bank.heartbeat = game.now
        elseif bank_parse_transaction(line) then
            -- logged
        end
        if qb.getting then
            if line == "Quest bonus list is empty." or string.contains(line, "\"qb\" is not currently enabled") then
                qb_finish(line)
            elseif line == "Your completed quest bonus list:" then
                qb.section, qb.got_first, qb.heartbeat = "completed", true, game.now
            elseif line == "Your incomplete quest bonus list:" then
                qb.section, qb.got_first, qb.heartbeat = "incomplete", true, game.now
            elseif qb_is_flag_line(line) then
                if not qb.flags[line] then qb.names[#qb.names + 1] = line end
                qb.flags[line] = qb.section
                qb.got_first, qb.heartbeat = true, game.now
            end
        end
    end
    if bank.getting then
        if bank.got_first and game.now - bank.heartbeat > 2 then
            bank.getting, bank.status = false, ""
        elseif not bank.got_first and game.now - bank.heartbeat > 15 then
            bank.getting, bank.status = false, "Timeout (15s) getting bank data"
        end
    end
    if qb.getting then
        if qb.got_first and game.now - qb.heartbeat > 5 then
            qb_finish("Found " .. #qb.names .. " quest bonus flags")
        elseif not qb.got_first and game.now - qb.heartbeat > 15 then
            qb_finish("Timeout (15s) getting quest bonuses")
        end
    end
end

local function bank_ingame_text()
    local d = data_get("bank")
    local parts = { "Bank Balances - " .. tostring(game.character or "") }
    for _, i in ipairs(BANK_DISPLAY) do
        local f = BANK_FIELDS[i]
        parts[#parts + 1] = f.short .. ": " .. format_number(d[f.key] or 0)
    end
    parts[#parts + 1] = "Updated: " .. (d.updated and format_utc(d.updated) or "Never")
    return table.concat(parts, " | ")
end

local function bank_page()
    local d = data_get("bank")
    local rows = { w_label("ub_bank_title", "Bank Balances", { bold = true }) }
    for _, i in ipairs(BANK_DISPLAY) do
        local f = BANK_FIELDS[i]
        rows[#rows + 1] = w_row("ub_bank_r_" .. f.key, {
            w_label("ub_bank_l_" .. f.key, f.label),
            w_label("ub_bank_v_" .. f.key, format_number(d[f.key] or 0), { align = "right" }),
        })
    end
    rows[#rows + 1] = w_label("ub_bank_updated", "Last Updated: " .. format_ago(d.updated))
    rows[#rows + 1] = w_row("ub_bank_btns", {
        w_button("ub_bank_refresh", bank.getting and "Please Wait..." or "Update from Bank", { enabled = not bank.getting }),
    }, { compact = true })
    if bank.status ~= "" then rows[#rows + 1] = w_text("ub_bank_status", bank.status) end
    rows[#rows + 1] = { id = "ub_bank_copy", type = "input", text = "Share", value = bank_ingame_text(),
                        tooltip = "Select and copy (AC:Unreal plugins can't write to the clipboard)" }
    return rows
end

local TX_TYPES = { "All", "Sent", "Received" }

local function tx_currencies()
    local seen, out = {}, { "All" }
    for _, t in ipairs(data_get("tx")) do
        if not seen[t.c] then seen[t.c] = true; out[#out + 1] = t.c end
    end
    return out
end

local function tx_filtered()
    local out, f = {}, string.lower(trim(bank.tx_filter))
    local tx = data_get("tx")
    for i = #tx, 1, -1 do
        local t = tx[i]
        if (bank.tx_type == "All" or t.k == bank.tx_type) and (bank.tx_currency == "All" or t.c == bank.tx_currency)
            and (f == "" or string.contains(string.lower(t.p), f) or string.contains(string.lower(t.c), f)) then
            out[#out + 1] = t
        end
    end
    return out
end

local function bank_item_names()
    local out = {}
    for _, i in ipairs(BANK_DISPLAY) do out[#out + 1] = BANK_FIELDS[i].label end
    return out
end

local function trans_page()
    local list = tx_filtered()
    local first, last, pages, page = w_page_bounds(#list, bank.tx_page, TX_PAGE)
    bank.tx_page = page
    local rows = {
        w_label("ub_tx_title", "Bank Transaction Log", { bold = true }),
        w_row("ub_tx_filters", {
            { id = "ub_tx_filter", type = "input", text = "Search", value = bank.tx_filter, tooltip = "Player or currency" },
            { id = "ub_tx_type", type = "select", text = "Type", value = bank.tx_type, options = TX_TYPES },
            { id = "ub_tx_currency", type = "select", text = "Currency", value = bank.tx_currency, options = tx_currencies() },
        }),
    }
    rows[#rows + 1] = w_row("ub_tx_head", {
        w_label("ub_tx_h1", "Date (UTC)", { bold = true }), w_label("ub_tx_h2", "Type", { bold = true }),
        w_label("ub_tx_h3", "Amount", { bold = true }), w_label("ub_tx_h4", "Currency", { bold = true }),
        w_label("ub_tx_h5", "Player", { bold = true }),
    })
    for i = first, last do
        local t = list[i]
        rows[#rows + 1] = w_row("ub_tx_" .. i, {
            w_label("ub_tx_d" .. i, format_utc(t.t)), w_label("ub_tx_k" .. i, t.k, { color = t.k == "Sent" and "red" or "green" }),
            w_label("ub_tx_a" .. i, format_number(t.a)), w_label("ub_tx_c" .. i, t.c), w_label("ub_tx_p" .. i, t.p),
        })
    end
    if #list == 0 then rows[#rows + 1] = w_text("ub_tx_none", "No transactions. They are logged automatically from bank messages.") end
    rows[#rows + 1] = w_row("ub_tx_tools", {
        w_button("ub_tx_prev", "< Prev", { enabled = page > 1 }),
        w_label("ub_tx_count", #list .. " shown · page " .. page .. "/" .. pages),
        w_button("ub_tx_next", "Next >", { enabled = page < pages }),
        w_button("ub_tx_clear", bank.tx_clear_armed and "Confirm clear" or "Clear Log", { color = bank.tx_clear_armed and "red" or nil }),
    }, { compact = true })

    local transfer = {
        w_row("ub_bt_inputs", {
            { id = "ub_bt_amount", type = "input", text = "Amount", value = bank.amount, tooltip = "Supports 1.5k, 2m, 3b, 4t" },
            { id = "ub_bt_item", type = "select", text = "Currency", value = bank.item, options = bank_item_names() },
            { id = "ub_bt_target", type = "input", text = "To", value = bank.target, tooltip = "Character name" },
        }),
    }
    if bank.confirm then
        local amount = parse_amount(bank.amount) or 0
        transfer[#transfer + 1] = w_row("ub_bt_confirm_row", {
            w_button("ub_bt_confirm", "Confirm: send " .. format_number(amount) .. " " .. bank.item .. " to " .. bank.target, { color = "yellow" }),
            w_button("ub_bt_cancel", "Cancel", { auto_width = true }),
        })
    else
        transfer[#transfer + 1] = w_button("ub_bt_send", "Send")
    end
    transfer[#transfer + 1] = w_text("ub_bt_status", bank.transfer_status)
    rows[#rows + 1] = w_section("ub_bt", "Bank Transfer", transfer)
    return rows
end

local function qb_page()
    local f = string.lower(trim(qb.filter))
    local list = {}
    for _, name in ipairs(qb.names) do
        if f == "" or string.contains(string.lower(name), f) then list[#list + 1] = name end
    end
    local first, last, pages, page = w_page_bounds(#list, qb.page, QB_PAGE)
    qb.page = page
    local rows = {
        w_row("ub_qb_top", {
            { id = "ub_qb_filter", type = "input", text = "Filter", value = qb.filter },
            w_button("ub_qb_refresh", qb.getting and "Please Wait..." or "Refresh", { enabled = not qb.getting, auto_width = true }),
        }),
        w_row("ub_qb_head", { w_label("ub_qb_h1", "Quest Bonus Flag", { bold = true }), w_label("ub_qb_h2", "Status", { bold = true }) }),
    }
    for i = first, last do
        local name = list[i]
        local done = qb.flags[name] == "completed"
        rows[#rows + 1] = w_row("ub_qb_" .. i, {
            w_label("ub_qb_n" .. i, name),
            w_label("ub_qb_s" .. i, done and "Completed" or "Incomplete", { color = done and "green" or "yellow" }),
        })
    end
    rows[#rows + 1] = w_text("ub_qb_status", qb.status .. (#qb.names > 0 and (" · " .. #list .. " shown") or ""))
    rows[#rows + 1] = w_pager("ub_qb", page, pages)
    return rows
end

local function bank_events(snapshot)
    for _, e in ipairs(snapshot.events or {}) do
        local id = e.id
        if e.type == "click" then
            if id == "ub_bank_refresh" then bank_refresh()
            elseif id == "ub_qb_refresh" then qb_refresh()
            elseif id == "ub_tx_prev" then bank.tx_page = math.max(1, bank.tx_page - 1)
            elseif id == "ub_tx_next" then bank.tx_page = bank.tx_page + 1
            elseif id == "ub_tx_clear" then
                if bank.tx_clear_armed then
                    settings.data.tx = {}
                    data_changed()
                    bank.tx_clear_armed = false
                else
                    bank.tx_clear_armed = true
                end
            elseif id == "ub_bt_send" then
                local amount = parse_amount(bank.amount)
                local target = trim(bank.target)
                if not amount then bank.transfer_status = "Error: enter a valid positive amount (supports k/m/b/t)"
                elseif target == "" then bank.transfer_status = "Error: enter a target character name"
                elseif string.contains(target, "\"") then bank.transfer_status = "Error: names can't contain quotes"
                else bank.confirm = true end
            elseif id == "ub_bt_cancel" then
                bank.confirm = false
            elseif id == "ub_bt_confirm" then
                local amount, target = parse_amount(bank.amount), trim(bank.target)
                local code
                for _, f in ipairs(BANK_FIELDS) do if f.label == bank.item then code = f.code end end
                if amount and code and target ~= "" then
                    game_send(string.format("/b t %s %s \"%s\"", code, tostring(amount), target))
                    bank.transfer_status = "Sent " .. format_number(amount) .. " " .. bank.item .. " to " .. target
                    bank.amount = ""
                end
                bank.confirm = false
            else
                qb.page = w_pager_event(e, "ub_qb", qb.page)
            end
            if id ~= "ub_tx_clear" then bank.tx_clear_armed = false end
        elseif e.type == "change" then
            if id == "ub_tx_filter" then bank.tx_filter, bank.tx_page = tostring(e.value or ""), 1
            elseif id == "ub_tx_type" then bank.tx_type, bank.tx_page = tostring(e.value), 1
            elseif id == "ub_tx_currency" then bank.tx_currency, bank.tx_page = tostring(e.value), 1
            elseif id == "ub_bt_amount" then bank.amount, bank.confirm = tostring(e.value or ""), false
            elseif id == "ub_bt_item" then bank.item, bank.confirm = tostring(e.value), false
            elseif id == "ub_bt_target" then bank.target, bank.confirm = tostring(e.value or ""), false
            elseif id == "ub_qb_filter" then qb.filter, qb.page = tostring(e.value or ""), 1 end
        end
    end
end
