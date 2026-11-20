-- Retail import walks index -> character list -> settings, then saves the settings
-- in state and remembers the match. Results are fed back with the request ids.
local clock = 1
local function request_of(out)
    return out and out.requests and out.requests[1]
end

local function reply(prev, data, ok)
    local r = request_of(prev)
    clock = clock + 1
    return {
        time = clock, unix_time = 1790000000, server = "Infinite Leaftide", character_name = "Schneebly",
        state = {}, health = 100, max_health = 100,
        events = { { type = "result", id = r and r.id, ok = ok ~= false, data = data } },
    }
end

return {
    name = "retail import",
    steps = {
        {
            snapshot = { time = 1, server = "Infinite Leaftide", character_name = "Schneebly", state = {} },
            check = function(out, t)
                local r = request_of(out)
                t.ok(r ~= nil, "first step requests the index")
                t.ok(r and r.service == "profiles" and r.operation == "read", "uses profiles read")
                t.ok(r and r.group == "r_index" and r.name == "index" and r.field == "ub_index", "reads r_index/index field ub_index")
            end,
        },
        {
            snapshot = function(prev)
                return reply(prev, { worlds = { { name = "Coldeve", group = "r_Coldeve" }, { name = "InfiniteLeaftide", group = "r_InfiniteLeaftide" } } })
            end,
            check = function(out, t)
                local r = request_of(out)
                t.ok(r and r.group == "r_InfiniteLeaftide", "server name matches the world ignoring spaces and case")
                t.ok(r and r.name == "_index" and r.field == "ub_characters", "then reads the character list")
            end,
        },
        {
            snapshot = function(prev)
                return reply(prev, { ["Schneebly"] = "Schneebly", ["++CletusClone"] = "__CletusClone-abc123" })
            end,
            check = function(out, t)
                local r = request_of(out)
                t.ok(r and r.name == "Schneebly" and r.field == "ub_settings", "then reads this character's settings")
            end,
        },
        {
            snapshot = function(prev)
                return reply(prev, { Plugin = { Debug = true }, Looter = { Enabled = false }, Huge = string.rep("x", 5000) })
            end,
            check = function(out, t)
                local s = out.state and out.state.ub_settings or {}
                t.ok(out.profile_patch == nil, "no longer patches the profile")
                t.ok(s.Plugin and s.Plugin.Debug == true, "saves ordinary settings in state")
                t.ok(s.Huge == nil, "drops strings over 4 KiB")
                t.ok(out.state and out.state.ub_retail and out.state.ub_retail.file == "Schneebly", "remembers the match in state")
                t.ok(out.status and string.find(out.status, "applied", 1, true) ~= nil, "status reports success")
            end,
        },
    },
}
