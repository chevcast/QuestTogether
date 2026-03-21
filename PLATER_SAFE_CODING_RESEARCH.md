# Plater Deep Dive

## Scope
- Source inspected: `/mnt/d/Battle.net/World Of Warcraft/_retail_/Interface/AddOns/Plater`
- Retail version inspected from TOC: `Plater-v637-Retail`
- Goal of this document:
  - Explain Plater like a new developer joining the project
  - Map the addon's high-level and low-level infrastructure
  - Trace how it interacts with Blizzard nameplate code and APIs
  - Deep dive quest mob detection
  - Extract the taint-avoidance and secure-UI lessons most relevant to QuestTogether

## Executive Summary
- Plater is not just a skin for Blizzard nameplates. It is a full runtime that hosts its own frame tree, event pipeline, update loop, script engine, plugin system, comms layer, resource system, aura system, and boss-mod integration.
- Its core architectural move is: keep Blizzard nameplates as the source of truth for nameplate existence, but render Plater's own `unitFrame` on top of Blizzard's lifecycle and often around Blizzard-owned subtrees rather than pretending Blizzard is gone.
- Plater is really several implementations behind one addon surface. Mainline, Classic, and Midnight branch heavily in aura handling, tooltip access, click-space APIs, ghost auras, protected-frame hiding, and secret-value safety.
- It treats secure/forbidden/combat restrictions as a normal operating environment, not as edge cases. The dominant pattern is guard, early return, and deferred retry.
- Its formal public API is tiny in this build. The real extension surfaces are scripts, hooks, plugins, comms, and selected integrations, not `Plater_API.lua`.
- It has learned several concrete anti-taint lessons the hard way. The most important is not to write custom state into Blizzard-owned frame members that can later be recycled into protected nameplates.
- Quest mob detection is primarily tooltip-driven. Plater builds a cache of active quest titles, then scans unit tooltips for quest lines and parses progress text. It intentionally skips this whole pipeline inside instances.

## 1. Load Order And Project Shape

Plater's TOC tells you a lot about the architecture:

1. `libs\libs.xml`
2. Locales
3. `Plater.xml`
4. `Definitions.lua`
5. `Plater_DefaultSettings.lua`
6. `Plater_Data.lua`
7. `Plater_Logs.lua`
8. `Plater_Util.lua`
9. `Plater.lua`
10. Subsystems and helpers:
    `Plater_ScriptHelpers.lua`, `Plater_PerformanceUnits.lua`, `Plater_Comms.lua`, `Plater_Auras.lua`, `Plater_Resources.lua`, `Plater_Resources_Frames.lua`, options files, boss-mod support, plugins, API, etc.
11. `Plater_LoadFinished.lua`

Key architectural implication:

- `Plater.xml` is tiny. It declares a script include and a border template. Most of the addon lives in Lua, not XML.
- `Definitions.lua` is the developer map of the runtime objects.
- `Plater_DefaultSettings.lua` is effectively the feature surface area of the addon.
- `Plater_Data.lua` bootstraps namespaces and shared tables before the core exists.
- `Plater.lua` is the engine.
- Later files attach systems onto the core tables created by `Plater.lua` and `Plater_Data.lua`.

For a new developer, the best mental order is:

1. TOC
2. `Definitions.lua`
3. `Plater_Data.lua`
4. `Plater.lua`
5. `Plater_Auras.lua`
6. `Plater_Resources.lua`
7. `Plater_BossModsSupport.lua`
8. `Plater_ScriptHelpers.lua`
9. `Plater_Comms.lua`
10. `Plater_Plugins.lua`
11. Default settings and option panels only after you understand runtime flow

## 2. High-Level Mental Model

Plater is easiest to understand as five layers.

### 2.1 Bootstrap Layer
- `Plater.xml`
- `Definitions.lua`
- `Plater_DefaultSettings.lua`
- `Plater_Data.lua`

This layer defines types, defaults, namespaces, media lists, caches, constants, and shared tables.

### 2.2 Core Nameplate Engine
- `Plater.lua`

This layer owns:

- Addon initialization through DetailsFramework
- Event registration and dispatch
- Nameplate creation/add/remove lifecycle
- Plate classification
- Update and tick pipelines
- CVar management
- Threat, colors, text, size, indicators, range, quest state

### 2.3 Subsystem Layer
- Auras
- Resources
- Boss-mod support
- Performance units
- Comms
- Plugins
- Scripting helpers

These are separate files, but they are not independent addons. They extend Plater's runtime tables and assume the core engine exists.

### 2.4 Extension Host Layer
Plater is also a platform for third-party behavior:

- Hooks / mods
- Scripts
- Plugins
- Comms between script instances
- External addon integration: DBM, BigWigs, Masque, OmniCC, Questie, Details

### 2.5 Blizzard Boundary Layer
Plater does not replace Blizzard's nameplate driver. It rides on top of it and constantly negotiates with:

- `C_NamePlate`
- `NamePlateDriverFrame`
- `NamePlateUnitFrameMixin`
- Blizzard resource bars
- Blizzard widget containers
- Blizzard aura APIs
- Blizzard tooltip APIs
- CVars
- Protected and forbidden nameplates

This boundary layer is where most taint and secure-UI precautions live.

### 2.6 Client Flavor Divergence
One misconception to avoid: there is no single Plater implementation.

Plater repeatedly forks behavior by client family:

- Mainline / Retail
- Classic branches
- Midnight / Apocalypse paths

The same subsystem can have materially different rules per client:

- Auras: incremental caches on retail, different filter semantics on Midnight, ghost auras disabled on Midnight
- Nameplate hiding: normal `:Hide()` when allowed, protected-frame detachment in some cases, `SetAlpha(0)` plus reparenting on Midnight
- Click and stacking APIs: older CVar paths on some clients, `C_NamePlateManager` and bitfields on Midnight
- Tooltip reads: structured `C_TooltipInfo` when possible, hidden tooltip fallbacks otherwise

