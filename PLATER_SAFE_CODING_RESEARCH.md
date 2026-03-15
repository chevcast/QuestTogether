# Plater Safety Research (Anti-Taint / Secure UI Practices)

## Scope
- Source inspected: `/mnt/d/Battle.net/World of Warcraft/_retail_/Interface/AddOns/Plater`
- Focus areas:
  - Secret value handling (`issecretvalue`)
  - Tooltip scanning safety
  - Combat lockdown handling (`InCombatLockdown`)
  - Protected/forbidden frame handling
  - Error isolation boundaries (`xpcall` / guarded execution)
  - Patterns relevant to QuestTogether nameplates + tooltip-based quest detection

## High-Level Takeaways
- Plater treats taint prevention as a first-class concern and adds guards at almost every boundary where Blizzard may return protected/secret values.
- Their core pattern is "guard + early return + deferred retry" rather than pushing through risky calls.
- Tooltip scanning is cautious: they gate GUID inputs, filter tooltip line types, and stop parsing when line metadata is secret.
- They avoid mutating Blizzard-owned sensitive members when they know those frames may be recycled into protected contexts.
- They isolate user/plugin/script code errors with centralized handlers and disable problematic scripts when secret-value errors appear.

## 1) Secret Value Handling Patterns

### 1.1 Guard inputs before using them
- `Plater.lua:11130-11140` (`Plater.IsQuestObjective`)
  - Chooses GUID only if not secret.
  - Falls back to `unitFrame` GUID if primary is secret.
  - Returns early when both are secret.
- `Plater.lua:11100-11107` (`Plater.GetActorSubName`)
  - Same guarded GUID selection before tooltip hyperlink.
- `Plater.lua:10898-10923` (`Plater.ForceFindPetOwner`)
  - Returns early when `serial` or parsed tooltip text is secret.

### 1.2 Guard tooltip metadata before branching
- `Plater.lua:11172-11177`
  - Iterates `tooltipData.lines`.
  - Breaks scan if `line.type` is secret.
  - Only processes specific line types (`QuestObjective`, `QuestTitle`, `QuestPlayer`).

### 1.3 Guard values before arithmetic/layout math
- `libs/DF/cooltip.lua:1394-1411`
  - Reads text/icon widths/heights.
  - Computes `lengthIsSecret`.
  - Skips width/height math entirely when any metric is secret.
- `libs/DF/cooltip.lua:1481-1483`
  - Avoids `SetValue` when status bar input is secret.

### 1.4 Defensive fallback for environments without secret API
- `libs/DF/cooltip.lua:18`
  - `local issecretvalue = issecretvalue or function() return false end`
  - Keeps code path stable across clients/builds.

## 2) Tooltip Scanning Behavior (Deep Dive)

### 2.1 Mainline-first: `C_TooltipInfo.GetHyperlink` before hidden tooltip frames
- `Plater.lua:11170-11179` (quest tooltip scan)
  - Uses structured tooltip data first.
- `Plater.lua:10587-10599` (creature name lookup)
  - Uses `C_TooltipInfo` first, then hidden `GameTooltip` fallback.
- `Plater.lua:10899-10905` (pet owner scan)
  - Uses `C_TooltipInfo` lines in mainline.

### 2.2 Hidden tooltip fallback is isolated and non-visual
- `Plater.lua:11116-11118` and `11181-11183`
  - Creates hidden tooltip only when needed.
  - Uses `SetOwner(WorldFrame, "ANCHOR_NONE")`.

### 2.3 Scan only relevant tooltip lines
- `Plater.lua:11174-11177`
  - Explicit allowlist of quest-related line types.
  - Avoids processing unrelated tooltip lines.

### 2.4 Throttle re-scans to reduce edge timing failures
- `Plater.lua:11384-11389`
  - `QuestLogUpdated` cancels prior timer and re-schedules scan with `C_Timer.NewTimer(1, ...)`.
  - Lowers churn and race conditions around rapidly changing quest data.

### 2.5 Optional integration path (Questie) still normalizes text
- `Plater.lua:11161-11168`, `11200-11205`
  - Uses Questie tooltip source if present.
  - Sanitizes color/format tokens before matching.

## 3) Combat Lockdown Strategy

Plater repeatedly follows this pattern:
1) Detect combat lockdown.
2) Do not execute risky code.
3) Reschedule with timer.

Examples:
- `Plater.lua:1679-1681` (`RestoreProfileCVars`)
- `Plater.lua:2525-2527` (`ZONE_CHANGED_NEW_AREA` handler)
- `Plater.lua:4781-4783` (`ForceCVars`)
- `Plater.lua:5306-5314` (`SetNamePlatePreferredClickInsets`)
- `Plater.lua:6693-6695` (`UpdateSelfPlate`)
- `Plater.lua:10979-10981` (`SetCVarsOnFirstRun`)
- `Plater.lua:11585-11590` (`SafeSetCVar`)
- `Plater.lua:11624-11628` (`RestoreCVar`)

They also disable unsafe option widgets during combat in framework UI code:
- `libs/DF/buildmenu.lua:1929-1958`

## 4) Protected/Forbidden Frame Precautions

### 4.1 Do not attach to secure frames when avoidable
- `Plater.lua:5193`
  - `C_NamePlate.GetNamePlateForUnit("target", false)` with explicit comment:
  - "don't attach to secure frames to avoid tainting!"

