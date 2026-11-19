# UtilityBelt → AC:Unreal port map

Inputs: `notes/ub/*.md` (UB source analysis, UB master a84ca96, 2026-10-27) and `notes/acunreal-plugin-api.md` (client v161). This replaces the generic feasibility guesses in `notes/ub/dependencies.md` with what the real API offers.

## Ground rules that shape everything
1. **Companions run beside UCM but can't act.** They can read everything (`data`), chat-send (`say`), identify (1/s), select, set the NAV arrow, play sounds, show UI/markers/plates, and drive UCM and Item Tools through the `commands` bridge (`/acueucm ...`, `/acueitems ...`, `/myquests`).
2. **Automation can act but is exclusive.** Starting a UB automation stops UCM. UB's model (helper actions alongside VTank, using decision locks) has no equivalent yet.
3. **Don't duplicate bundled plugins.** Where the client already ships a tool, improve that (an issue or PR to Thwargle) instead of making a UB copy. That matches the goal of one version of each replacement.
4. **No file, network, IPC or native access.** Persist through `state` (64 KiB per character) and the `profiles` service (up to 8 MiB files).
5. **Command surface:** players type `/acueplugin utilitybelt <verb> <args>`, which arrives as `{type="command",text}`. A short `/ub` alias would need an API addition.

Legend for Target: **Native** = already in the client, use or improve it. **C** = UB companion (portable now). **C+** = companion that delegates the action to UCM or Item Tools through the commands bridge. **A** = needs a UB automation (stops UCM) or the helper lane. **API** = blocked until Thwargle adds something. **Skip** = not applicable to AC:Unreal.

## Per-tool map
| UB tool | Target | AC:Unreal path | Gap / note |
|---|---|---|---|
| Plugin (core `/ub` commands) | C | Command dispatcher on `events` type=command; `use/select/close` → select via `action="select"`, use needs A | `/ub` alias (API). `portal`, `follow`, `use` need actions → A or UCM bridge |
| Aliases | API | — | Needs interception of typed chat text. Only `/acueplugin` text reaches plugins today |
| Arrow | Native | Waypoint plugin: arrow, clickable chat coordinates; `waypoint` service `set` | `face` → `face` action (A) |
| Assessor | Native | Host appraisal: `identify` (companion, 1/s), plates auto-assess, `identified`/property maps in snapshot | Not needed as a tool |
| AutoSalvage | Native | UCM loot profile salvage + `salvage`/`combine_salvage` actions | Standalone "salvage now" → A |
| AutoTinker | C (calc) / A (apply) | TinkerCalc in Lua on appraised `int_properties`; applying = `apply_item` (inventory, A) | Autocraft overlaps crafting, not tinkering. Good C candidate for calc-only |
| AutoTrade | API | — | No trade-window state or trade intents in the API |
| AutoVendor | Native / C+ | Item Tools shop/profile/restock (`/acueitems shop|restock`), `buy/sell/sell_note` actions | Rule profiles are UCM loot profiles |
| AutoXp | API | — | No "spend XP" action. Planner math portable |
| ChatFilter | C | `chat_filters` (hide/show/color/route per window, native, no flash) + `chat_subscriptions` | Port UB's category regexes. Strong candidate |
| ChatHandler | C (library) | `chat_events` with `chat_type`, `sender_type` | Internal helper for other UB tools |
| ChatLogger | API / Native | Host has a chat log file option. Rule-based files need file output | Ask for a bounded plugin log-to-file service, or skip |
| ChatNameClickHandler | Skip | Waypoint handles coordinate links | |
| Client | Skip | Native graphics/UI settings | Retail memory patches |
| Counter | C | `inventory` + `lootmatch` for rules; `objects` for player counts | Strong candidate |
| DerethTime | C (needs check) | Calendar math in Lua from `unix_time`, if the epoch matches the server clock | Client syncs sky to the server clock natively; ask to expose game ticks if `unix_time` math drifts |
| DungeonMaps | Native | Waypoint world/dungeon map | Improve Waypoint instead |
| EquipmentManager | A / Native | UCM equipment handling; `equip` action needs inventory (A) | `.utl` equip sets → UCM loot-rule format |
| FellowshipManager | Native / A | UCM auto fellowship manager (tell password) + `fellowship` actions (not companion-allowed) | Commands → A or UCM bridge |
| GameEvents | C (partial) | Login = companion start; death/portal from snapshot (`portal_events`, vitals); actions limited to companion abilities | |
| GUI | Skip | Native UI controls | |
| HealthTracker | Native | Target `vitals` / `health_fraction` in snapshot | |
| InventoryManager | Native / C+ | Item Tools give/merge/split/chest; `/acueitems give` | autostack via `it_merge` (A) |
| ItemInfo | C | Read selected or appraised item properties; print to panel or `notice` | Verify that `selection` covers inventory items. Clipboard impossible. Strong candidate |
| Jumper | C+ / A | `jump` action (navigation, A) or UCM meta `jump` through `/acueucm` | |
| LandscapeMaps | Native | Waypoint map | |
| LoginManager | Skip / API | — | Login-screen automation is not in the plugin API |
| Looter | Native / A | UCM corpse looting; Item Tools keyed chests (`it_open/it_key`); `loot`/`open_corpse` (A) | Chest looting with lockpicks: `lockpick_available` exists, needs A |
| LSD | Skip | — | No network. Waypoint and the DAT files cover the map data |
| Movement | API | — | No raw motion intents (only `move`/`face`/`jump`) |
| Nametags | C (limited) | `world_plates` (4 per plugin, 16 globally), `markers` (32) | Limits are too low for "every player in range". Ask for a lightweight nametag surface |
| NetworkUI | API | — | Cross-client |
| Networking (`/ub bc`, `bct`, tags) | API | Local plugin `messages` only | Biggest blocker: needs a host-provided multi-client channel |
| OverlayMap | Skip / Native | Dereth Lens terrain overlay covers some of it | Raw D3D |
| Player (inspector) | C | `char_ints/quads/doubles/bools/strings`, `skills`, enchantments | Easy first port |
| PlayerOptions | API / Skip | — | No client options API |
| PrepClick | A | `confirmations` + `confirm` action (not companion-allowed) | UCM already answers known confirmations |
| Professors | C / A | Tell via `say` with `recipient` (companion OK); confirm needs A | |
| QuestTracker | C | `/myquests` via the commands bridge or `say`; `chat_subscriptions`; `chat_filters` hide the dump; flags in `state` | Kill Tracker example is close. Strong candidate |
| SpellManager | API | — | No spell-tab or spellbar API |
| VisualNav | Native | UCM "Show route in world" | |
| VTankControl (expressions, vars) | C (engine) / API (meta hook) | UCM already evaluates VT meta expressions natively. UB's ~260 extra functions can't be registered into UCM | Ask for plugin-registered meta expression functions. A Lua `/ub mexec` interpreter is possible but standalone |
| VTankExtensions | Skip | UCM is native; no VTank to patch | |
| VTankFellowHeals | API | — | Cross-client |
| XPMeter | Native | Hunt Ledger (XP/lum totals and rates) | Add past-275 or UB-style views to Hunt Ledger if missing |

