-- Entry point: the client calls this at most twice per second (companion mode)
-- with a fresh snapshot and the active profile. Return nil or one output table.

-- Every service request goes through one outbox: the client allows four requests
-- per callback and rejects a whole batch sent within half a second of the last one.
local SERVICE_INTERVAL = 0.6
local outbox = { items = {}, last = -1000 }

local function outbox_flush(now)
    if #outbox.items == 0 or now - outbox.last < SERVICE_INTERVAL then return nil end
    local batch = {}
    while #outbox.items > 0 and #batch < 4 do batch[#batch + 1] = table.remove(outbox.items, 1) end
    outbox.last = now
    return batch
end

local last_character

return function(snapshot, profile)
    local now = snapshot.time or 0
    local state = snapshot.state or {}
    game.now, game.unix, game.character = now, snapshot.unix_time or game.unix, snapshot.character_name

    -- A different character in the same session starts over.
    if snapshot.character_name ~= last_character then
        last_character = snapshot.character_name
        settings.loaded, settings.values, settings.charstate, settings.data, settings.dirty = false, {}, {}, {}, false
        retail.phase, retail.pending = "start", nil
        quests.flags, quests.count, quests.auto_done, quests.login_time = {}, 0, false, nil
        qb.flags, qb.names = {}, {}
    end
    settings_load(state)

    -- Player input: commands, then each page's controls.
    local wants_import, requests = false, {}
    for _, e in ipairs(snapshot.events or {}) do
        if e.type == "click" and e.id == "ub_retail_import" then wants_import = true end
        if e.type == "command" then ub_command(e.text, requests) end
    end
    ui_events(snapshot)
    w_setting_events(snapshot)
    bank_events(snapshot)
    xp_events(snapshot)
    augs_events(snapshot)
    enl_events(snapshot)
    quests_events(snapshot)
    window_events(snapshot)

    -- Server replies.
    local lines = game_server_lines(snapshot)
    bank_chat(lines)
    xp_chat(lines)
    augs_chat(lines)
    quests_chat(lines, snapshot)
    xp_auto_tick(snapshot)

    local out = retail_tick(snapshot, wants_import)
    for _, r in ipairs(out.requests or {}) do requests[#requests + 1] = r end
    local send = game_send_tick(now)
    if send then requests[#requests + 1] = send end
    for _, r in ipairs(requests) do outbox.items[#outbox.items + 1] = r end
    for _, r in ipairs(chat_tick(snapshot, 4 - #outbox.items)) do outbox.items[#outbox.items + 1] = r end
    out.requests = outbox_flush(now)

    local saved = settings_state(out.state or state)
    if saved then out.state = saved end

    out.status = "UtilityBelt " .. UB_VERSION .. " · " .. retail.status
    out.ui = window_build(snapshot)
    return out
end
