-- The plugin reports its version, shows the settings window, and offers the retail import.
local function find_control(list, id)
    for _, c in ipairs(list or {}) do
        if c.id == id then return c end
        local found = find_control(c.children, id)
        if found then return found end
    end
end

return {
    name = "startup",
    steps = {
        {
            snapshot = { time = 1 },
            check = function(out, t)
                t.ok(type(out) == "table", "callback returns a table")
                t.ok(type(out.status) == "string" and string.find(out.status, "UtilityBelt", 1, true) ~= nil, "status names the plugin")
                t.ok(find_control(out.ui, "ub_tabs") ~= nil, "window has tabs")
                local tool = find_control(out.ui, "ub_tool")
                t.ok(tool and tool.type == "select" and #tool.options > 30, "tool picker lists the UB tools")
                t.ok(find_control(out.ui, "ub_retail_import") ~= nil, "offers Import from retail")
                t.ok(out.requests == nil, "no service request before the character is known")
            end,
        },
        {
            snapshot = { time = 2 },
            check = function(out, t)
                t.ok(out and out.status ~= nil, "missing fields do not raise")
            end,
        },
    },
}
