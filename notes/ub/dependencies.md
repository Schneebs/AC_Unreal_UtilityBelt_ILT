# Porting dependency matrix (UB -> sandboxed Lua plugin API)

Assumed target API: no file/network/native access; actions only through validated intents; read-only game-state snapshot ~2x/second; some events likely. Legend of capability ids used below:
RAW = raw network message parsing (ServerDispatch/ClientDispatch, even eat/modify) | EVT = per-frame (RenderFrame) logic needing sub-second timing | D3D = 3D/D3D drawing | HUD = 2D window/HUD/overlay | FILE = file I/O | DB = persistent DB | NET = outbound HTTP | IPC = multi-client IPC | VT = VTank control/hooks | HOT = keyboard hotkeys | MEM = client memory/native hooks (UBHelper) | CHAT = chat intercept/inject | LOOT = VTank loot profile (.utl) engine.

Feasibility: Y = likely portable with plain state + intents; P = partially (core logic yes, some capability missing); N = depends on missing capability.

| Tool | Needs capability | Feasible | Notes |
|---|---|---|---|
| Aliases | CHAT (intercept typed text, eat), FILE/settings, expression engine | P | Needs command-line interception + a plugin-owned settings store. Pure logic otherwise. |
| Arrow | HUD, CHAT (read chat, make links), MEM (TurnToHeading) | P | Compass logic is simple (player pos + heading). Needs HUD drawing and a face-heading intent. |
| Assessor | RAW (appraisal reply), EVT, MEM (UBHelper.Weenie validity) | P | Needs an "appraise object" intent with rate limit; snapshot of appraised props. Replaces if API gives IDs with data. |
| AutoSalvage | LOOT, intents (use item, salvage panel add/salvage), EVT | P | Needs salvage-panel intents + own item rule evaluation (no .utl engine). |
| AutoTinker | Item props + salvage/tinker intents, EVT, HUD (UI) | P | Calc is pure math; applying salvage requires use-on intents and ID data. |
| AutoTrade | Trade events + trade add/accept intents, LOOT, EVT | P | Needs trade window state + intents. |
| AutoVendor | RAW (vendor/inventory messages), vendor buy/sell list intents, LOOT, MEM (Vendor, Inventory), EVT | P/N | Needs vendor inventory snapshot and buy/sell intents; item verdicts need own rule engine. |
| AutoXp | Intents to spend XP, EVT timer | Y/P | Logic simple if "raise skill/attribute" intent exists. |
| ChatFilter | CHAT (eat), RAW | N | Requires suppressing chat messages; code itself says NPC chat can't be eaten. |
| ChatHandler | RAW + CHAT | P | Classifier regexes can run on chat text events if chat events exist. |
| ChatLogger | CHAT (read), FILE | N/P | Needs file output (unless host provides log API). |
| ChatNameClickHandler | Chat link click events, process launch | N | Skip. |
| Client | MEM (UI element move, resolution, textures, pcap, video patch, frame limit), logout/quit | N | Native memory patches; not portable. |
| Counter | Inventory snapshot, LOOT | Y/P | Name matching works; .utl needs rule engine. |
| DerethTime | Server-time source; HUD for display | Y/P | Math only; needs reliable game time. |
| DungeonMaps | HUD, D3D(2D textures), cell.dat reads (UBService.CellDat), DB, NET (lifestoned), position each frame | N/P | Needs dat access/geometry and HUD canvas; high rate position. |
| EquipmentManager | LOOT/FILE (.utl), intents (equip/move/use), BusyState | P | Needs wield intents and item props. |
| FellowshipManager | CHAT (/fellow commands), fellowship events/state, EVT | P | Mostly intents (recruit/dismiss/etc.) + fellowship state. Auto-recruit needs chat events. |
| GameEvents | Login/LoginComplete/Logout/Death events, expression engine | Y/P | Needs event hooks; actions via chat command intents. |
| GUI | UBService GUI | N | External ImGui layer. |
| HealthTracker | RAW (0xF7B0 0x01C0 health query response) | P | Needs target health % events; snapshot maybe sufficient. |
| InventoryManager | Inventory snapshot, intents (give/move/split/stack), RAW (0xF7B1 0xBF), MEM (inventory in client memory), EVT | P | Pacing/busy detection critical; snapshot at 2Hz too slow for fast stacking. |
| ItemInfo | Item select/click events, full item properties (ID data), CHAT output, clipboard | P/N | Needs appraisal data + selection events; clipboard unavailable. |
| Jumper | MEM (Jumper, TurnToHeading), VT locks, EVT | N | Needs timed jump hold + facing intents at frame granularity. |
| LandscapeMaps | HUD canvas, position/heading, bundled marker data | P | Needs map window/canvas drawing. |
| LoginManager | Native login call, character list | N | Needs loader-level login automation. |
| Looter | RAW (container events), intents (use, move), VT locks, LOOT, EVT, jump | P/N | Needs container-open events and move-item intents with fast reaction; loot profile from VTank unavailable. |
| LSD | NET, DB | N | Network + persistent cache. |
| Movement | Motion injection (set/clear motion), HUD | N/P | Needs a "set movement" intent. |
| Nametags | D3D/HUD world-to-screen, object positions every frame | N | Needs per-frame projection and overlay drawing. |
| NetworkUI | IPC, HUD | N | Needs IPC. |
| Networking | IPC (UBNet TCP server), chat command exec | N | Cross-client messaging is the hard blocker; maybe host-provided channel. |
| OverlayMap | D3D (raw device), dat geometry (cell.dat), camera matrices, EVT | N | |
| Player | Property read (aug/int/int64/bool/float/did/iid/str/pos/skill), HUD/chat out | Y | Snapshot-based; fine. |
| PlayerOptions | MEM (UBHelper.Player options), FILE profile | P | Needs "get/set option" intents. |
| Plugin | CHAT (/ub commands), MEM (VideoPatch/PCap/frame limiter), VT (portal/follow), use/select/close intents, FILE (settings, playsound), Allegiance, expression engine | P | Core expression engine and many commands portable; patches not. |
| PrepClick | MEM (ConfirmationRequest events + response) | N | Needs yes/no dialog hook. |
| Professors | CHAT, confirmation events, tell-by-guid | P/N | Needs confirm dialog handling. |
| QuestTracker | CHAT read (/myquests output), send chat, DB | P | Needs chat intercept to hide output and persistent store. |
| SpellManager | Spellbook state, spell tab edit | P/N | Spell tab write API unknown; portal.dat spell table read. |
| VisualNav | D3D, VT nav state, nav file parse (FILE) | N | |
| VTankControl | VT (settings, meta, nav), DB (vars), expression engine, wobject finders, intents | P | Expression engine and finders portable; VTank-specific functions (vt*) not; actiontry* need intents. |
| VTankExtensions | VT (Harmony patching VTank internals) | N | Pure VTank hack; irrelevant to non-VTank clients. |
| VTankFellowHeals | IPC, VT | N | |
| XPMeter | XP/lum value reads, HUD | Y/P | Needs only snapshot and a display. |

