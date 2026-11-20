-- Snapshot test harness for the built UtilityBelt main.lua (Lua 5.4).
--
-- Usage: lua5.4 tools/test/run_tests.lua dist/utilitybelt/main.lua tools/test/cases/*.lua
--
-- Loads main.lua into an environment that mimics the AC:Unreal plugin sandbox
-- (no require/io/os/debug/coroutine/load/pcall/metatables/print, no Lua string
-- patterns, 250,000 instructions per callback), then feeds each case's snapshots
-- to the plugin callback and runs the case's checks on the returned output.
-- This approximates the client; behaviour must still be confirmed in game.

local INSTRUCTION_LIMIT = 250000
local host_find = string.find

local function sandbox_string()
    local s = {}
    for k, v in pairs(string) do s[k] = v end
    s.find, s.match, s.gmatch, s.gsub, s.dump = nil, nil, nil, nil, nil
    -- Client helpers (see Docs/Plugins/PublicAPI.md, "Sandbox helper functions").
    s.findplain = function(text, value, start)
        start = math.max(1, start or 1)
        local i = host_find(text, value, start, true)
        return i
    end
    s.contains = function(text, value)
        return host_find(text, value, 1, true) ~= nil
    end
    return s
end

local function unavailable(name)
    return function() error(name .. " is not emulated by the test harness", 2) end
end

local function make_env()
    local env = {
        assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs,
        select = select, tonumber = tonumber, tostring = tostring, type = type,
        rawequal = rawequal, rawget = rawget, rawlen = rawlen, rawset = rawset,
        _VERSION = _VERSION,
        table = table, math = math, utf8 = utf8, string = sandbox_string(),
        workavailable = function() return true end,
        regextest = unavailable("regextest"), regexmatch = unavailable("regexmatch"),
        lootmatch = unavailable("lootmatch"), spellindex = unavailable("spellindex"),
        ucmcommand = unavailable("ucmcommand"), vtcommand = unavailable("vtcommand"),
    }
    env._G = env
    return env
end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep_copy(x) end
    return t
end

local function limited(fn, ...)
    debug.sethook(function() error("instruction limit exceeded (" .. INSTRUCTION_LIMIT .. ")", 2) end, "", INSTRUCTION_LIMIT)
    local results = table.pack(pcall(fn, ...))
    debug.sethook()
    return table.unpack(results, 1, results.n)
end

local main_path = arg[1]
if not main_path or #arg < 2 then
    io.stderr:write("usage: lua run_tests.lua <main.lua> <case.lua> [...]\n")
    os.exit(2)
end

local source = assert(io.open(main_path, "rb")):read("a")
local failures, checks = 0, 0

for i = 2, #arg do
    local case = dofile(arg[i])
    io.write(("case %s (%s)\n"):format(case.name or "?", arg[i]))
    -- Fresh VM per case, as the client starts a fresh VM per plugin start.
    local chunk, err = load(source, "=main.lua", "t", make_env())
    if not chunk then
        failures = failures + 1
        io.write("  FAIL load: " .. tostring(err) .. "\n")
    else
        local ok, callback = limited(chunk)
        if not ok or type(callback) ~= "function" then
            failures = failures + 1
            io.write("  FAIL main.lua must return a function, got " .. tostring(callback) .. "\n")
        else
            local previous
            for n, step in ipairs(case.steps or {}) do
                -- A step's snapshot may be a function of the previous output (e.g. to answer
                -- a service request with its id).
                local snapshot = step.snapshot
                if type(snapshot) == "function" then snapshot = snapshot(previous) end
                local ok2, out = limited(callback, deep_copy(snapshot or {}), deep_copy(step.profile or {}))
                previous = ok2 and out or nil
                local t = {
                    ok = function(cond, msg)
                        checks = checks + 1
                        if not cond then
                            failures = failures + 1
                            io.write(("  FAIL step %d: %s\n"):format(n, msg or "assertion"))
                        end
                    end,
                }
                if not ok2 then
                    failures = failures + 1
                    io.write(("  FAIL step %d raised: %s\n"):format(n, tostring(out)))
                else
                    step.check(out, t)
                end
            end
        end
    end
end

io.write(("%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
