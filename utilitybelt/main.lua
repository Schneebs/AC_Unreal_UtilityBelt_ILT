-- UtilityBelt for AC:Unreal: scaffold.
-- Called at most twice a second with a fresh snapshot; return nil or one intent table.
-- API reference: Unreal/Plugins/ACEClient/Docs/Plugins/ in the AC:Unreal repo.
return function(snapshot, profile)
    return { status = "UtilityBelt scaffold loaded. Health: " .. snapshot.health .. "/" .. snapshot.max_health }
end
