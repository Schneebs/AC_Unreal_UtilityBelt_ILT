# UB tools (UtilityBelt/Tools/*.cs), one section per file

Method: profiled via grep of attributes/settings/API calls plus selective reads. Depth varies; "unclear" = not read. Paths: UtilityBelt/Tools/<File>. Persistence root: `<storage>` = Documents\Decal Plugins\UtilityBelt, `<char>` = `<storage>/<World>/<Character>`. Profile files `*.utl` = VTank loot profiles (evaluated by VTank's loot engine).
Common: most tools have `Enabled` setting; most commands send results via chat. "Lock" = `UBHelper.vTank.Decision_Lock(ActionLockType, ms)` to stop VTank acting while UB acts.

## Aliases (313 lines)
- Purpose: user-defined regex -> action on typed chat text.
- Commands: none (edited in UI).
- Settings: Enabled(true); Profile(char state, "[character]"); DefinedAliases (list of {Alias regex, Eat, Action}).
- Reads: `Core.CommandLineText`. Actions: run Expression / ChatExpression / ChatCommand; sets expression vars `capturegroup_<name>`.
- Persist: `<char>/aliases.json` or `<storage>/profiles/<name>.aliases.json`.
- Gotchas: multiple aliases can match; cannot override plugin cmds; needs UI for editing.

## Arrow (396)
- Purpose: HUD arrow pointing to coordinates; makes N/S E/W coords in chat clickable.
- Commands: `/ub arrow point <NS> <EW>` (e.g. 32.7N, 45.5E), `/ub arrow face`.
- Settings: Enabled(true); char state: Visible, HudSize(32), HudX(215), HudY(5), TargetEW, TargetNS.
- Reads: ChatBoxMessage (regex for coords), player position/heading (`Actions.Heading/Landcell/LocationX/Y`). Actions: `UBHelper.Core.TurnToHeading` for `face`; adds chat link text (`AddChatText`); adds marker on landscape map.
- Deps: UBHud + DxTexture (2D HUD drawing).

## Assessor (343)
- Purpose: rate-limited queue to request item appraisal (ID) data; used by other tools needing property data.
- Commands: `/ub testassessor` (debug).
- Mechanism: RenderFrame sends max 4 idents in flight, 75ms spacing, 5s timeout, retries up to 10; sends the appraise request (`m(id)`, an id request helper); listens `ServerDispatch` 0xF7B0 event 0x00C9 (APPRAISAL_INFO). Skips object classes (Money, Scroll, Container, Food, Key, Book, ...).
- Needs: send appraisal request, receive appraisal event, `WorldObject.HasIdData`, `UBHelper.Weenie(id).Valid`, `UBHelper.InventoryManager.GetInventory`.

## AutoSalvage (355)
- Purpose: salvage inventory items per the loaded VTank loot profile.
- Commands: `/ub autosalvage [force]`; expression `ustadd/ustopen/ustsalvage`.
- Settings: Think(false), OnlyFromMainPack(false).
- Actions: use Ust item, `Actions.SalvagePanelAdd`, `SalvagePanelSalvage`; locks VTank (Salvage). Reads inventory + loot profile verdict (`eLootAction.Salvage`), `Actions.OpenedContainer`.

## AutoTinker (1078)
- Purpose: UI to apply salvage (tinker) to weapons/armor, with success-chance calc (Lib/Salvage/TinkerCalc, Lib/Tinker/*).
- Commands: `/ub getjob` (print queued jobs), `/ub tinkcalc` (selected item: best iron/granite combo). `/ub autotinker` command is commented out; UI-driven.
- Settings: MinPercentage(99.5), MaxTinks(10).
- Reads: item props, skills, `CharacterFilter.CharacterOptions`. Actions: use salvage on item via Ust/crafting use (unclear exact calls). Mostly unclear beyond header.

## AutoTrade (592)
- Purpose: mule via trade window per loot profile; optional auto accept.
- Commands: `/ub autotrade <lootProfile>`, `/ub autotrade autoaccept add[gs]|remove[gs] <namePattern>`, `autoaccept list`.
- Settings: Enabled(false), TestMode, Think, OnlyFromMainPack, AutoAccept, AutoAcceptChars(list).
- Reads: WorldFilter trade events (EnterTrade, AddTradeItem, AcceptTrade, EndTrade, FailToAddTradeItem). Actions: `Actions.TradeAdd`, `TradeAccept`; VTank locks. Reads .utl file (File.Exists).

## AutoVendor (1245)
- Purpose: buy/sell at vendors per loot profile; vendor commands.
- Commands: `/ub autovendor <cancel|lootProfile>`; `/ub vendor open[p] <name|id|hex>`, `buyall`, `sellall`, `clearbuy`, `clearsell`, `opencancel`, `addbuy[p] <item>`, `addsell[p] <item>`.
- Settings: Enabled, EnableBuying, EnableSelling (true), TestMode, Think, ShowMerchantInfo(true), OnlyFromMainPack, Tries(4), TriesTime(5000ms).
- Reads: ServerDispatch/ClientDispatch raw messages: 0xF7B1 actions 0x5F/0x60 (client buy/sell), 0xF7B0 0x22 (item container change), 0x24, 0x197, 0x02DA, 0xF745 (object create) ; vendor item lists (`UBHelper.Vendor`), `VendorCache` (Lib/VendorCache). Actions: add to vendor sell/buy lists (`Actions.VendorAddSellList`, buy list), accept transaction, open vendor (use item); VTank locks; loads .utl profile.
- Gotchas: custom vendor currency support; needs client-memory inventory (UBHelper.InventoryManager).

## AutoXp (368)
- Purpose: spend XP across attributes/vitals/skills by weighted policy.
- Commands: `/ub xp [level|slow|test|export|import <json>]`.
- Settings: StopBeforeMax(10), TriesTime(300ms), MaxXpChunk(1e9), Policy (dict XpTarget->weight; attributes/vitals/skills default 1; neutral).
- Actions: raise attribute/vital/skill via Decal Actions (unclear exact call; xp spend packets) on RenderFrame timer.
- Persist: policy in settings; export/import as text.

## ChatFilter (119)
- Purpose: eat chat categories (recharge, otherscast, youcast, misc, attackonyou, attackontarget).
- Commands: `/ub chatfilter (recharge|otherscast|youcast|misc|attackonyou|attackontarget|all|test) (true|false)`.
- Settings: Enabled(false), per-category option sets (Lib/Settings/Chat/*). Depends on ChatHandler classification; code notes NPC chat cannot be eaten (GDLE/ACE packet mismatch).
- Needs ability to suppress chat (Decal `e.Eat` on ChatBoxMessage / network message).

## ChatHandler (403)
- Purpose: classifies raw chat/combat network messages into ChatType and raises UB events (used by ChatFilter, ChatLogger).
- Reads: ServerDispatch 0xF7B0 events 0x02BD (HearSpeech), 0x01AD (attacker notification) + ChatBoxMessage text regexes (damage, buffs, debuffs, regen, etc.).
- Needs: raw message hook; chat text hook.

## ChatLogger (417)
- Purpose: log chat to file by message-type/regex rules.
- Settings: SaveToFile(false), Rules (list of ChatLogRule {pattern, types}).
- Reads: ChatBoxMessage. Persist: `<char>/chat.txt` (Lib/ChatLog/ChatLogWriter). UI list editor.

## ChatNameClickHandler (57)
- Purpose: handle clicks on UB-made chat links: select object id (`Actions.SelectItem`) or open URL (`Process.Start`).
- Needs: chat link click events (Decal ChatClickIntercept), process launch.

## Client (493)
- Purpose: client UI/layout/graphics/process tweaks.
- Commands: `/ub getui`, `/ub setui UI:<str>`, `/ub resolution <w> <h>`, `/ub textures <landscape0-4> <landscapeDetail0-1> <env0-4> <envDetail0-1> <scenery1-25> <landscapeDraw1-25>`, `/ub element[q][ <element> [x y w h]]`, `/ub pcap {enable [depth]|disable|print}`, `/ub videopatch {enable|disable|toggle}`, `/ub globalframelimit <fps>`, `/ub bgframelimit <fps>`, `/ub clienthealth`, `/ub logout`, `/ub quit`.
- Settings: UIProfile("[character]"), per-element X/Y/Width/Height (ClientUI settings; element ids CHAT, VITS, RADA, EXAM, SBOX, COMB, PBAR, TBAR, INDI, ENVP, PANS, FCH, SVIT).
- Needs: `UBHelper.Core.GetElementPosition/MoveElement/SetResolution/SetTextures`, PCap, VideoPatch, frame limiter (native memory patches), window messages, logout/quit.
- Persist: `ClientUI` profile json.

## Counter (271)
- Purpose: count items matching name or .utl profile, or players in range.
- Commands: `/ub count item <name>|profile <lootProfile>|player <range> [debug] [think]`.
- Reads: inventory, WorldFilter players; loot profile via VTank loot engine; File.Exists on .utl.

## DerethTime (422)
- Purpose: day/night HUD + game-time expressions.
- Settings: Enabled(true), HudX(415), HudY(5), ShowLabel(true).
- Mechanism: computes Dereth time from client tick/server time (Dereth calendar: year/month/day/hour names); expressions listed in architecture.md. Needs UBHud drawing for the HUD; calc itself is pure math (need server-time reference; clock source unclear).

## DungeonMaps (1518)
- Purpose: overlay map of the current dungeon (data from lifestoned.org / cell.dat via UBService.CellDat), with visited tiles, compass.
- Settings: Enabled(true), Debug, DrawWhenClosed(true), ShowVisitedTiles(true), VisitedTilesColor, ShowCompass(true), Opacity(16), MapZoom(4.2), window X/Y/W/H, LabelFontSize(10), marker toggles/colors (many).
- Reads: player landcell/xyz/heading each frame (`Actions.Landcell/LocationX/Y/Z/Heading`), WorldFilter create/change (markers for portals, monsters etc. - `UBHelper.Core.RadarUpdate`), ServerDispatch 0xF747, portal change events; Database (LiteDB landblocks) for LSD data.
- Draws: DxTexture 2D into HUD; VVS view for window.
- Persist: LiteDB `landblocks`, visited tiles (format unclear).

## EquipmentManager (823)
- Purpose: equip sets from .utl profiles; damage calc.
- Commands: `/ub equip {list | load [lootProfile] | test [lootProfile] | create [lootProfile]}`, `/ub calcdamage`.
- Settings: Think(false).
- Profile search paths: `<storage>/equip/<Server>/<Character>/<Trade Partner>.utl`, ..., `default.utl` at several levels (EquipmentManager.cs:23-28).
- Actions: `Actions.MoveItem`/`UseItem` to wield; VTank locks (ItemUse); `BusyState` waits; reads inventory + loot profile (equip rules).

## FellowshipManager (645)
- Purpose: fellowship commands/auto-recruit and expressions.
- Commands: `/ub fellow create <name>|quit|disband|open|close|status|recruit[p] [name|id|selected]|dismiss[p] ...|leader[p] ...`.
- Settings: Enabled(false), MyAutoFellowPassword("xp"), BanList (char state list).
- Reads: fellowship events (Decal ChatBoxMessage/fellowship messages; exact hooks unclear), WorldFilter. Actions: send /fellow chat commands (`InvokeChatParser`) ; auto-accept/recruit people who say password (unclear details).

## GameEvents (306)
- Purpose: trigger actions (expressions/commands) on game events.
- Event types (Lib/GameEvents): Login, LoginComplete, Logout, CharacterDeath.
- Settings: Enabled(true), Profile("[character]"), HandlerList. Event args set as expression vars. Persist: game events profile json.

## GUI (178)
- Purpose: hosts UBService GUI (ImGui-style) demo/inspector. Settings: Enabled(true), MaxFramerate(60), EnableDemoUI, EnableGameStateInspector. Mostly in external lib (unclear).

## HealthTracker (178)
- Purpose: track target health % from server messages for expressions.
- Settings: Enabled(true). Reads ServerDispatch 0xF7B0: 0x01C0 (Combat_QueryHealthResponse), 0x00C9 (appraisal); WorldFilter.ReleaseObject. Expressions: wobjectgethealth(+value/stamina/mana).

## InventoryManager (897)
- Purpose: give items, autostack/autocram, unstack, item giver UI (ig).
- Commands: `/ub give[p|P|r] [count] <item> to <target>` (p=partial name, P/r regex variants), `/ub ig[p] <lootProfile> to <target>`, `autostack`, `autocram`, `unstack`, `clearbugged`.
- Settings: AutoCram, AutoStack, IGThink, IGFailure(3), IGBusyCount(10), IGRange(15), IGUIEnabled(true), IGWindow X/Y, TreatStackAsSingleItem(true), WatchLootProfile.
- Reads: inventory (client memory via UBHelper.InventoryManager), ClientDispatch 0xF7B1 action 0xBF (set inscription), WorldFilter changes, radar. Actions: give item (`Actions.GiveItem`-like `MoveItem` to target), stack split/combine, move to pack; VTank locks (ItemUse/Navigation). Expressions: actiontrygiveprofile/move/drop/split.

## ItemInfo (1226)
- Purpose: prints rich item descriptions (imbues, spells, damage calcs, magtools buffed values) when item selected/clicked/looted.
- Settings: Enabled(false), DescribeOnSelect/RightClick/LeftClick/Loot(true), ShowMagtoolsBuffedValues, ShowDamage, ShowValueAndBurden, AutoClipboard, ShowRetailComparison, ShowRetailMax, ShowDoorInfo, ShowNpcInfo.
- Reads: ItemSelected, WindowMessage (mouse), WorldObject properties (needs ID data), Lib/ItemInfoHelper dictionaries. Output: chat (+ clipboard).

## Jumper (301)
- Purpose: face heading and jump with hold time, pausing VTank nav.
- Commands: `/ub face <heading>`, `/ub jump[swzxc] [heading] [holdtime]` (suffix = direction key).
- Settings: PauseNav(true), ThinkComplete, ThinkFail, Attempts(3).
- Needs: `UBHelper.Jumper.Jump/JumpComplete/JumpCancel` (simulated jump with charge time), `UBHelper.Core.TurnToHeading`, VTank locks.

## LandscapeMaps (787)
- Purpose: landscape map window with POI markers (Lib/Maps/LandscapeMarkers, bundled marker data).
- Settings: Enabled(true), Opacity(16), window X/Y/W/H, marker type toggles. Reads player position/heading. Draws via DxTexture inside VVS view.

## LoginManager (223)
- Purpose: choose next character to auto-login.
- Command: `/ub login <name part|relative index>` (verb "login").
- Expressions: getcharacterindex, setnextlogin, clearnextlogin. Mechanism: `UBLoader.LoaderLogin.SetNextLogin(id)`; loader calls `AcClient.CPlayerSystem::LogOnCharacter` after logout. Needs native login call + character list.

## Looter (976)
- Purpose: loot chests and own corpse per active VTank loot profile.
- Settings: Enabled(false), EnableChests, EnableMyCorpse, BlockVtankMelee, JumpWhenLooting, JumpHeight(100), MaxOpenAttempts(10), MaxUnlockAttempts(10), AttemptsBeforeBlacklisting(500), AutoSalvageAfterLooting, DelaySpeed(1000), OverallSpeed(100), TestMode.
- Triggers: `/ub use <name>` on chest/corpse; auto for corpse/chest when enabled. Expressions hascorpsebeenopenedbyme, getcorpsesunopenedbyme.
- Reads: raw messages: ServerDispatch 0xF7B0 events 0x0196 (view contents), 0x0052 (close), 0x01C7 (use done failure), 0x0022 (container change), 0x0024 (delete), 0xF74E / 0xF750 (jump/lock state), 0x02D2 (qualities bool); ClientDispatch 0xF7B1 0x0019, 0xF61B. Actions: use container, move items to inventory (`MoveItem`), select, optional jump; lockpicks (use lockpick on chest); VTank locks CorpseOpenAttempt/ItemUse; may trigger AutoSalvage.

## LSD (354)
- Purpose: LifeStoned Database cache for dungeon/weenie data.
- Commands: `/ub lsdlb <landblock hex8>`, `/ub lsdclearcache`.
- Settings: Enabled(false), LSDWebRoot("https://lifestoned.org/"), LSDCacheSeconds(180 days).
- Needs: HTTP download (WebClient) + LiteDB cache (weenies, landblocks). Not portable without network access.

## Movement (401)
- Purpose: set/get movement motion states; key debug HUD.
- Commands: `/ub getmotion`, `/ub setmotion <Forward|Backward|TurnRight|TurnLeft|StrafeRight|StrafeLeft|Walk> <0|1>`, `/ub clearmotion`.
- Settings: ShowMovementKeysDebugUI, HudX(615), HudY(5), KeySize(24). Needs client movement input injection (`Core.Movement`/UBHelper) + HUD.

## Nametags (427)
- Purpose: draw name text above players/pets/allegiance members etc. in 3D view.
- Settings: Enabled(true), MaxRange(35), per-type nametag display options (player, pet, allegiance, ...).
- Reads WorldFilter create/change, positions; draws screen-projected text via HUD; pauses when video patched/unfocused (VideoPatch.Changed). Needs world-to-screen projection + overlay drawing.

## NetworkUI (475)
- Purpose: HUD listing other UB clients with vitals/tracked item counts; follow/use selected.
- Settings: Enabled(false), ShowHudWhenClosed(true), WindowPositionX/Y, TrackedItems (list), SelectedTag("All").
- Needs UBNet (see Networking), HUD drawing, `Actions.SelectItem`.

## Networking (563)
- Purpose: multi-client messaging (see architecture.md 7).
- Commands: `/ub bc [delayMs] <command>`, `/ub bct <tags,comma> [delayMs] <command>`, `/ub netclients <tag>`.
- Settings: Tags (char state list). Expression: netclients. Channel "utilitybelt" publishes ClientData/vitals/position/cast/tracked-item messages. Needs UBService local TCP server.
- Gotcha: received commands queued and run only if tags match; guarded against stale recipients (tests/Networking.*).

## OverlayMap (501)
- Purpose: 3D in-world map overlay (dungeon walls/floors) drawn with Direct3D.
- Settings: Enabled(false), OnlyDrawWhenVideoPatched(true), wall/ceiling/floor display options.
- Needs: raw D3D device, geometry from cell.dat (Lib/Geometry, LandblockGeometry, DynamicObjectGeometry), camera matrices (Lib/Camera), WorldFilter objects.

## Player (440)
- Purpose: inspector HUD of player data.
- Command: `/ub player aug|int|int64|bool|float|did|iid|str|pos|skill` (prints property tables). Settings: open player data window. Reads CharacterFilter/ client properties.

## PlayerOptions (383)
- Purpose: get/set in-game character options by name, with profile files.
- Command: `/ub playeroption list|<option> on|true|off|false`.
- Settings: Profile("[character]"); ~dozens nullable bool options (ViewCombatTarget, SalvageMultiple, MainPackPreferred, UseMouseTurning, LockUI, VividTargetingIndicator, ShowTooltips, CoordinatesOnRadar, SideBySideVitals, SpellDuration, DisableMostWeatherEffects, DisableDistanceFog, PersistentAtDay, ...).
- Needs: `UBHelper.Player.GetOption/SetOption/SaveOptions` (client memory + sends option packet). Persist: player options profile json.

## Plugin (2155)
- Purpose: core/misc commands + most generic expressions.
- Commands: (empty verb: print version), `help [cmd]`, `test`, `opt list|get <name>|set <name> <val>|toggle <name>`, `date [fmt]`, `delay <ms> <command>`, `closestportal`, `portal <params>` (use portal w/ retries; p variants), `follow[p] <name>` (VTank nav follow), `mexec <expr>`, `pos`, `id`, `printcolors`, `propertydump` (selected object), `playsound [id] <file>`, `vitae`, `combatstate <state>`, `swearallegiance[p] [name]`, `breakallegiance[p]`, `use[p] <item> [on <item2>]`, `select[p] <item>`, `close [objectclass]`.
- Settings: CheckForUpdates(true), Debug(false; hotkey), SettingsProfile, window positions, PortalThink, PortalTimeout(5000), PortalAttempts(3), VideoPatch(false), VideoPatchFocus, BackgroundFrameLimit(0), PCap(false), PCapBufferDepth(5000), chat message display options.
- Needs: UBHelper.VideoPatch/PCap/SimpleFrameLimiter/Allegiance; VTank follow via nav profile "UBFollow" (LoadNavProfile + NavSetFollowTarget + enable EnableNav); portal use detection by ServerDispatch 0xF74B; use/select/close actions; mp3 play (File.Exists).

## PrepClick (111)
- Purpose: auto-confirm YES/NO confirmation dialogs for a time window.
- Command: `/ub prepclick {stop|yes <seconds>|no <seconds>}`. Needs `UBHelper.ConfirmationRequest` event + auto-response; `Core.Uptime`.

## Professors (166)
- Purpose: tell Professor NPCs the right words / auto-confirm for school-of-magic augmentation.
- Command: `/ub professor <creature|item|life|war|void> <level>`; Settings: Timeout(600s). Reads ChatBoxMessage, ConfirmationRequest; sends tell by GUID (`UBHelper.Core.SendTellByGUID`).

## QuestTracker (573)
- Purpose: quest flag timers via /myquests parsing + expressions.
- Commands: `/ub quests check|parse <flag>`, `/ub myquests`. Settings: AutoRequest(true). Reads ChatBoxMessage (QuestFlag.MyQuestRegex), sends `/myquests` via `InvokeChatParser`, hides output. Persist: LiteDB `quest_flags` (per server/char). Expressions testquestflag/getqueststatus/getquestktprogress/...

## SpellManager (594)
- Purpose: save/load/clear spell tabs (spellbar favorites); spell expressions.
- Command: `/ub spell load|save|clear|test [tabs 1-8] [name]`. Settings: LoadBest(true), IgnoreComps(true), IgnoreSkill, DifficultyModifier(0), IgnoreMissingTabs(true), AddSpellsOnCast, Quiet. Reads `CharacterFilter.SpellBook`, portal.dat spell table (Lib/Spells). Actions: modify spell tab contents (client spellbar API, unclear call). Persist: saved spell tab files (unclear path).

## VisualNav (355)
- Purpose: draw VTank nav route (waypoints/lines) in 3D (like vi2).
- Settings: Enabled(true), ScaleCurrentWaypoint(true), LineOffset(0.05), SaveNoneRoutes. Reads vTank nav (NavNumPoints, nav profile route .nav file via Lib/VTNav parser), draws with D3D lines on RenderFrame; honors VideoPatch.

## VTankControl (2301)
- Purpose: bridge to VTank + home of expression engine functions and variable stores.
- Commands: `/ub translateroute <startLB> <route.nav> <endLB> <saveAs.nav> [force]`, `/ub listvars|listpvars|listgvars`.
- Settings: VitalSharing(true), PatchExpressionEngine(false; hotkey), MetaTickRateOverride(-1), FixPortalLoops(false), PortalLoopCount(3). Expressions: vars, wobject finders (iterate `WorldFilter`), char vital/skill/attr/props, spell state, UI controls, vt* (meta state/settings), actions (use/apply/give/cast/select/equip wand).
- Persist: LiteDB persistent/global vars. Needs VTank APIs + Harmony (VTankExtensions) for engine override.

## VTankExtensions (1229)
- Purpose: Harmony runtime patches to VTank (classic server skill support, more debuffs, ignore errors, better following, cleave).
- Command: `/ub dumpskills` (prints PlayerDesc skills 0x0013).
- Settings: EnableAutoClassicPatch(true), AdditionalDebuffs(list), DontStopOnError(true), BetterFollowing(true), EnableCleaveMod(false). Not portable (depends on VTank internals).

## VTankFellowHeals (471)
- Purpose: share vitals/casts between local clients into VTank's fellow heal system.
- Mechanism: reports own vitals every ~150ms over UBNet (VitalUpdateMessage); on receipt calls VTank VitalSharing; ClientDispatch 0xF7B1 action 0x4A (cast attempt) -> CastAttempt/CastSuccess messages (spell, target, skill/duration); ChatBoxMessage for cast success; ActionQueue. Needs UBNet + VTank.

## XPMeter (274)
- Purpose: HUD XP meter that works past level 275; xp/lum totals & avg.
- Command: `/ub xpmeter on|off|reset|true|false`. Settings: Enabled(true), ShowTotals, ShowTime, Visible. Reads XP total/luminance properties via CharacterFilter/ chat; expressions xpreset/xpmeter/xpduration/xptotal/lumtotal/xpavg/lumavg.