For maintenance, the correct mental model is:

- one addon
- several client-specific boundary implementations
- one shared conceptual architecture

## 3. Core Runtime Objects And Data Model

`Definitions.lua` is unusually valuable here. It tells you what Plater believes its own runtime objects are.

### 3.1 `plateFrame`
This is still fundamentally the Blizzard nameplate frame. Plater adds references and cached state to it.

Important fields:

- `actorType`
- `unitFrame`
- `UnitFrame` (the Blizzard unit frame)
- `unitFramePlater` backup
- `QuestInfo`, `QuestAmountCurrent`, `QuestAmountTotal`, `QuestText`, `QuestName`, `QuestIsCampaign`
- `isSoftInteract`, `isObject`, `isPlayer`, `isSelf`, `isBattlePet`, `isWidgetOnlyMode`
- `PlaterAnchorFrame`
- `OnTickFrame`

### 3.2 `unitFrame`
This is Plater's real UI object. It is a DetailsFramework unit frame attached to the nameplate lifecycle.

Important fields:

- `namePlateUnitToken`
- `targetUnitID`
- `healthBar`
- `castBar`
- `powerBar`
- `BuffFrame`
- `BuffFrame2`
- `ExtraIconFrame`
- `BossModIconFrame`
- `WidgetContainer`
- `isPerformanceUnit*`
- `InCombat`
- `Quest*` mirror fields for scripts

### 3.3 `MEMBER_*` cached members
Plater caches frequently-used state with member-name strings like:

- `namePlateUnitToken`
- `namePlateUnitGUID`
- `namePlateNpcId`
- `namePlateIsQuestObjective`
- `namePlateUnitReaction`
- `namePlateInRange`
- `namePlateNoCombat`
- `namePlateUnitName`
- `namePlateUnitNameLower`

These are used to avoid repeated string-building and repeated API calls across hot paths.

### 3.4 Important design warning
One of Plater's strongest taint lessons is explicitly encoded in code comments:

- It does not write `plateFrame[MEMBER_UNITID]`.
- Reason: that member belongs to Blizzard's default nameplate internals, and writing into it caused taint when Blizzard later recycled that frame into protected usage.

This is a major rule for QuestTogether:

- Do not treat Blizzard frames as general-purpose Lua tables for custom state.
- Put your own state on your own frames or your own side tables.

## 4. Bootstrap And Shared Infrastructure

### 4.1 DetailsFramework is a hard dependency
Plater is built on DetailsFramework:

- Addon object creation
- Unit frame creation
- Scroll boxes and UI widgets
- Animation hubs
- Utility tables and dispatch

Without that, Plater's structure makes much less sense.

### 4.2 `Plater_Data.lua`
This file seeds shared namespaces and caches:

- `platerInternal.Scripts`
- `platerInternal.CastBar`
- `platerInternal.Mods`
- `platerInternal.Events`
- `platerInternal.Comms`
- `platerInternal.Frames`
- `platerInternal.Data`
- `platerInternal.Logs`
- `platerInternal.Audio`

It also creates:

- Cached unit-token lists for party, raid, boss, arena, and nameplates
- Comm prefixes
- `Plater.UnitReaction`
- `Plater.PerformanceUnits`
- `Plater.Resources`
- `Plater.Auras`
- Boss-mod timer tables
- Media lists
- `Plater.ForceInCombatUnits`

That last table is important. It is an explicit list of NPC IDs that should be treated as effectively in combat even when the game state is awkward or misleading.

### 4.3 `Definitions.lua`
This is not just type sugar. It is a map of what Plater thinks exists.

For reverse engineering and maintenance:

- Read it early
- Keep it updated if we borrow patterns
- Use it as the canonical list of what state is expected to exist on a plate or unit frame

### 4.4 `Plater_API.lua` is intentionally small
`Plater_API.lua` is easy to overestimate.

In this inspected build it documents and exposes a very small public API surface, essentially:

- `Plater.IsCampaignQuest(questName)`

That is important architecturally:

- the API file is not the real addon contract
- the real extension model is scripts, hooks, plugins, comms, profile data, and selected helper functions spread through the runtime

For a new developer, this means:

- do not start from `Plater_API.lua` expecting the addon's architecture to be represented there
- treat it as a thin exported helper layer, not the heart of the system

## 5. Nameplate Lifecycle

This is the most important runtime path in the addon.

### 5.1 `NAME_PLATE_CREATED`
When Blizzard creates a nameplate, Plater builds its own frame tree around it.

Key work done here:

- Create a Plater `unitFrame` via DetailsFramework with Plater-controlled unit, health, cast, and power-bar options
- Optionally parent the Plater unit frame to `UIParent` instead of the Blizzard plate when the profile wants frame-strata flexibility
- Create `PlaterAnchorFrame`, which becomes the addon's general anchor surface for layout decisions
- Create buff containers, aura caches, ghost-aura caches, extra-aura caches, target visuals, aggro flash, raid-target visuals, stacking debug support, and other plate-owned helpers
- Mix `Plater.ScriptMetaFunctions` into the unit frame and later into aura icons so scripts can treat them as runtime hosts
- Hook healthbar and castbar behavior through framework hooks and `hooksecurefunc`
- Backup the real Plater unit frame into `plateFrame.unitFramePlater` so it can be restored if a script or external addon corrupts `plateFrame.unitFrame`
- Fire `HOOK_NAMEPLATE_CREATED`

The result is:

- Blizzard still owns plate existence
- Plater owns most visible presentation and extension surfaces

### 5.2 `FORBIDDEN_NAME_PLATE_UNIT_ADDED`
This is a special secure/forbidden handling path.

