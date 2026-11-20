-- The plugin reports its version, shows the player's health, and offers the retail import.
local function find_control(out, id)
    for _, c in ipairs(out and out.ui or {}) do
        if c.id == id then return c end
    end
end

return {
    name = "startup status",
    steps = {
        {
            snapshot = { time = 1, health = 1234, max_health = 2000 },
            check = function(out, t)
                t.ok(type(out) == "table", "callback returns a table")
                t.ok(type(out.status) == "string" and string.find(out.status, "UtilityBelt", 1, true) ~= nil, "status names the plugin")
                local health = find_control(out, "ub_health")
                t.ok(health and string.find(health.text, "1,234/2,000", 1, true) ~= nil, "health is shown with separators")
                local button = find_control(out, "ub_retail_import")
                t.ok(button and button.type == "button", "offers Import from retail")
                t.ok(out.requests == nil, "no service request before the character is known")
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
