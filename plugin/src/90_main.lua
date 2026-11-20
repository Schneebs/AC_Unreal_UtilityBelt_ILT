-- Entry point: the client calls this at most twice per second (companion mode)
-- with a fresh snapshot and the active profile. Return nil or one output table.
return function(snapshot, profile)
    local wants_import = false
    for _, e in ipairs(snapshot.events or {}) do
        if e.type == "click" and e.id == "ub_retail_import" then wants_import = true end
    end

    local out = retail_tick(snapshot, wants_import)

    local health = snapshot.health or 0
    local max_health = snapshot.max_health or 0
    out.status = "UtilityBelt " .. UB_VERSION .. " · " .. retail.status
    out.ui = {
        { id = "ub_version", type = "text", text = "UtilityBelt " .. UB_VERSION .. " for AC:Unreal" },
        { id = "ub_health", type = "text", text = "Health: " .. format_number(health) .. "/" .. format_number(max_health) },
        { id = "ub_retail_status", type = "text", text = retail.status, wrap = true },
        { id = "ub_retail_import", type = "button", text = "Import from retail",
          tooltip = "Apply this character's retail UtilityBelt settings (run UB Manager's Import first)",
          enabled = retail.pending == nil },
    }
    return out
end
