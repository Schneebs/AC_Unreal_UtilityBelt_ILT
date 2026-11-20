-- Entry point: the client calls this at most twice per second (companion mode)
-- with a fresh snapshot and the active profile. Return nil or one output table.
return function(snapshot, profile)
    local health = snapshot.health or 0
    local max_health = snapshot.max_health or 0
    return {
        status = "UtilityBelt " .. UB_VERSION .. " loaded. Health: "
            .. format_number(health) .. "/" .. format_number(max_health)
    }
end