## Cross-cutting blockers (what a snapshot+intent Lua API lacks)
1. RAW message hooks used by ~12 tools (Assessor, AutoVendor, Looter, HealthTracker, ChatHandler, VTankFellowHeals, InventoryManager, Plugin portal retry, DungeonMaps, loader). Events like appraisal received, container contents viewed, use failure, vendor open/close, object delete, item moved are timing sensitive; 2 Hz snapshots add latency but may suffice for slow flows (vendor, loot at 1s delay).
2. Per-frame logic (RenderFrame state machines) in Jumper, Looter, AutoVendor, Assessor, Inventory/give, Movement.
3. D3D/HUD drawing: Arrow, DerethTime, DungeonMaps, LandscapeMaps, Nametags, OverlayMap, VisualNav, XPMeter, NetworkUI, Player.
4. File/DB: settings, aliases, game events, LiteDB (persistent vars, quest flags, LSD cache), chat logs, .utl loot profiles, equip/*.utl, nav files.
5. IPC: Networking, NetworkUI, VTankFellowHeals, bc/bct.
6. VTank dependence: loot profile engine (Looter, AutoVendor, AutoSalvage, AutoTrade, Counter, EquipmentManager, ig), decision locks, nav, Harmony patches. In a non-VTank client these are replaced by plugin-defined rules and intent queue exclusivity.
7. Native client memory (UBHelper): video patch, frame limit, pcap, UI element move, resolution/textures, player options, jump hold, login, confirmation dialogs.
8. Chat intercept/eat: Aliases, ChatFilter, QuestTracker, /ub command dispatch.

## Most portable (logic-only) pieces
- Expression/meta-expression engine (grammar + ~280 functions; see architecture.md) as a Lua interpreter of the same syntax; list/dict/math/string/var functions are pure.
- Command dispatcher (regex per verb) and settings schema.
- Calculators: AutoTinker TinkerCalc, ItemInfo damage/imbue calcs, DerethTime, Arrow bearing, AutoXp planner, FellowshipManager state expressions, Counter name matching.
