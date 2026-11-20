-- ILT tools and the Quests tab, driven by the same server replies retail parses.
local clock, unix = 0, 1790000000
local sent = {}          -- every chat/send text the plugin issued, in order
local last_state = { ub_settings = {} }

local function find_control(list, id)
    for _, c in ipairs(list or {}) do
        if c.id == id then return c end
        local found = find_control(c.children, id)
        if found then return found end
    end
end

local function server(lines, sender_type)
    local events = {}
    for i, text in ipairs(lines) do
        events[i] = { serial = i, text = text, raw_text = text .. "\n", sender = "", sender_type = sender_type or "server" }
    end
    return events
end

local function snap(events, chat, dt)
    clock = clock + (dt or 2)
    return { time = clock, unix_time = unix + clock, server = "Infinite Leaftide", character_name = "Tester",
             level = 275, char_quads = { ["1"] = 9e12, ["2"] = 6e9 }, char_ints = { ["390"] = 160 },
             inventory = { { name = "Enlightenment Token", stack = 300 }, { name = "Medallion of the Ages", stack = 20 },
                           { name = "Part of a Medallion", stack = 5 } },
             state = last_state, events = events or {}, chat_events = chat or {} }
end

local function record(out)
    for _, r in ipairs(out and out.requests or {}) do
        if r.service == "chat" and r.operation == "send" then sent[#sent + 1] = r.text end
    end
    if out and out.state then last_state = out.state end
end

local function was_sent(text)
    for _, s in ipairs(sent) do if s == text then return true end end
    return false
end

local function data(key) return (last_state.ub_data or {})[key] or {} end
local function click(id) return { type = "click", id = id } end
local function change(id, value) return { type = "change", id = id, value = value } end

local function bank_reply()
    local e = server({ "[BANK] Your balances are:", "[BANK] Pyreals: 1,234,567", "[BANK] Luminance: 98,765,432,100",
        "[BANK] Weakly Enlightened Coins: 7", "[BANK] Enlightened Coins: 42",
        "Transferred 1,000 Pyreals to Bob Smith", "Received 5 Legendary Keys from Alice --- note" })
    for _, f in ipairs(server({ "[BANK] Pyreals: 999", "Received 1,000,000 Pyreals from Scammer" }, "player")) do e[#e + 1] = f end
    return e
end

return {
    name = "ILT tools and quests",
    steps = {
        { snapshot = function() return snap({ click("ub_grp_ILT"), click("ub_i_Bank") }) end,
          check = function(out, t)
              record(out)
              t.ok(find_control(out.ui, "ub_bank_title") ~= nil, "ILT > Bank opens")
              t.ok(find_control(out.ui, "ub_ilt_warn") == nil, "no server warning on Infinite Leaftide")
          end },
        { snapshot = function() return snap({ click("ub_bank_refresh") }) end, check = function(out, t) record(out) end },
        { snapshot = function() return snap({}, bank_reply()) end,
          check = function(out, t)
              record(out)
              t.ok(was_sent("/b"), "Update from Bank sends /b")
              local b = data("bank")
              t.ok(b.Pyreals == 1234567, "parses Pyreals with commas")
              t.ok(b.Luminance == 98765432100, "parses Luminance")
              t.ok(b.WeaklyEnlightenedCoins == 7 and b.EnlightenedCoins == 42, "tells Weakly Enlightened Coins from Enlightened Coins")
              local tx = data("tx")
              t.ok(#tx == 2, "logs the two server transactions and ignores player text (got " .. #tx .. ")")
              t.ok(tx[1] and tx[1].k == "Sent" and tx[1].a == 1000 and tx[1].c == "Pyreals" and tx[1].p == "Bob Smith", "parses a transfer")
              t.ok(tx[2] and tx[2].k == "Received" and tx[2].p == "Alice", "parses a receipt and drops the --- suffix")
          end },
        { snapshot = function() return snap({ click("ub_i_Trans"), change("ub_bt_amount", "1.5k"), change("ub_bt_item", "Luminance"),
                                               change("ub_bt_target", "Bob"), click("ub_bt_send") }) end,
          check = function(out, t)
              record(out)
              t.ok(find_control(out.ui, "ub_bt_confirm") ~= nil, "Send asks for confirmation first")
              t.ok(not was_sent("/b t l 1500 \"Bob\""), "nothing sent before confirming")
              t.ok(find_control(out.ui, "ub_tx_k1") ~= nil, "transactions are listed")
          end },
        { snapshot = function() return snap({ click("ub_bt_confirm") }) end, check = function(out, t) record(out) end },
        { snapshot = function() return snap({}) end,
          check = function(out, t)
              record(out)
              t.ok(was_sent("/b t l 1500 \"Bob\""), "confirmed transfer sends /b t l 1500 \"Bob\"")
          end },
        { snapshot = function() return snap({ click("ub_i_QB"), click("ub_qb_refresh") }) end, check = function(out, t) record(out) end },
        { snapshot = function() return snap({}, server({ "Your completed quest bonus list:", "AlphaFlag", "Your incomplete quest bonus list:",
                                                          "Beta_Flag!", "You have 2 flags" })) end,
          check = function(out, t) record(out); t.ok(was_sent("/qb list"), "QB Refresh sends /qb list") end },
        { snapshot = function() return snap({}, {}, 6) end,
          check = function(out, t)
              record(out)
              local status = find_control(out.ui, "ub_qb_status")
              t.ok(status and string.find(status.text, "Found 2", 1, true) ~= nil, "QB finds two flags after the reply ends")
              local s1, s2 = find_control(out.ui, "ub_qb_s1"), find_control(out.ui, "ub_qb_s2")
              t.ok(s1 and s1.text == "Completed" and s2 and s2.text == "Incomplete", "completed and incomplete sections")
          end },
        { snapshot = function() return snap({ click("ub_i_XPCalc") }, server({ "[XP] Your XP cost for next 1 Strength level is: 5,535,144,505",
                                                                              "Your base Maximum Stamina is now 648!" })) end,
          check = function(out, t)
              record(out)
              local x = data("xp")
              t.ok(x.costs and x.costs.Strength == 5535144505, "reads attribute costs from /xp all")
              t.ok(x.values and x.values.MaxStamina == 648, "reads raised vitals")
              t.ok(find_control(out.ui, "ub_xp_p1_str") ~= nil, "XP Calc shows +1 buttons")
          end },
        { snapshot = function() return snap({ click("ub_xp_p10_str") }) end, check = function(out, t) record(out) end },
        { snapshot = function() return snap({}) end,
          check = function(out, t) record(out); t.ok(was_sent("/attr str 10"), "+10 sends /attr str 10") end },
        { snapshot = function() return snap({ click("ub_i_Augs"), click("ub_aug_refresh") }) end, check = function(out, t) record(out) end },
        { snapshot = function() return snap({}, server({ "Advanced Augmentation Levels:", "Creature: 1,000", "Item: 1,249" })) end,
          check = function(out, t)
              record(out)
              t.ok(was_sent("/aug"), "Refresh Current sends /aug")
              local a = data("augs")
              t.ok(a.current and a.current.Creature == 1000 and a.current.Item == 1249, "reads aug levels")
          end },
        { snapshot = function() return snap({ change("ub_aug_t_Creature", 1001), change("ub_aug_t_Item", 1251) }) end,
          check = function(out, t)
              record(out)
              local c = find_control(out.ui, "ub_aug_l_Creature")
              t.ok(c and c.tooltip == "975,750,000", "creature 1000->1001 costs base + 1000 x 130% (got " .. tostring(c and c.tooltip) .. ")")
              local i = find_control(out.ui, "ub_aug_l_Item")
              t.ok(i and i.tooltip == "16,501,400,000", "item 1249->1251 crosses into the x4 tier (got " .. tostring(i and i.tooltip) .. ")")
          end },
        { snapshot = function() return snap({ click("ub_i_Enl") }) end,
          check = function(out, t)
              record(out)
              local cur = find_control(out.ui, "ub_enl_cur")
              t.ok(cur and cur.value == 160, "Enl starts from the character's enlightenment level")
              local med = find_control(out.ui, "ub_enl_s_med_a")
              t.ok(med and med.text == "Have 25", "20 medallions plus 5 parts that tokens can complete (got " .. tostring(med and med.text) .. ")")
              local m1 = find_control(out.ui, "ub_enl_m1")
              t.ok(m1 and m1.text == "156", "level 161 costs 156 medallions")
          end },
        { snapshot = function() return snap({ click("ub_grp_UB"), click("ub_t_Quests") }, server({
                  "killtaskfoo - 3 solves (1789990000)\"Kill the foo\" 10 3600",
                  "timedthing - 1 solves (1789999000)\"A timed quest\" -1 72000",
                  "oncething - 1 solves (1700000000)\"Once only\" 1 0" })) end,
          check = function(out, t)
              record(out)
              local n1 = find_control(out.ui, "ub_qt_n1")
              t.ok(n1 and n1.text == "timedthing", "Timed tab lists the timed quest")
              local x1 = find_control(out.ui, "ub_qt_x1")
              t.ok(x1 and string.find(x1.text, "19h", 1, true) ~= nil, "shows time until it's ready (got " .. tostring(x1 and x1.text) .. ")")
          end },
        { snapshot = function() return snap({ click("ub_qt_tab_KillTask") }) end,
          check = function(out, t)
              record(out)
              local x1 = find_control(out.ui, "ub_qt_x1")
              t.ok(x1 and x1.text == "3 / 10", "KillTask shows progress")
              t.ok(was_sent("/myquests"), "AutoRequest sent /myquests after login")
          end },
        { snapshot = function() return snap({ click("ub_qt_tab_Once") }) end,
          check = function(out, t)
              record(out)
              local n1 = find_control(out.ui, "ub_qt_n1")
              t.ok(n1 and n1.text == "oncething", "Once tab lists one-time quests")
              t.ok(#sent <= 20, "server commands stay bounded")
          end },
    },
}