Plater retrieves the nameplate with `C_NamePlate.GetNamePlateForUnit(unitID, true)`.

Why it matters:

- Secure or forbidden nameplates are normal in some contexts
- Plater treats them as a compatibility case, not as an unexpected failure
- On non-mainline clients it also toggles Blizzard castbar texture loading behavior here

### 5.3 `NAME_PLATE_UNIT_ADDED`
This is the main attach path.

The broad sequence is:

1. Find the plate frame with `C_NamePlate.GetNamePlateForUnit(unitID)`
2. Fallback to forbidden retrieval if needed
3. Restore `plateFrame.unitFrame` from `unitFramePlater` if another addon or script broke it
4. Cache unit token on the Plater unit frame
5. Compute reaction, soft-interact state, object state, widget-only state, battle-pet state, player/self state
6. Cache GUID and derive NPC ID
7. Classify actor type:
   - player personal plate
   - friendly player
   - enemy player
   - friendly NPC
   - enemy NPC
8. Decide whether Plater should own this plate or whether Blizzard should remain the visible implementation for this actor/config/client combination
9. Hook Blizzard frame `Show` once and, in Midnight, also guard `SetAlpha`
10. If Plater should not own the plate:
    - mark Blizzard frame enabled
    - hide Plater frame
    - adjust anchor behavior so Plater helpers can still align to Blizzard-owned bars when needed
    - keep Blizzard support paths alive
    - return
11. If Plater owns the plate:
    - hide Blizzard visuals
    - show Plater frame
    - bind unit
    - clear old cached state
    - configure performance-unit reductions
    - cache name, GUID, NPC ID, reaction, threat, classification, combat, guild, etc.
    - call `UpdatePlateFrame`
    - reparent Blizzard `WidgetContainer`
    - start the tick loop
    - register aura updates
    - sync boss-mod auras
    - update resources
    - run hooks

This path is the heart of the addon.

### 5.4 `Plater.OnRetailNamePlateShow`
This is the core Blizzard-hiding function.

Behavior:

- If the Blizzard plate has been marked as intentionally enabled, Plater leaves it alone
- Otherwise Plater hides or suppresses Blizzard visuals

Important safety details:

- If the frame is protected, Plater does not blindly `:Hide()` it
- It clears points and parents cautiously
- In Midnight it uses `SetAlpha(0)` and reparents Blizzard subframes to a hidden parent because click behavior and protection rules are different
- `SUPPORT_BLIZZARD_PLATEFRAMES` is a real global mode, enabled when any actor-type module is disabled; in that mode Plater is more conservative about unregistering Blizzard events because Blizzard-owned plate paths may still be intentionally visible
- If Plater does not need Blizzard frame support, it unregisters Blizzard unit/castbar events after hiding Blizzard visuals
- It also uses `CompactUnitFrame_UnregisterEvents` where available

This function is one of the strongest examples of Plater's secure-frame pragmatism:

- It does not assume one hiding strategy works everywhere
- It varies by protection status and client flavor

### 5.5 `NAME_PLATE_UNIT_REMOVED`
Teardown is just as careful as setup.

Key work:

- Stop aura updates
- Cancel scheduled refreshes
- Fire remove hooks
- Stop `OnUpdate`
- Reset quest and soft-interact state
- Stop active animations
- Run widget `OnHideWidget` cleanup
- Reset aura containers
- Remove private aura anchors
- Unset the unit on the Plater frame
- Move `WidgetContainer` back to Blizzard
- Explicitly hide the frame if UIParent parenting is enabled

This cleanup discipline matters for taint and correctness because nameplates are aggressively recycled.

## 6. Update Loop And Runtime Flow

### 6.1 Event-driven outer loop
`Plater.EventHandlerFrame` registers a broad set of events:

- Nameplate add/remove/create
- Combat enter/leave
- Target/focus/soft-target changes
- Zone changes
- Quest-log changes
- Group/role/spec changes
- UI scale / display changes
- Unit flags/faction/name
- Encounter and challenge mode events

### 6.2 Tick-driven inner loop
Each active plate gets an `OnTickFrame` running `Plater.NameplateTick`.

The tick handles:

- Range
- Threat
- execute-range visuals
- percent text
- auras
- boss-mod auras
- scripts
- castbar tick hooks
- color interpolation
- health animation

Plater also spreads work based on FPS using `Plater.FPSData` and `EveryFrameFPSCheck`.

This is a performance architecture, not just convenience code.

### 6.3 Settings caching
Plater aggressively copies profile values into local upvalues.

Implication:

- Runtime code avoids repeated deep table reads
- Changing profile data often requires a refresh path
- If we copy patterns from Plater, we also need the refresh discipline that goes with them

## 7. Major Subsystems

### 7.1 Performance Units
`Plater_PerformanceUnits.lua` defines a per-NPC override system with bit flags:

- `THREAT`
- `CAST`
- `AURA`

Meaning:

- Certain high-volume NPCs can selectively skip expensive subsystems
- On `NAME_PLATE_UNIT_ADDED`, Plater marks a unit frame as performance-reduced and can disable aura updates or cast binding

This is an important part of lower-level infrastructure:

- It changes behavior at runtime
- It affects debugging
- It can make a plate look "weird" on purpose for performance reasons

### 7.2 Aura System
`Plater_Auras.lua` is its own subsystem, not a few helper functions.

It handles:

- Unit aura event registration per visible nameplate
- Incremental aura caching keyed by aura instance ID
- Full-scan fallback paths
- Filter evaluation
- Manual and automatic tracking modes
- Special aura detection
- Ghost auras
- Extra auras injected by scripts and mods
- Tooltip display for Plater aura icons
- Optional private aura anchors

Important design choices:

- Uses `C_UnitAuras` heavily on retail and modern clients
- Keeps caches for regular, ghost, and extra auras
- `UnitAuraCacheData` stores `buffs`, `debuffs`, `buffsInOrder`, `debuffsInOrder`, plus change flags and full-update flags
- `UnitAuraEventHandlerData` is the lighter "what needs work next tick" signal
- `Plater.AddToAuraUpdate(unit, unitFrame)` registers a per-unit `UNIT_AURA` listener and forces an initial cache fill
- `UpdateUnitAuraCacheData()` supports full refreshes and incremental added/updated/removed aura-instance updates
- `getUnitAuras()` has a short path for changed instance IDs and a long path for full scans
- `Plater.GetUnitAurasForUnitID()` merges helpful and harmful caches into one map for scripts
- Tooltip display uses `SetUnitBuffByAuraInstanceID` / `SetUnitDebuffByAuraInstanceID` when available and falls back to `SetSpellByID`
- Hides compatibility tooltip only if the tooltip is not forbidden
- Private aura support exists but is currently short-circuited by `if true then return end`, which tells us the feature exists conceptually but is disabled in this inspected build

Second-pass details that matter:

- Ghost auras are spec-scoped reminder icons stored per class/spec in profile data, rebuilt into a `GHOSTAURAS` lookup cache, and only shown on hostile or neutral units in combat, outside self plates, outside performance-unit reductions, and only outside Midnight
- Extra auras are a separate injected-icon pipeline with their own GUID and spell caches so scripts or external tools can request temporary icons without pretending those icons are real unit auras
- Automatic tracking is effectively two systems:
  - non-Midnight: Plater's own rule engine for important, player-cast, other-player, other-NPC, self-cast, dispellable, enrage, crowd-control, and user-listed auras
  - Midnight: much heavier reliance on Blizzard filters such as `IMPORTANT`, `RAID`, `PLAYER`, `CROWD_CONTROL`, `RAID_PLAYER_DISPELLABLE`, and optional mirroring of Blizzard's own visible aura rows
- On Midnight, `getBlizzardDebuffs()` and `getBlizzardBuffs()` can mirror Blizzard aura visibility from the Blizzard `AurasFrame` layout children instead of recomputing every visibility decision independently
- `Plater.RefreshAuras()` forces update flags on all visible plates and then re-applies Masque skins, which shows that skin integration is treated as part of aura-refresh correctness
- `Plater.ConsolidateAuraIcons()` can collapse same-name icons into one visible icon and sum their displayed stacks

### 7.3 Resources
There are really two resource stories:

1. Repositioning Blizzard's class nameplate resource bars
2. Replacing them with a fully Plater-owned resource bar system

`Plater_Resources.lua` and `Plater_Resources_Frames.lua` together handle:

- Spec/class resource capability
- Which resource bar model to use
- Event wiring for power updates
- Plater-owned bar creation
- Blizzard resource-bar hiding
- Anchoring resources either to the target plate or the personal plate

Second-pass correction:

- The inspected code does not use an explicit `C_NamePlate.GetNamePlateForUnit("target", false)` taint-avoidance override here. It uses ordinary nameplate retrieval and then relies on later forbidden/protected checks when hiding Blizzard-owned mechanic bars.

What the subsystem is actually doing:

- `CreateMainResourceFrame()` creates one `PlaterNameplatesResourceFrame` on `UIParent`
- That frame owns three registries:
  - `resourceBars`
  - `allResourceBars`
  - `resourceBarsByEnumName`
- `UpdateResourceFrameToUse()` picks the visual model to use for the player's class/spec and even allows alternate class-resource visuals
- `CanUsePlaterResourceFrame()` is the policy gate: it checks class capability, whether the relevant nameplate exists, spec and form rules, and low-level-class exceptions
- `UpdateMainResourceFrame()` parents the main resource frame to the chosen plate's healthbar, sets anchor, width, scale, strata, and frame level, and enables the right power events
- `UpdateResourceBar()` is the visual switchboard: it hides or shows the right widget row, updates current values, and only hides Blizzard mechanic or alternate power bars if those Blizzard frames are not forbidden

Architecturally, this subsystem is both:

- a Plater-owned class-resource renderer
- a compatibility layer around Blizzard's own class mechanic bars

### 7.4 Boss Mod Support
`Plater_BossModsSupport.lua` integrates with:

- DBM
- BigWigs

It supports:

- Nameplate auras pushed by boss mods
- Timer bars on nameplates
- Alternate castbar rendering
- Important glows

Important second-pass details:

- `Plater.SetAltCastBar()` builds and updates a secondary castbar (`castBar2`) below the main castbar, supports cast and channel modes, custom icon/text/anchors, fade in/out, and reuse of normal castbar hooks
- `Plater.ClearAltCastBar()` and `Plater.StopAltCastBar()` explicitly reset that secondary bar so prediction overlays do not linger
- `RegisterBossModsBars()` captures DBM callbacks such as `DBM_NameplateStart` and `DBM_NameplateUpdate`, storing timer metadata per GUID and flagging that GUID for a boss-mod update pass
- DBM test mode can intentionally fan timer bars out to all currently shown GUIDs
- BigWigs support stores comparable timer metadata in a separate table
- Spell-prediction logic currently attaches alt castbars to the current target plate, which is a practical but intentionally narrower strategy than pretending Plater can always resolve the exact caster safely

Architecturally this shows that Plater treats external encounter data as a first-class input channel, not as an afterthought.

### 7.5 Scripts And Hooks
Plater hosts two extension types:

- Scripts
- Hooks / mods

`Plater_ScriptHelpers.lua` and the scripting section in `Plater.lua` handle:

- Script lookup
- Trigger registration by spell, NPC, or cast
- Compiling code from saved strings
- Global and per-script environments
- Constructor / OnShow / OnUpdate / OnHide / hook execution
- Cleanup on hide
- Hot reload

This makes Plater closer to a runtime platform than to a normal addon.

