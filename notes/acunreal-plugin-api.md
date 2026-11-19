# AC:Unreal client plugin API: working notes

Source of truth: `C:\Scripting\AC_Unreal\Unreal\Plugins\ACEClient\`
- Docs: `Docs/Plugins/README.md`, `PublicAPI.md` (API 2), `Companions.md`, `LootMatching.md`, `VirindiCompatibility.md`, `Waypoint.md`, `Examples/`
- Machine-readable catalog: `ClientMods/api.json` (57 actions, permissions, snapshot fields, limits)
- Host code: `Source/ACEClient/Private/Mods/ACEPluginSubsystem.cpp` (discovery ~L430, permission/intent dispatch ~L1886), `ACEPluginVM.cpp` (Lua sandbox), `ACEPluginPublicAPI.cpp`, `ACEPluginPanel.cpp`
- Snapshot of client v161, 2026-11-19. Re-check `api.json` after upstream merges.

## Two meanings of "plugin"
- **Unreal Engine plugins** (`Unreal/Plugins/ACEClient`, `ACEWorldBake`): how the C++ client is organized. `ACEClient` is essentially the whole client. Not what we build.
- **Client plugins** (Plugin Manager, `/acueplugins`): Lua add-ons. **This is the UB target.** Not a Decal loader: no DLLs, no .NET, no VVS. The same Lua runs on Windows, Linux, PC VR, Quest and Android.

Thwargle's policy (Discord, 2026-11-19): plugins live in their own repos, installed like Decal or WoW add-ons. The client repo is base client plus the plugin API. If the API is missing something, ask him or send an API PR.

## Packaging
Folder `<id>/` containing:
- `plugin.json`: `api` (1|2), `mode` (`automation` default | `companion` | `local`), `id`, `name`, `short_name` (4-character bar label), `version`, `description`, `permissions[]`, `settings[]` (bool/number/choice/text), optional `presentation{title,icon,controls,settings,status,scroll,window{opacity,pinned}}`, `update_interval` (companion 0.5 to 60 s), `snapshot_fields[]` (API 2 companion only), `chat_history`, `chat_subscriptions[]`, `policy` (`ucm`|`itemtools`, automation only).
- `main.lua`: `return function(snapshot, profile) ... return output_or_nil end`. Locals outside the function persist until Stop.
- `default.json`: the default profile object.
- Optional `images/*.png` (icons and UI art), `sounds/*.wav` (PCM16, at most 10 s and 1 MiB).

Install locations: bundled `ClientMods/<id>/`, user `Saved/ClientPlugins/Installed/<id>/`. Duplicate IDs are rejected, and a user plugin can't override a bundled ID. Our dev setup junctions `utilitybelt/` into Installed.
Saved data: `Saved/ClientPlugins/settings.json` (preferences), `Profiles/<id>/<name>.json` and `Profiles/<id>/Library/<group>/` (profiles service), `State/<id>/<server-hash>_<char-guid>.json` (state, 64 KiB, written at most every 5 s).

## Modes: the most important constraint
| Mode | Starts | Can act in game? | Runs with UCM? |
|---|---|---|---|
| `automation` | Explicit Start | Yes, via intents with permissions | **No. Only one automation driver runs at a time. Starting one stops the previous (UCM included).** Item Tools pauses UCM temporarily. |
| `companion` | Auto when enabled and in world | No cast/attack/move. Can do: `identify` (one appraisal/s), `say` (chat send), `select`/`select_item`, `waypoint`, `command` bridges, `messages`, sounds, notices | Yes, alongside |
| `local` | At enable, even at login screen | Native C++ local services (cosmetics) | n/a |

Consequence for UB: UB's passive and UI tools map to companions. UB's acting tools (looter, autovendor, autotinker, jumper, equipment manager...) need automation mode, and running one stops UCM. They can't run alongside UCM the way UB runs alongside VTank. Options: (a) companion that drives UCM/Item Tools through the `commands` bridge (`/acueucm ...`, `/acueitems ...`); (b) automation that wraps UCM with `"policy":"ucm"` (`builtinpolicy(s,p)`) and adds its own actions; (c) ask Thwargle for a "helper action" lane for companions.

## Callback
- `snapshot` (copy; mutating it does nothing) and `profile`. Return nil, or a table that can combine: one game `action` intent + `status`, `state`, `ui`, `presentation`, `chat_filters`, `chat_subscriptions`, `markers`, `world_plates`, `terrain_overlay`, `messages`, `requests`, `profile_patch`, `runtime_route`.
- Timing: companion at most 2 Hz (round robin, one per frame, `update_interval` up to 60 s; input events wake early). Automation wakes on UCM's completion, vitals and target-death signals.
- Omitted output field = keep previous; explicit `{}` = clear.
- Errors: a Lua error or quota breach stops only this plugin. `snapshot.error` = last native action or save error.

## Sandbox (ACEPluginVM.cpp)
- Lua 5.4.9, one VM per plugin, 32 MiB heap (snapshots count), 250k instructions per callback, 20 ms regex per callback.
- Available: base, `table`, `math`, `utf8`, bounded `string`. **Not available:** `require`, `io`, `os`, `debug`, coroutines, `load`, `pcall`/`xpcall`, metatables, `collectgarbage`, `print`, and `string.find/match/gmatch/gsub/dump`.
- So: a single file (no modules), no error recovery, no OOP via metatables (use closures and plain tables), no Lua patterns.
- Helpers: `string.contains`, `string.findplain`, `regextest`, `regexmatch` (bounded .NET/VT regex subset, named captures), `lootmatch(rule,item,snapshot,scan)`, `spellindex(...)`, `ucmcommand(text)` (alias `vtcommand`: compiles a VT/UCM command to a record, doesn't run it), `workavailable()` (split long jobs across callbacks).

## Permissions (declare only what's used; enabling grants them)
Game: `cast`, `combat`, `navigation`, `inventory`, `loot`, `say`, `fellowship`, `confirm`.
Observe/UI: `data` (full snapshot for a companion), `chat`, `chat_filter`, `identify`, `sound`, `state`, `ui`, `markers`, `waypoint`, `messaging`, `commands`, `profiles`, `terrain`, `admin_content`.

## Snapshot (highlights; full list in api.json `public_api.snapshot_fields`)
- Always: `api`, `time` (monotonic), `unix_time`, `player`, `server`, `state`, `error`, `events`, `capabilities`.
- Player: `health/stamina/mana` + max + base, `position{cell,x,y,z}`, `heading`, `level`, `burden_percent`, `pyreals`, `skills`, `trained_skills`, `char_ints/quads/doubles/bools/strings` (decimal property-ID string keys; bools are 0/1), `components_required`, `combat_mode`, `busy`, `ready`, `moving`, `jumping`.
- Magic: `spells`, `known_spells`, `enchantments` (with `duration`, `remaining`), `harmful_enchantments`, `debuffs`, `item_buffs`, `cooldowns` (keyed by cooldown ID), `last_spell(_confirmed)`.
- Inventory: `inventory` (appraised items: `int_properties`, `identified`, `can_wield`/`wield_reason`, icons, mana, `salvage_tool_available`, `mana_supply_available`...), `packs`, `pack_slots`, `main_pack_slots`, `inventory_revision`, `appraisal_revision`, `inventory_failure_*`.
- World: `objects` (up to 512 nearby, within 240 m: `id,name,wcid,distance,position,monster,player,corpse,dead,object_type`), `selection`/`selected`, `targets`, `tracked_targets`, `target_effects` (own confirmed casts only), `nearest`, `distance`, `corpses`, `route_objects` (doors: `door_open/locked`), `portal_events`, `portal_space`, `teleport_sequence`, `world_name`.
- Containers/vendors: `container`, `container_is_corpse`, `contents`, `vendor`, `vendor_stock`, `vendor_trade_notes`...
- Social: `fellowship{valid,name,open,leader,members}`, `in_fellowship`, `confirmations`.
- Results: `action_serial`, `action_error`, `events` (use/cast requested and completed), `action_events` (last 64), `combat_events` (hit, damage), `chat_events` (+ cursor fields), `log` (last 200).
- Target fields: `name, wcid, object_type, creature_class, title, level, pk_status, vitals{health,stamina,mana}` (health often a `fraction`, not hit points), `assessment_age`.
- Coordinates are AC cell + local metres, not Unreal cm. GUIDs are unsigned 32-bit. Never save GUIDs across sessions.

## Actions (one per callback; api.json `public_api.actions`)
- cast: `cast{spell,target,fast_cast,cast_jiggle}`, `cast_item{item,spell,target}` (cast+inventory)
- combat: `attack{target,mode 2 melee|4 missile,height 1-3,power 0-1}`, `cancel_attack`, `combat_mode{mode}`, `attack_bar{power}`
- navigation: `move{cell,x,y,z,arrival_radius,target}`, `face{heading}`, `jump{charge,heading,forward,strafe,walk_jump}`, `recall{destination}` (marketplace/lifestone/allegiance/house/mansion), `use_world{item}`, `close_vendor`, `select{target}`, `logout`
- inventory: `equip{item,offhand,unequip}`, `use_item`, `apply_item{item,target}`, `identify`, `store_item{item,target}`, `give{item,target,amount}`, `merge`
- loot: `open_corpse`, `close_corpse`, `loot{item,amount}`, `salvage{item,tool}`, `combine_salvage{tool,items}`, `sell`, `read`, `buy{vendor,item,count}`, `split_note`, `sell_note`
- Item Tools paths (inventory+loot): `it_give/it_buy/it_sell/it_merge/it_split/it_open/it_key/it_refresh_chest/it_close/it_pickup`
- social: `say{text,recipient|channel=2048}`, `fellowship{operation,...}`, `confirm{type,context,accept}`
- misc: `select_item` (ui), `waypoint` (waypoint), `command{text}` (commands: only `/acueucm`, `/acueitems`, `/myquests`), `plugin_command`, `profile_load`, `notice`, `stop`, buff-request/force-buff markers.
- Rate limits: casts and attacks at most once per 3.5 s, routes at most 2/s, chat send 1/s, commands bridge 1/s, identify 1/s. Native code revalidates everything, and the server decides. Treat submit as "requested" and confirm through serials, revisions and events.
- **Not possible:** raw packets, teleport, bypassing collision or cast delays, arbitrary slash commands, reading files, network or IPC.

## Services (`requests={{id,service,operation,...}}`, at most 4 per callback, 0.5 s apart, results in `events` as `{type="result",id,ok,error,...}`)
`profiles` (list/read/save/load/delete; archived, never hard-deleted), `import` (list/inspect/convert/export_loot/activate for VT .utl/.nav/.met/.usd from the user's import folder), `route` (record), `force_buff`, `policy` (command into your own driver queue), `waypoint` (set/clear), `window` (show/hide/toggle), `chat` (send), `notice` (local green chat line), `sound` (play), `log` (append/clear). Also `content` (admin) and `local_cosmetics`.

## UI
- `ui` = a tree of controls, each with a unique `id`: text, button, checkbox, slider, number, input, select, color, progress, icon, item_icon, image, row, column, section, tabs, overlay, frame. Up to 256 controls, 8 levels, 128 roots.
- Events come back in `snapshot.events`: `{type="click",id}`, `{type="change",id,value}`. The host doesn't persist values: handle the event, return the new value, and save it through `state` or a profile.
- Button actions: `event`, `select`, `select_item`, `waypoint`, `command`, `sound_file`, `content_folder`.
- Styling: color, size 10 to 36, bold, wrap, ellipsis, opacity, rotation, scale and offset transforms, blink/pulse/rotate effects, outline/glow. `presentation.window{opacity,pinned}`.
- World and map overlays: `markers` (`!`/arrow/diamond on nearby objects; world mesh + Waypoint map; 32 per plugin), `world_plates` (nameplates with vitals and effect timers; ui+markers; 4 per plugin, 16 globally), `terrain_overlay` (slopes/water/radar/dungeon light; one global provider), `runtime_route` (ground route line, navigation).
- **No** free-form drawing, D3D, custom meshes or shaders, retail compass/radar annotations, or arbitrary Slate.

## Chat
- `chat_events` (needs `chat`): `{serial,time,text,raw_text,sender,sender_type,color,chat_type}`. Up to 128 events / 64 KiB per callback, per-plugin cursors.
- `chat_subscriptions` (manifest or runtime; prefix/contains/exact/pattern/sender/sender_type/chat_type) to only receive matching lines.
- `chat_filters` (needs `chat_filter`): hide/show/color/route lines per chat window, natively, without a flash. 32 rules.
- Players type `/acueplugin <id> <text>` and the plugin gets `{type="command",text}` in `events`. This is how a "/ub ..." command surface would work.

## Bundled plugins that overlap UB (check before porting)
| Bundled | Mode | Overlaps UB tool |
|---|---|---|
| `ucm` (Lua, 3,825 lines) | automation | VTank itself; UB VTankControl/VTankFellowHeals targets; meta engine incl. VT expressions |
| `itemtools` | automation | AutoVendor, AutoTrade, InventoryManager (give/restock/chests) |
| `thirdeye` | companion | Nametags / spawn alerts |
| `waypoint` (C++) | n/a | Arrow, VisualNav, LandscapeMaps/DungeonMaps, chat coordinate links. Its doc has a "UtilityBelt compatibility" section |
| `derethlens` | companion | OverlayMap-ish terrain aids |
| `huntledger` (C++) | n/a | XPMeter |
| `supplyledger` (C++) | n/a | Counter |
| `autocraft` (C++) | n/a | AutoTinker-adjacent crafting |
| `looteditor` (C++) | n/a | VTClassic loot editing |
| `actiondeck` (C++) | n/a | Hotkeys/macros |
| `ucmmicro` (C++) | n/a | Compact controls |

## What Thwargle already concluded about UB (Waypoint.md "UtilityBelt compatibility")
UB can't run unchanged: net48/x86, unsafe code, Decal COM, VVS/VirindiHUDs/Hotkeys, DirectX, retail memory offsets (`Lib/PhysicsObject.cs`), and a Decal network filter. A useful port keeps the data and isolated algorithms, and replaces the integrations with host APIs and native panels.

## Open questions for Thwargle (seed list; grows from the port map)
- A way for companion/helper plugins to act (loot, vendor, use items) without stopping UCM.
- Multi-client communication (UB Networking / `/ub bc`): the API has local plugin messages only, nothing cross-client.
- Arbitrary world drawing (UB VisualNav lines, 3D text), currently markers/plates/route lines only.
- Expression functions for UCM metas from third-party plugins (UB adds many VT expression functions).
- Persistent storage beyond 64 KiB state plus profiles (UB settings and its loot/quest databases).
