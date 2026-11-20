-- /ub commands. AC:Unreal delivers "/plugin utilitybelt <text>" (or /acueplugin) as a
-- {type="command", text=...} event; text is parsed like retail's "/ub <text>".
-- Output goes to local chat through the notice service (one line, at most 500
-- characters, four requests per callback, half a second apart), so lines are queued.

local NOTICE_MAX = 480          -- keep under the service's 500-character limit
local NOTICE_INTERVAL = 0.5

local chat = {
    queue = {},       -- lines waiting to be shown
    pending = {},     -- request id -> line, until its result arrives
    next_id = 0,
    last_sent = -1000,
}

local function chat_line(text)
    text = tostring(text)
    while #text > NOTICE_MAX do
        chat.queue[#chat.queue + 1] = string.sub(text, 1, NOTICE_MAX)
        text = string.sub(text, NOTICE_MAX + 1)
    end
    chat.queue[#chat.queue + 1] = text
end

-- Packs many short items into as few notice lines as possible.
local function chat_lines_packed(items, separator)
    local line = ""
    for _, item in ipairs(items) do
        if line ~= "" and #line + #separator + #item > NOTICE_MAX then
            chat_line(line)
            line = item
        else
            line = line == "" and item or (line .. separator .. item)
        end
    end
    if line ~= "" then chat_line(line) end
end

-- Handles notice results (requeues rate-limited lines) and returns new requests.
local function chat_tick(snapshot, budget)
    for _, e in ipairs(snapshot.events or {}) do
        if e.type == "result" and e.id and chat.pending[e.id] then
            if not e.ok then
                local err = string.lower(tostring(e.error or ""))
                if string.contains(err, "rate") or string.contains(err, "limit") or string.contains(err, "busy") then
                    table.insert(chat.queue, 1, chat.pending[e.id])
                end
            end
            chat.pending[e.id] = nil
        end
    end
    local now = snapshot.time or 0
    local requests = {}
    if #chat.queue == 0 or budget <= 0 or now - chat.last_sent < NOTICE_INTERVAL then return requests end
    while #chat.queue > 0 and #requests < budget do
        local line = table.remove(chat.queue, 1)
        chat.next_id = chat.next_id + 1
        local id = "ub_chat_" .. chat.next_id
        chat.pending[id] = line
        requests[#requests + 1] = { id = id, service = "notice", operation = "show", text = line }
    end
    chat.last_sent = now
    return requests
end

-- Splits on spaces, keeping the remainder after `count` words in the last item.
local function split_words(text, count)
    local words, i, n = {}, 1, #text
    while i <= n do
        while i <= n and string.sub(text, i, i) == " " do i = i + 1 end
        if i > n then break end
        if count and #words == count - 1 then
            words[#words + 1] = trim(string.sub(text, i))
            break
        end
        local j = i
        while j <= n and string.sub(text, j, j) ~= " " do j = j + 1 end
        words[#words + 1] = string.sub(text, i, j - 1)
        i = j
    end
    return words
end

local function opt_list(filter)
    local f = filter and string.lower(filter) or nil
    local items = {}
    for _, entry in ipairs(settings.list) do
        if not f or string.contains(string.lower(entry.name), f) then
            items[#items + 1] = entry.name .. " (" .. (entry.store == "state" and "State" or "Profile") .. ") = " .. settings_display(entry)
        end
    end
    chat_line((f and ("Settings matching \"" .. filter .. "\"") or "All Settings") .. ": " .. #items)
    chat_lines_packed(items, " | ")
end

local function opt_invalid(name)
    chat_line("Invalid option: " .. name)
    -- Suggest close names (retail lists every state option, which is too long for chat).
    local l, near = string.lower(name), {}
    for _, entry in ipairs(settings.list) do
        local n = string.lower(entry.name)
        if string.contains(n, l) or string.contains(l, string.lower(entry.short)) then near[#near + 1] = entry.name end
        if #near >= 12 then break end
    end
    if #near > 0 then chat_lines_packed(near, ", ") end
end

-- /ub opt {list | get <option> | set <option> <newValue> | toggle <option>}
local function cmd_opt(args)
    local words = split_words(args, 3)
    local verb = string.lower(words[1] or "")
    if verb == "list" then opt_list(words[2]); return end
    if verb ~= "get" and verb ~= "set" and verb ~= "toggle" then
        -- Retail also accepts "/ub opt <option> [value]".
        words = split_words(args, 2)
        verb = words[2] and "set" or "get"
        table.insert(words, 1, verb)
    end
    local name = words[2]
    if not name or name == "" then
        chat_line("Usage: /ub opt {list | get <option> | set <option> <newValue> | toggle <option>}")
        return
    end
    local entry = settings.by_name[string.lower(name)]
    if not entry then opt_invalid(name); return end
    if verb == "toggle" then
        if entry.type ~= "bool" then chat_line("Unable to toggle setting " .. entry.name .. ": not a true/false setting"); return end
        settings_put(entry, not settings_get(entry))
        chat_line(settings_full_display(entry))
        return
    end
    local value_text = words[3]
    if verb == "get" or not value_text or value_text == "" then
        chat_line(settings_full_display(entry))
        return
    end
    if entry.type == "list" then
        local parts = split_words(value_text, 2)
        local op, list = string.lower(parts[1] or ""), settings_get(entry)
        if type(list) ~= "table" then list = {} end
        if op == "add" or op == "remove" then
            if not parts[2] or parts[2] == "" then chat_line("Missing items to " .. op); return end
            for _, item in ipairs(split_commas(parts[2])) do
                local at
                for i, v in ipairs(list) do if v == item then at = i end end
                if op == "add" and not at then list[#list + 1] = item end
                if op == "remove" and at then table.remove(list, at) end
            end
        elseif op == "clear" then
            list = {}
        else
            chat_line("Unknown verb: " .. tostring(parts[1]) .. " (use add, remove or clear)")
            return
        end
        settings_put(entry, list)
        chat_line(settings_full_display(entry))
        return
    end
    local value, err = settings_parse(entry, value_text)
    if value == nil then chat_line("Unable to set " .. entry.name .. ": " .. err); return end
    settings_put(entry, value)
    chat_line(settings_full_display(entry))
end

local ub_ui = { tool = nil, filter = "", page = 1, visible = nil }   -- shared with the window module

local function cmd_help()
    chat_line("UtilityBelt " .. UB_VERSION .. " for AC:Unreal. Type commands as /plugin utilitybelt <command> (retail: /ub <command>).")
    chat_line("Commands: opt {list [filter] | get <option> | set <option> <value> | toggle <option>}, settings [tool], help. Other UB tools are not ported yet.")
end

local function ub_command(text, requests)
    text = trim(text or "")
    -- Accept a leading "/ub" or "ub" so pasted retail commands work.
    local l = string.lower(text)
    if string.sub(l, 1, 4) == "/ub " then text = trim(string.sub(text, 5))
    elseif string.sub(l, 1, 3) == "ub " then text = trim(string.sub(text, 4))
    elseif l == "/ub" or l == "ub" then text = "" end
    local words = split_words(text, 2)
    local verb = string.lower(words[1] or "")
    local rest = words[2] or ""
    if verb == "opt" then
        cmd_opt(rest)
    elseif verb == "settings" or verb == "" then
        if rest ~= "" then
            for _, tool in ipairs(settings.tools) do
                if string.lower(tool.name) == string.lower(rest) then
                    ub_ui.tool, ub_ui.page, ub_ui.filter, ub_ui.goto_settings = tool.name, 1, "", true
                end
            end
        end
        requests[#requests + 1] = { id = "ub_window", service = "window", operation = "show" }
    elseif verb == "help" then
        cmd_help()
    else
        chat_line("Unknown command \"" .. words[1] .. "\". Not ported yet, or try /plugin utilitybelt help")
    end
end
