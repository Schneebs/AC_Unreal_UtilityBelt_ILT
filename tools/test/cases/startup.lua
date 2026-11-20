-- The scaffold reports its version and the player's health.
return {
    name = "startup status",
    steps = {
        {
            snapshot = { time = 1, health = 1234, max_health = 2000 },
            check = function(out, t)
                t.ok(type(out) == "table", "callback returns a table")
                t.ok(type(out.status) == "string", "status is a string")
                t.ok(out.status and string.find(out.status, "UtilityBelt", 1, true) ~= nil, "status names the plugin")
                t.ok(out.status and string.find(out.status, "1,234/2,000", 1, true) ~= nil, "health is formatted with separators")
            end,
        },
        {
            snapshot = { time = 2 },
            check = function(out, t)
                t.ok(out and out.status ~= nil, "missing vitals do not raise")
            end,
        },
    },
}