### 7.6 Plugins
`Plater_Plugins.lua` is a separate plugin installation and options system.

Plugins provide:

- `OnEnable`
- `OnDisable`
- A frame for their options UI
- Persistent enable state in the profile

Callbacks are wrapped in `xpcall`, which is important for safety.

### 7.7 Comms
`Plater_Comms.lua` provides:

- AceComm transport
- serializer/compression layer
- native `C_EncodingUtil` support when available
- fallback to `LibDeflate` / AceSerializer
- script-to-script messages
- profile/data sharing

Incoming handlers are dispatched through a centralized comm handler table and wrapped in `xpcall`.

### 7.8 Public API, Debug, And External Tooling
Plater's outward-facing helper layer is broader than `Plater_API.lua`, but it is still intentionally selective.

Useful examples:

- `Plater_API.lua` only exports a tiny documented helper surface in this build
- `Plater.DebugTargetNameplate()` uses `C_NamePlate.GetNamePlateForUnit("target", issecure())` and defers deep inspection to FrameInspect if installed
- `platerInternal.InstallMDTHooks()` uses `hooksecurefunc(MDT, "UpdateEnemyInfoFrame", ...)` to inject "go to Plater" buttons into Mythic Dungeon Tools for NPC and spell setup

This shows Plater's preferred integration style:

- post-hook another addon's stable redraw point
- add narrowly scoped affordances
- avoid invasive ownership of the other addon's UI

## 8. Lower-Level Utilities And Infrastructure Patterns

### 8.1 Anchor abstraction
`Plater.SetAnchor` is a core utility.

Why it matters:

- Almost every subsystem anchors through config tables
- Frame attachment is consistently data-driven
- This makes layout highly configurable without spreading raw `SetPoint` logic everywhere

### 8.2 CVar ownership and restore logic
Plater treats a specific set of CVars as managed state.

Key functions:

- `SaveConsoleVariables`
- `RestoreProfileCVars`
- `ForceCVars`
- `SafeSetCVar`
- `RestoreCVar`

Notable behavior:

- It saves profile copies of selected CVars
- It records where they were last changed from via callstack parsing
- It restores in a sorted order
- It defers restoration and forcing when in combat
- `SafeSetCVar()` keeps a per-CVar postponed timer table and retries after `0.5` seconds if combat is blocking the write
- On the first safe set, it stores the original value in `profile.cvar_default_cache`
- `RestoreCVar()` uses the same deferred-retry pattern, restores from that cached original value, and then clears the cache entry

This is unusually mature CVar hygiene for a WoW addon.

### 8.3 `TextureLoadingGroupMixin` as a compatibility tool
Plater repeatedly uses `TextureLoadingGroupMixin.AddTexture` and `RemoveTexture` rather than bluntly replacing chunks of Blizzard behavior.

This appears in:

- Castbar visibility behavior
- Show-only-name state handling
- Blizzard option-table behavior
- Midnight compatibility paths

In the concrete `UpdateBaseNameplateOptions()` path, Plater uses these helpers to toggle:

- `hideHealthbar`
- `hideCastbar`
- `colorNameBySelection`
- `colorNameWithExtendedColors`
- `showLevel`

On Midnight, that same function takes a much narrower compatibility path and mostly removes `updateNameUsesGetUnitName` instead of trying to mirror the non-Midnight texture toggles.

This is a subtle but important architectural choice:

- Influence Blizzard behavior with the mechanisms Blizzard already uses
- Avoid reckless mutation of default tables and state

### 8.4 Reusing Blizzard widgets
On retail, Plater reparents Blizzard's `WidgetContainer` into the Plater frame while the plate is active, then returns it on removal.

This is one of the addon's strongest practical anti-taint lessons:

- Reuse Blizzard's widget container
- Do not clone or recreate secure-ish widget behavior yourself unless absolutely necessary

### 8.5 Throttled Tooltip And Localization Work
`Plater.TranslateNPCCache()` is a good example of low-risk, low-pressure boundary work.

It:

- only runs if NPC auto-translation is enabled
- uses `C_TooltipInfo.GetHyperlink("unit:Creature-...")` when available and a hidden tooltip fallback otherwise
- defers itself for `5` seconds if the player is in combat
- processes only up to `10` cached NPCs per pass
- continues through short timers until the backlog is done

This is exactly how addon code should touch tooltip-derived data that is noncritical and potentially noisy:

- chunk it
- do it out of combat
- accept eventual consistency

## 9. Blizzard API And Frame Touchpoints

This is the key boundary map.

### 9.1 Nameplate APIs
- `C_NamePlate.GetNamePlateForUnit`
- `C_NamePlate.GetNamePlates`
- `C_NamePlate.SetNamePlateEnemySize`
- `C_NamePlate.SetNamePlateFriendlySize`
- `C_NamePlate.SetNamePlateSize`
- `C_NamePlate.SetNamePlateFriendlyClickThrough`
- `C_NamePlate.SetNamePlateFriendlyPreferredClickInsets`
- `C_NamePlate.SetNamePlateEnemyPreferredClickInsets`

Midnight-specific:

- `C_NamePlateManager.SetNamePlateSimplified`
- `C_NamePlateManager.SetNamePlateHitTestInsets`

### 9.2 Blizzard driver and mixin hooks
Plater uses `hooksecurefunc` heavily on:

- `NamePlateDriverFrame.SetupClassNameplateBars`
- `NamePlateDriverFrame.OnNamePlateAdded`
- `NamePlateDriverFrame.OnNamePlateRemoved`
- `NamePlateDriverFrame.UpdateNamePlateSize`
- `NamePlateDriverFrame.UpdateNamePlateOptions`
- `NamePlateDriverFrame.namePlateSetInsetFunctions.friendly`
- `NamePlateDriverFrame.namePlateSetInsetFunctions.enemy`
- `NamePlateUnitFrameMixin.UpdateNameClassColor`
- `NamePlateUnitFrameMixin.UpdateIsFriend`
- `NamePlateUnitFrameMixin.OnUnitSet`

