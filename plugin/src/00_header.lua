-- UtilityBelt for AC:Unreal.
-- Built file: tools/build-plugin.ps1 concatenates plugin/src/*.lua in name order
-- into a single main.lua (the client sandbox has no require). Do not edit main.lua.
--
-- Sandbox reminders (enforced by the build lint): no require, io, os, debug,
-- coroutine, load, pcall/xpcall, metatables, print, or string.find/match/gmatch/gsub.
-- Use string.findplain, string.contains, regextest and regexmatch instead.

local UB_VERSION = "@VERSION@"