### 4.2 Check `IsForbidden()` before frame mutations
- `Plater.lua:3706-3708`
  - Hooked `SetAlpha` callback exits if frame is forbidden.
- `Plater_Resources.lua:857-862`
  - Hides Blizzard resource/alternate frames only if not forbidden.
- `Plater_Auras.lua:910-911`
  - NamePlate tooltip hide path exits if tooltip is forbidden.

### 4.3 Treat secure/forbidden retrieval failures as normal
- `Plater.lua:5130-5153`
  - Hooks check for `not plateFrame` ("secure in dungeon") and use fallback behavior.
- `Plater.lua:3607-3620`
  - If plate retrieval fails, tries forbidden path and returns early.

## 5) Known Taint Avoidance in Data Ownership

Plater has an explicit historical taint fix:
- `Plater.lua:3897-3899`
  - They stopped writing to `plateFrame[MEMBER_UNITID]` because that member belongs to Blizzard nameplates and caused taint when frames were recycled into protected contexts.

This is one of the most important lessons: avoid mutating Blizzard-owned fields on frames that can become protected later.

## 6) Error Isolation Boundaries

### 6.1 Centralized handler with secret-error response
- `Plater.lua:12044-12051`
  - Detects secret-value-related error strings.
  - Sets `tmpDisabled` on script object to stop repeated failures.

### 6.2 Runtime script execution via `xpcall`
- `Plater.lua:12121-12267`, `12273-12310`
  - Constructor/OnShow/OnUpdate/OnHide/hook paths all wrapped.
- `Plater.lua:12197`, `12219`, `12243`, `12301`
  - Early return if script marked `tmpDisabled`.

### 6.3 Plugin/comms execution isolation
- `Plater_Plugins.lua:66-79`
  - Plugin enable/disable callbacks wrapped in `xpcall`.
- `Plater_Comms.lua:163-165`
  - Incoming comm handler wrapped in `xpcall`.

## 7) Hooking Strategy

- Plater generally uses `hooksecurefunc` into Blizzard systems instead of replacing Blizzard functions:
  - `Plater.lua:5295-5302` (`UpdateNamePlateOptions`)
  - `Plater.lua:3703-3715` (`Show`, `SetAlpha`)
  - `Plater.lua:5088-5158` (`OnNamePlateAdded/Removed`, mixin methods)

This lowers taint risk versus direct overrides.

## 8) Layout/Rendering Safety Separation

- `Plater.lua:8483-8496`
  - Explicitly splits percent-text layout updates into separate function to avoid "manipulating secrets and layout in a taint path."

This "separate layout from volatile data updates" pattern is useful when values may become protected mid-flow.

## 9) Historical Signals From Changelog

- `Plater_ChangeLog.lua:485`
  - "Fixing taint issues with widgets by reusing blizzards WidgetContainer."
- `Plater_ChangeLog.lua:1011`
  - Resource-on-target changes to avoid forbidden/protected plate issues.

The team appears to iterate quickly on taint regressions and encode those lessons into architecture over time.

## 10) Practical Rules We Should Copy Into QuestTogether

1. Wrap all secret checks behind one local helper and gate every untrusted value before `tonumber`, arithmetic, string ops, `SetWidth`, `SetValue`, etc.
2. Treat tooltip scan inputs/metadata as untrusted:
   - Guard GUID/serial.
   - Filter line types.
   - Break/return on secret metadata.
3. Never mutate Blizzard-owned frame members that may be reused in protected contexts.
4. Any protected-risk call should be combat-gated with deferred retry (single reusable queue helper preferred).
5. Check `frame:IsForbidden()` before mutating Blizzard frames.
6. Prefer `hooksecurefunc` over direct function replacement.
7. Isolate extension/plugin/comms callbacks with `xpcall`; avoid wrapping core logic unnecessarily.
8. Split style/layout updates from dynamic data refresh paths.
9. Throttle high-frequency refresh work that depends on dynamic Blizzard state.
10. Consider toggling off repeatedly failing extension paths when secret-value errors are detected to prevent spam loops.

## 11) Audit Checklist for QuestTogether (Derived From Plater)

- [ ] Every tooltip-driven code path: input GUID/serial guarded?
- [ ] Every tooltip line parse: line metadata guarded before branch?
- [ ] Any `tonumber` on values that can come from tooltip/comms/events?
- [ ] Any arithmetic/layout calls (`SetWidth`, `SetValue`, position math) fed by unguarded data?
- [ ] Any mutations on Blizzard frame members/tables that could be protected later?
- [ ] Any map/nameplate/world frame interactions missing `InCombatLockdown` gate?
- [ ] Any Blizzard frame mutation missing `IsForbidden` check?
- [ ] Any external callback (comms/plugins/user scripts) not wrapped by an isolation boundary?
- [ ] Any high-frequency refresh path missing throttle/debounce?
- [ ] Any taint/error reporting path converting protected values before guard?

## Notes
- Plater still has user-facing error messaging in some contexts (`Plater:Msg` in handler), but the key anti-taint behavior is the guard/defer architecture and strong secret-value gating.
- Their strongest protective patterns appear in the exact areas where QuestTogether is currently seeing issues: tooltip parsing, nameplate updates, and runtime UI mutation under combat/secure constraints.