This is a strong signal that Plater prefers secure post-hooks over function replacement.

### 9.3 Tooltip APIs
- `C_TooltipInfo.GetHyperlink`
- Hidden `GameTooltip` fallback on classic and older flows

Used for:

- Quest detection
- NPC subtitle detection
- Pet-owner detection
- NPC name localization / translation cache

### 9.4 Aura APIs
- `C_UnitAuras.GetUnitAuras`
- `C_UnitAuras.GetAuraDataByAuraInstanceID`
- `C_UnitAuras.GetAuraDataBySlot`
- `C_UnitAuras.GetAuraDuration`
- `C_UnitAuras.IsAuraFilteredOutByInstanceID`
- `C_UnitAuras.GetAuraDispelTypeColor`
- `C_UnitAuras.AddPrivateAuraAnchor`
- `C_UnitAuras.RemovePrivateAuraAnchor`

### 9.5 Quest APIs
- `C_QuestLog.GetInfo`
- `C_QuestLog.GetNumQuestLogEntries`
- `C_TaskQuest.GetQuestsForPlayerByMapID` or `GetQuestsOnMap`
- `C_TaskQuest.GetQuestInfoByQuestID`

### 9.6 Resource APIs
- `NamePlateDriverFrame.classNamePlateMechanicFrame`
- `NamePlateDriverFrame.classNamePlateAlternatePowerBar`
- `NamePlateDriverFrame.classNamePlatePowerBar`
- Unit power APIs

### 9.7 Unit and combat APIs
Plater relies constantly on:

- `UnitReaction`
- `UnitGUID`
- `UnitClassification`
- `UnitDetailedThreatSituation`
- `UnitThreatSituation`
- `UnitCanAttack`
- `UnitAffectingCombat`
- `UnitIsPlayer`
- `UnitIsQuestBoss`
- `UnitIsGameObject`
- `UnitNameplateShowsWidgetsOnly`
- `UnitIsBattlePet`
- `UnitIsBossMob`
- `UnitIsLieutenant`
- `UnitIsUnit`
- `GetInstanceInfo`
- `GetZonePVPInfo` / `C_PvP.GetZonePVPInfo`

### 9.8 CVar APIs
- `SetCVar`
- `GetCVarBool`
- `GetCVar`
- `SetCVarToDefault`
- `C_CVar.GetCVarBitfield`
- `C_CVar.SetCVarBitfield`

### 9.9 Frame protection APIs
- `InCombatLockdown`
- `frame:IsProtected()`
- `frame:IsForbidden()`
- `CompactUnitFrame_UnregisterEvents`
- `UnregisterAllEvents`

## 10. Quest Mob Detection Deep Dive

This is the most important section for QuestTogether.

### 10.1 How Plater decides whether a unit is a quest unit
Plater does not appear to use a direct quest-objective-to-unit-ID mapping from Blizzard.

Instead it does this:

1. Build a cache of active quest titles
2. Inspect a unit's tooltip
3. Extract quest-related lines
4. Match quest titles found in the tooltip against the quest-title cache
5. Parse progress text from following lines
6. Mark the plate as a quest objective only if at least one relevant objective is unfinished

This is a tooltip-driven inference system.

### 10.2 Building the quest cache
`update_quest_cache` does the following:

- Wipes `Plater.QuestCache`
- Wipes `Plater.QuestCacheCampaign`
- Returns immediately if the player is in an instance
- Adds all active quest titles from the quest log
- On retail, tracks campaign quests separately
- Adds world-quest titles for the current map
- Calls `Plater.UpdateAllPlates()`

Implication:

- Quest scanning is intentionally open-world oriented
- Plater does not even try to maintain quest-title cache in instances

### 10.3 `QuestLogUpdated` is throttled
Quest events do not immediately rebuild the cache every time.

Plater cancels the previous timer and schedules a rebuild with `C_Timer.NewTimer(1, update_quest_cache)`.

That debounce does two useful things:

- Reduces expensive churn
- Smooths over quest-log timing instability

### 10.4 Tooltip source priority
`Plater.IsQuestObjective` uses this priority:

1. Questie tooltip integration if available
2. `C_TooltipInfo.GetHyperlink("unit:" .. guid)` on retail
3. Hidden `GameTooltip` fallback otherwise

This is a mature approach:

- Prefer structured Blizzard tooltip data when available
- Reuse Questie if it already solved some tooltip data problems
- Keep a fallback for older flows

Questie-specific nuance:

- When Questie provides tooltip data, Plater strips color codes, level brackets, and appended quest IDs before matching titles against `Plater.QuestCache`

### 10.5 Secret-value guards
On Midnight, Plater guards GUID access with `issecretvalue`.

Behavior:

- Try `plateFrame[MEMBER_GUID]` if it is not secret
- Else try `unitFrame[MEMBER_GUID]`
- Else return immediately

It also breaks tooltip-line processing if `line.type` becomes secret.

This is exactly the kind of defensive coding we need around tooltip-based logic.

### 10.6 Tooltip-line filtering
Plater does not parse all tooltip lines.

It keeps only lines with types:

- `QuestObjective`
- `QuestTitle`
- `QuestPlayer`

This matters because:

- It narrows the parser to the data it actually cares about
- It avoids treating unrelated tooltip noise as quest state

### 10.7 Parsing logic
After finding a quest title that matches `Plater.QuestCache`, Plater:

- Creates a `questData` object
- Walks following lines
- Detects:
  - `x/y` progress
  - percentage objectives
  - whether the line belongs to the player or a group member
  - whether the quest is finished or unfinished
- Stops scanning that block if it hits the threat tooltip marker

