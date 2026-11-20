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
                t.ok(find_control(out.ui, "ub_grp_UB") ~= nil and find_control(out.ui, "ub_grp_ILT") ~= nil, "UtilityBelt and ILT tab groups")
                t.ok(find_control(out.ui, "ub_t_Main") ~= nil and find_control(out.ui, "ub_t_Quests") ~= nil, "retail tab bar")
                t.ok(find_control(out.ui, "ub_opt_AutoVendor.Enabled") ~= nil, "Main tab shows retail switches")
                t.ok(out.requests == nil, "no service request before the character is known")
            end,
        },
        {
            snapshot = { time = 2, events = { { type = "click", id = "ub_t_Settings" } } },
            check = function(out, t)
                t.ok(out and out.status ~= nil, "missing fields do not raise")
                local tool = find_control(out.ui, "ub_tool")
                t.ok(tool and tool.type == "select" and #tool.options > 30, "Settings tab lists the UB tools")
            end,
        },
        {
            snapshot = { time = 3, events = { { type = "click", id = "ub_t_Import" } } },
            check = function(out, t)
                t.ok(find_control(out.ui, "ub_retail_import") ~= nil, "Import tab offers Import from retail")
            end,
        },
    },
}