## Tally
- Native already (use or improve the bundled tool): Arrow, Assessor, AutoSalvage, DungeonMaps, LandscapeMaps, HealthTracker, VisualNav, XPMeter, plus most of AutoVendor, InventoryManager, Looter, FellowshipManager, EquipmentManager.
- Portable now as UB companions: ChatFilter, ChatHandler, Counter, ItemInfo, Player, QuestTracker, TinkerCalc, DerethTime (check), GameEvents (partial), Nametags (limited), Professors (partial), core command dispatcher.
- Blocked on API: Aliases, AutoTrade, AutoXp, ChatLogger, Movement, Networking/NetworkUI/VTankFellowHeals, PlayerOptions, SpellManager, meta expression registration, short `/ub` prefix.
- Skip: Client, ChatNameClickHandler, GUI, LSD, LoginManager, OverlayMap, VTankExtensions.

## Suggested order
1. **Foundation (C):** one `utilitybelt` companion with a command dispatcher (`/acueplugin utilitybelt <verb>`), settings in a profile, per-character data in `state`, shared Lua helpers (chat classifier, item-property names). Single `main.lua`; there is no `require`.
2. **Quick wins (C):** QuestTracker, ItemInfo, Counter, Player, ChatFilter. Each is read-plus-display with no automation conflict.
3. **API request list to Thwargle**, in priority order: (a) helper action lane for companions alongside UCM, (b) cross-client channel, (c) `/ub` command prefix and text interception, (d) plugin-registered meta expression functions, (e) trade window, XP spend, spellbar, client options, (f) larger nametag/plate limits.
4. **Action tools** after (a) lands: Jumper, PrepClick, Looter chests, AutoTinker apply, EquipmentManager, `/ub use|portal|follow`.

## Open checks before coding
- Whether `snapshot.selection` includes items selected in inventory (ItemInfo depends on it).
- Whether `unix_time` plus UB's Dereth epoch gives the same time as the client's sky clock (DerethTime).
- Whether one UB plugin should be split into several plugins (QuestTracker, ItemInfo...) so players enable only what they want. The enabled-plugin limit is 16 by default.