It stores:

- `questName`
- `questText`
- `finished`
- `groupQuest`
- `groupFinished`
- `amount`
- `groupAmount`
- `total`
- `yourQuest`
- `isCampaignQuest`

Important behavior:

- `namePlateIsQuestObjective` only becomes true if the unit belongs to a quest and at least one matched objective is unfinished
- Finished quest text alone is not enough
- If the player is grouped, Plater tries to infer ownership and group progress from tooltip structure rather than from a direct unit-to-quest API
- If the tooltip block is not marked as a group quest, Plater normalizes `yourQuest = true` for that `questData` entry

### 10.8 What gets cached on the plate
Plater always builds `QuestInfo`; when unfinished quest data exists it also writes the scalar quest fields:

- `QuestAmountCurrent`
- `QuestAmountTotal`
- `QuestText`
- `QuestName`
- `QuestIsCampaign`

It mirrors this onto both `plateFrame` and `unitFrame` so scripts can consume it.

### 10.9 Where quest detection is used
Plater uses this result in several places:

- Enemy NPC coloring in open world
- Friendly NPC display policy in open world
- Quest indicator display

Behavior split:

- Enemy NPC quest scan is gated to open-world hostile NPC plates
- Friendly NPC quest behavior is also open-world gated
- Enemy NPCs can also get a quest indicator from `UnitIsQuestBoss`
- Friendly NPCs use the cached `namePlateIsQuestObjective` flag for their quest badge

### 10.10 Important limitations of Plater's approach
This is a powerful but imperfect system.

Limits:

- It is title-based, not quest-ID-to-unit mapping
- It depends on tooltip structure
- It is skipped in instances
- It can be sensitive to localization and third-party tooltip shaping
- It infers group progress from tooltip text, which is clever but brittle

For QuestTogether, that means:

- Plater is a great source of defensive tooltip-scanning patterns
- It is not proof that tooltip-driven quest detection is ideal as a primary architecture

## 11. Combat, Raid, Dungeon, PvP, And Arena Behavior

### 11.1 Combat lockdown policy
Plater repeatedly uses the same rule:

- If a risky UI or CVar operation would happen in combat, defer it

Important combat-gated functions include:

- `RestoreProfileCVars`
- `ForceCVars`
- `ZONE_CHANGED_NEW_AREA`
- `SetNamePlatePreferredClickInsets`
- `UpdatePlateClickSpace`
- `SafeSetCVar`
- `RestoreCVar`
- initial options-panel creation outside the open world

This is one of the strongest safe-coding patterns in the addon.

### 11.2 What happens on `PLAYER_REGEN_DISABLED`
Plater:

- Marks player-in-combat state
- Refreshes auto toggles
- Refreshes the tank cache
- Updates all plates
- Schedules combat-enter hooks
- Refreshes last-combat capture tables
- Caches friendly group GUIDs for affiliation checks

### 11.3 What happens on `PLAYER_REGEN_ENABLED`
Plater:

- Clears combat state
- Refreshes auto toggles for leave-combat state
- Clears no-combat plate state
- Refreshes tank cache
- Updates colors and plates
- Delays option-panel open requests until combat has fully ended

### 11.4 Zone classification
`ZONE_CHANGED_NEW_AREA` updates:

- `Plater.ZonePvpType`
- `Plater.ZoneInstanceType`
- `Plater.ZoneName`
- `IS_IN_OPEN_WORLD`
- `IS_IN_INSTANCE`

It then:

- Refreshes all plates
- Runs auto-toggle logic
- Refreshes battleground player-role cache

### 11.5 Raid and dungeon behavior
Notable behaviors:

- Quest cache rebuild is skipped in instances
- Quest color / quest objective scan is effectively an open-world feature
- Auto-toggle can hide enemy player pets and totems in party/raid
- NPC name cache is populated for hostile NPCs found in raid, party, or scenario
- Some Blizzard nameplate paths are explicitly treated as secure in dungeon contexts
- Plater does not globally disable itself in raids or dungeons; instead it shifts into more defensive secure/forbidden-frame handling when Blizzard restricts normal plate access
- The options panel will refuse to build itself during combat if it is not already loaded and the player is not in the open world; Plater stores the request and reopens it after combat

### 11.6 Battleground and arena behavior
Plater has explicit PvP logic:

- It builds BG and arena player caches from battlefield score data and arena-opponent-spec APIs
- It uses those caches for faction/spec/role information
- Enemy faction indicators are intentionally hidden in BGs and arenas because they are considered low value there
- Enemy spec icons are normally suppressed during combat unless the config says otherwise
- Enemy players can be treated as effectively "in combat" for size logic in PvP and arena
- Auto-toggle has explicit `arena` policy buckets that are also reused for battleground `pvp` instances

### 11.7 Auto-toggle policy
`RefreshAutoToggle` is the central zone-policy engine.

It supports separate behaviors for:

- `party`
- `raid`
- `arena`
- `world`
- `cities`

And it manages:

- Friendly nameplates
- Enemy nameplates
- Stacking mode
- Always-show mode
- Combat-only toggle behavior
- Dungeon/raid pet and totem hiding

Important nuance:

- The pet/totem hide logic only runs out of combat, which is a deliberate stability choice

This is not just a cosmetic system. It is a policy engine for nameplate mode.

## 12. Taint And Secure-UI Precautions

This is the part we most want to learn from.

### 12.1 Guard, early return, retry
Plater rarely tries to force risky operations through. It prefers:

- check
- bail out
- retry later

This shows up in combat gating, tooltip secret-value gating, and secure-frame fallbacks.

### 12.2 Do not write into Blizzard-owned members
This is the clearest explicit taint lesson in the addon.

If a Blizzard frame member may later exist in a protected context:

- do not stash custom state there

Use:

- your own frame
- your own side table
- your own namespace

### 12.3 Prefer `hooksecurefunc`
Plater hooks Blizzard code far more often than it replaces it.

That lowers the chance of taint and makes Blizzard behavior easier to track.

### 12.4 Treat forbidden frames as normal
Plater repeatedly checks `IsForbidden()` before mutating Blizzard-owned frames.

This shows up in:

- Blizzard resource bars
- alternate power bars
- compatibility tooltip hiding
- Midnight `SetAlpha` hook behavior

### 12.5 Avoid secure attachment when possible
The stronger verified rule is slightly different than the first pass suggested:

- retrieve the relevant Blizzard plate normally
- then guard every mutation of Blizzard-owned helper frames with protection and forbidden checks

Plater follows that pattern more consistently than it relies on special retrieval flags.

### 12.6 Reuse Blizzard components
Plater reuses:

- Blizzard nameplate existence
- Blizzard widget containers
- Blizzard class resource bars when useful
- Blizzard tooltip data structures

This is safer than rebuilding everything from scratch.

### 12.7 Unregister Blizzard events when hiding Blizzard visuals
When Plater fully owns the visible UI, it can unregister Blizzard events from the hidden frame paths.

That reduces redundant work and avoids weird dual-ownership states.

### 12.8 Script/plugin/comms isolation
Plater centralizes error handling and wraps extension execution with `xpcall`.

Special behavior:

- If a secret-value error occurs in a script context, Plater can mark that script as temporarily disabled

That is a very practical production defense.

### 12.9 Split layout work from volatile data work
Plater explicitly contains commentary and structure intended to keep layout changes away from taint-sensitive value paths.

This is a subtle but valuable pattern:

- do not mix frame layout mutation with unstable secret-value reads if you can separate them

The clearest concrete example is `platerInternal.UpdatePercentTextLayout()`, whose code comment explicitly says it exists to avoid manipulating secrets and layout in a taint path. Font, anchor, height, and alpha setup are split away from the volatile health-text update path.

The same mindset shows up in the designer/preview code, which creates a separate safe percent-text path instead of assuming preview health reads behave like normal runtime reads.

### 12.10 Prefer chunked, deferred boundary work
Plater repeatedly treats expensive or potentially noisy boundary work as eventually consistent rather than immediate.

Examples:

- quest cache rebuild is throttled through a one-second timer
- NPC translation work chunks itself over time
- options-panel opening is deferred until combat ends when initial construction would be risky

This is a core anti-taint mindset:

- do less right now
- do the risky thing later
- keep live combat paths boring

## 13. What A New Developer Should Read First

If someone joins the project and wants to really understand Plater:

1. Read the TOC
2. Read `Definitions.lua`
3. Read `Plater_Data.lua`
4. Read the event registration and lifecycle sections in `Plater.lua`
5. Read `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, and `OnRetailNamePlateShow`
6. Read `UpdatePlateFrame`
7. Read `RefreshAutoToggle`
8. Read `IsQuestObjective` and `update_quest_cache`
9. Read `Plater_Auras.lua`
10. Read `Plater_Resources.lua`
11. Read `Plater_BossModsSupport.lua`
12. Read the scripting section

That order reflects how the runtime actually works.

## 14. Practical Rules QuestTogether Should Copy

1. Keep Blizzard frame ownership and addon state ownership separate.
2. Never add custom data to Blizzard frame members unless you are certain they are not Blizzard-owned and not reused in protected contexts.
3. Use explicit wrappers for risky nameplate/frame access and centralize forbidden/protected checks there.
4. If a call can fail in combat or on a secure frame, design the retry path up front.
5. Prefer structured tooltip APIs over raw tooltip text when possible.
6. When tooltip parsing is necessary, filter line types aggressively and treat metadata as untrusted.
7. Keep quest-detection logic separate from core plate lifecycle so it can be disabled or replaced without destabilizing nameplates.
8. Reuse Blizzard widget and resource infrastructure where possible instead of forking it.
9. Use `hooksecurefunc` and event hooks rather than function replacement.
10. Isolate extension points with `xpcall` and consider temporary-disable logic for repeated secret-value failures.
11. Maintain clear per-zone policy code so raid, dungeon, PvP, arena, and open-world behavior is explicit rather than accidental.
12. Build teardown paths as carefully as setup paths because nameplates are constantly recycled.

## 15. Audit Checklist For QuestTogether

- [ ] Are we storing any custom state on Blizzard frames or Blizzard-owned members?
- [ ] Do we guard tooltip GUIDs, serials, and line metadata before using them?
- [ ] Do we have one reusable combat-defer path for risky UI mutations?
- [ ] Are all Blizzard frame mutations gated by `IsForbidden()` where appropriate?
- [ ] Do we have explicit open-world versus instance policy for quest logic?
- [ ] Are target-nameplate attachments done through a path that avoids secure-frame taint when possible?
- [ ] Are add/remove lifecycle paths symmetrical?
- [ ] Do we separate data refresh from layout mutation in taint-sensitive paths?
- [ ] Are external code paths such as plugins, scripts, or comm handlers isolated?
- [ ] Do we reuse Blizzard widget/resource infrastructure where reuse is safer than replacement?

## Closing Assessment

Plater is worth studying because it has already absorbed many years of painful nameplate-edge-case knowledge:

- secure and forbidden plates
- tooltip fragility
- combat lockdown
- CVar ownership
- zone-specific policy
- frame recycling
- extension-safety boundaries

The most important lesson is not any single API call. It is the architectural posture:

- Blizzard owns the dangerous objects
- Plater wraps, reuses, defers, and carefully overlays them
- State is cached aggressively
- Risky work is isolated
- Open-world-only features stay open-world-only

If QuestTogether adopts that same posture, especially around tooltip quest detection and nameplate attachment, we should be able to eliminate a large class of taint-prone designs before they ship.
