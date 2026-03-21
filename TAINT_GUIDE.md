# TAINT_GUIDE

## Scope

This guide is based on a direct read of Blizzard interface source under:

`/mnt/d/Battle.net/World Of Warcraft/_retail_/BlizzardInterfaceCode`

For modern addon-facing secure behavior, the primary source of truth is the addon-loaded restricted stack in:

- `Interface/AddOns/Blizzard_RestrictedAddOnEnvironment/Blizzard_RestrictedAddOnEnvironment.toc:1-15`

That TOC loads:

- `RestrictedInfrastructure.lua`
- `RestrictedEnvironment.lua`
- `RestrictedExecution.lua`
- `RestrictedFrames.lua`
- `SecureHandlers.lua`
- `SecureStateDriver.lua`
- `SecureHoverDriver.lua`
- `SecureGroupHeaders.lua`

Older copies of parts of this stack still exist under `Blizzard_FrameXML`. Where behavior differs, this guide prioritizes the `Blizzard_RestrictedAddOnEnvironment` versions because those are the modern addon-facing copies Blizzard is explicitly loading.

## Short Version

Taint is not just "combat lockdown."

In modern WoW UI code, Blizzard is protecting at least five related things:

- execution provenance: secure vs insecure code paths
- protected objects and protected functions
- explicitly protected frames vs frames that are only incidentally protected
- forbidden frames that Blizzard wants quarantined from addon mutation
- secret values, secret tables, and secret object aspects

When Blizzard detects unsafe crossover between those worlds, it does one or more of the following:

- blocks the action
- forces execution back to insecure code
- scrubs values to `nil`
- refuses to create or resolve frame handles
- prevents writing secret values into restricted tables or attributes
- marks referenced frames forbidden

Stable addons avoid taint by treating Blizzard secure code as a hard boundary, not as a normal API surface.

## The Right Mental Model

### 1. Taint is provenance

Blizzard code cares about where execution and data came from, not just what the values are.

That is why the API surface includes functions like:

- `canaccessallvalues` (`FrameScriptDocumentation.lua:20-35`)
- `canaccesssecrets` (`FrameScriptDocumentation.lua:37-46`)
- `canaccesstable` (`FrameScriptDocumentation.lua:48-63`)
- `canaccessvalue` (`FrameScriptDocumentation.lua:65-80`)
- `issecretvalue` (`FrameScriptDocumentation.lua:243-259`)
- `issecrettable` (`FrameScriptDocumentation.lua:227-242`)
- `scrubsecretvalues` (`FrameScriptDocumentation.lua:331-346`)
- `scrub` (`FrameScriptDocumentation.lua:348-363`)
- `secretwrap` (`FrameScriptDocumentation.lua:383-398`)
- `CreateSecureDelegate` (`FrameScriptDocumentation.lua:98-113`)
- `securecallmethod` (`FrameScriptDocumentation.lua:400-416`)

The important implication: a value that is harmless in ordinary Lua can still be unusable if it is secret, came through a tainted path, or lives inside a tainted container.

### 2. Protected is not the same as explicitly protected

`IsProtected()` returns two booleans:

- `isProtected`
- `isProtectedExplicitly`

See `SimpleScriptRegionAPIDocumentation.lua:492-505`.

This distinction matters. Blizzard's restricted infrastructure only creates certain secure affordances for explicitly protected frames:

- frame handles for protected-only access (`RestrictedInfrastructure.lua:113-141`)
- managed restricted environments (`RestrictedInfrastructure.lua:600-637`)
- secure header wrapping and execution (`SecureHandlers.lua:539-542`, `SecureHandlers.lua:669-671`, `SecureHandlers.lua:734-736`)

If code only checks "is this protected somehow?" and ignores "is this explicitly protected?", it will misread how Blizzard gates secure behavior.

### 3. Forbidden is a quarantine bit

Blizzard exposes `IsForbidden` and `SetForbidden` directly on frame script objects:

- `SimpleFrameScriptObjectAPIDocumentation.lua:83-94`
- `SimpleFrameScriptObjectAPIDocumentation.lua:128-144`

Forbidden is not just "currently blocked in combat." It is Blizzard saying "addon code must not operate on this object through the usual paths."

Examples:

- `Blizzard_NamePlateUnitFrame.lua:41-45` marks the hit test frame forbidden so addons cannot arbitrarily modify it.
- `CallbackRegistry.lua:24-49` creates a forbidden helper frame as a barrier.
- `TooltipDataHandler.lua:111-125` does the same for insecure tooltip callbacks.

### 4. Secrets are now part of the core security model

Many APIs are tagged with secret argument and secret return metadata.

Examples:

- tooltip frame APIs:
  - `SetMinimumWidth` is `AllowedWhenUntainted` (`FrameAPITooltipDocumentation.lua:81-91`)
  - `SetPadding` is `AllowedWhenUntainted` (`FrameAPITooltipDocumentation.lua:93-105`)
  - `SetText` is `AllowedWhenTainted` (`FrameAPITooltipDocumentation.lua:107-121`)
- tooltip data getters:
  - `GetMountBySpellID` is `AllowedWhenTainted` (`TooltipInfoDocumentation.lua:627-642`)
  - `GetSpellByID` is `AllowedWhenTainted` (`TooltipInfoDocumentation.lua:1043-1060`)
  - `GetUnitAura` is `SecretWhenUnitAuraRestricted` and `AllowedWhenUntainted` (`TooltipInfoDocumentation.lua:1195-1213`)
  - `GetUnitAuraByAuraInstanceID` is `SecretWhenInCombat` and `AllowedWhenUntainted` (`TooltipInfoDocumentation.lua:1215-1233`)
  - `GetUnitBuffByAuraInstanceID` is `SecretWhenUnitAuraRestricted` and `AllowedWhenTainted` (`TooltipInfoDocumentation.lua:1253-1271`)
  - `GetUnitDebuffByAuraInstanceID` is `SecretWhenUnitAuraRestricted` and `AllowedWhenTainted` (`TooltipInfoDocumentation.lua:1291-1300`)

This metadata is not limited to tooltip APIs. Generated docs show secret-argument and secret-return behavior across broader systems too. For example:

- `ClosestGameObjectPosition` has `SecretReturns = true` and `SecretArguments = "AllowedWhenUntainted"` (`UnitDocumentation.lua:34-50`)
- `ClosestUnitPosition` has `SecretReturns = true` and `SecretArguments = "AllowedWhenUntainted"` (`UnitDocumentation.lua:53-69`)

This is why an addon can "work fine" outside of classic combat-lockdown cases and still trip security faults around aura, tooltip, or restricted-object access.

## Restriction States Are Broader Than Combat

`InCombatLockdown()` is still a major gate, but Blizzard's current docs expose a wider restriction system through `C_RestrictedActions`:

- `CheckAllowProtectedFunctions` (`RestrictedActionsDocumentation.lua:10-27`)
- `GetAddOnRestrictionState` (`RestrictedActionsDocumentation.lua:28-43`)
- `IsAddOnRestrictionActive` (`RestrictedActionsDocumentation.lua:55-69`)

Restriction types are:

- `Combat` (`RestrictedActionsConstantsDocumentation.lua:25-31`)
- `Encounter`
- `ChallengeMode`
- `PvPMatch`
- `Map`

Restriction states are:

- `Inactive`
- `Activating`
- `Active`

See `RestrictedActionsConstantsDocumentation.lua:5-33`.

Blizzard also exposes and surfaces restriction failures through events:

- `ADDON_ACTION_BLOCKED`
- `ADDON_ACTION_FORBIDDEN`
- `MACRO_ACTION_BLOCKED`
- `MACRO_ACTION_FORBIDDEN`
- `ADDON_RESTRICTION_STATE_CHANGED`

See `RestrictedActionsDocumentation.lua:72-128` and `UIParent.lua:1680-1687`.

Practical consequence: code that only asks `InCombatLockdown()` is incomplete. Combat is one restricted state, not the whole system.

## Object Secret Controls And Table Security Options

The generated API docs also expose object-level and table-level secret controls that are easy to miss if you only read the secure header code.

On frame script objects, Blizzard documents:

- `HasSecretValues` (`SimpleFrameScriptObjectAPIDocumentation.lua:69-80`)
- `IsPreventingSecretValues` (`SimpleFrameScriptObjectAPIDocumentation.lua:114-125`)
- `SetPreventSecretValues` as a protected function (`SimpleFrameScriptObjectAPIDocumentation.lua:136-145`)
- `SetToDefaults`, with the note that it resets script-accessible values and clears secret state if possible (`SimpleFrameScriptObjectAPIDocumentation.lua:147-155`)

On the Lua side more generally, Blizzard exposes `SetTableSecurityOption` with:

- `DisallowTaintedAccess`
- `DisallowSecretKeys`
- `SecretWrapContents`

See `FrameScriptDocumentation.lua:429-440` and `FrameScriptDocumentation.lua:490-500`.

I did not find direct Lua-side uses of `SetTableSecurityOption` in Blizzard addon code during this validation pass, but the documented API matters because it shows the engine's security model includes configurable table-level taint and secret policies, not just protected frames and snippets.

## The Secure Stack Blizzard Actually Uses

### Secure frame templates

The root secure template is:

- `SecureFrameTemplate` with `protected="true"` (`SecureTemplatesBase.xml:3-10`)

Important descendants include:

- `SecureActionButtonTemplate` (`SecureTemplates.xml:3-10`)
- `SecureUnitButtonTemplate` (`SecureTemplates.xml:20-25`)

These are the starting point for secure buttons, headers, attribute drivers, and restricted snippets.

### Core secure modules

At a high level, Blizzard's secure addon stack splits responsibilities like this:

- `RestrictedInfrastructure.lua`: frame handles, restricted tables, managed environments
- `RestrictedEnvironment.lua`: what restricted snippets are allowed to call
- `RestrictedExecution.lua`: how restricted snippets are compiled and run
- `RestrictedFrames.lua`: what frame-handle methods restricted snippets can use
- `SecureHandlers.lua`: secure wrapper API for headers and snippets
- `SecureStateDriver.lua`: macro-conditional state drivers and visibility/unit watching
- `SecureHoverDriver.lua`: secure auto-hide/hover behavior
- `SecureGroupHeaders.lua`: secure unit/aura header logic

If you want to understand why secure code allowed one thing and blocked another, these are the files that matter first.

## Restricted Snippets Are Not General Lua

The first common misunderstanding is thinking secure snippets are just ordinary Lua with a magic environment. They are not.

### Hard restrictions at compile time

`BuildRestrictedClosure` explicitly rejects:

- the `function` keyword (`RestrictedExecution.lua:59-62`, `RestrictedExecution.lua:69-72`)
- direct table literal creation with `{}` (`RestrictedExecution.lua:64-67`)
- invalid signature characters (`RestrictedExecution.lua:74-77`)

It compiles the body with `loadstring_untainted` and then wraps execution as:

- `def(SelfScrub(self), scrub(...))` (`RestrictedExecution.lua:80-99`)

That means:

- snippet arguments are scrubbed before entry
- `self` is scrubbed before entry
- nested Lua features Blizzard considers dangerous are simply not available

### Restricted snippets must use restricted helpers

Because direct table literals are blocked, restricted code is expected to use restricted helpers such as:

- `newtable`
- `copytable`
- restricted `pairs`, `ipairs`, `next`, `unpack`
- restricted `table.insert`, `table.remove`, `table.sort`, `table.wipe`

See `RestrictedExecution.lua:278-296`, `RestrictedExecution.lua:325-338`, and `RestrictedInfrastructure.lua:572-589`.

### The restricted environment is stack-managed

`CreateRestrictedEnvironment` maintains:

- a current working environment
- a current control handle
- a stack for nested calls

See `RestrictedExecution.lua:183-253`.

Lookups resolve from:

- the base environment first
- then the working table
- with special handling for `control`

Writes go into the working table (`RestrictedExecution.lua:191-206`).

That is why snippet execution is tightly scoped to a particular protected owner and environment rather than having broad access to global Lua state.

### CallRestrictedClosure has hard entry conditions

`CallRestrictedClosure` rejects calls when:

- the owning frame is forbidden (`RestrictedExecution.lua:448-453`)
- the working environment is not a writable restricted table (`RestrictedExecution.lua:455-458`)
- the caller is insecure (`RestrictedExecution.lua:473-476`)

Only after those checks does it:

- push the environment
- increment execution depth
- track referenced frames
- execute via `pcall`
- pop the environment

See `RestrictedExecution.lua:421-486`.

### Restricted code cannot smuggle arbitrary values back out

Blizzard's own comment is explicit: functions exposed to this environment must not return arbitrary tables, functions, or userdata unless Blizzard has intentionally wrapped them (`RestrictedExecution.lua:265-270`).

That design shows up everywhere else in the stack.

## Restricted Tables And Managed Environments

### Restricted tables are proxied userdata, not ordinary tables

Restricted tables are stored behind proxies in `LOCAL_Restricted_Tables` (`RestrictedInfrastructure.lua:169-217`).

Allowed values are very narrow:

- `string`
- `number`
- `boolean`
- `nil`
- other restricted-table proxies
- frame handles

Anything else errors (`RestrictedInfrastructure.lua:188-207`).

### Secret keys and values are explicitly banned

Restricted table assignment fails if either the key or value is secret:

- `RestrictedInfrastructure.lua:205-207`

`table.insert` and `table.remove` also reject secret indices:

- insert: `RestrictedInfrastructure.lua:493-502`
- remove: `RestrictedInfrastructure.lua:521-526`

This is a critical modern hardening change. Blizzard is not only protecting code flow; it is preventing secret-bearing data structures from even being built inside restricted execution.

### Read-only proxies are used when Blizzard must expose table contents safely

Blizzard creates read-only proxies for restricted tables so values can be returned without granting unsafe mutation:

- proxy setup: `RestrictedInfrastructure.lua:219-285`
- read-only `unpack`: `RestrictedInfrastructure.lua:390-414`

### copytable is deep and restricted-aware

`RestrictedTable_copytable` recursively copies nested restricted tables (`RestrictedInfrastructure.lua:556-568`).

That matters because Blizzard now uses `copytable` inside the restricted environment to pull safe table-shaped data inward without letting raw tables flow across the boundary.

### Managed environments only exist for explicitly protected owners

`ManagedEnvironmentsIndex`:

- only allows secure access
- requires a valid frame
- requires the owner to be explicitly protected

See `RestrictedInfrastructure.lua:600-637`.

When Blizzard creates a managed environment, it seeds:

- `_G = e`
- `owner = ownerHandle`

This is a strong signal that snippets are intended to be anchored to a protected owner frame, not treated as free-floating Lua.

## Frame Handles: The Only Safe Way Restricted Code Touches Frames

Frame handles are Blizzard's safe stand-in objects for frames inside restricted execution.

### Handle creation rules

`GetFrameHandle` and its supporting lookup machinery show:

- a given frame maps to a stable handle
- only explicitly protected frames get protected handles
- insecure code cannot create handles

See `RestrictedInfrastructure.lua:92-141`.

### Handle resolution respects protection and lockdown

`GetFrameHandleFrame` and `GetHandleFrame` enforce combat and protection rules:

- protected-only resolution in certain paths
- denial when the frame is not valid for the current restrictions
- referenced frame tracking
- forbidden-frame propagation

See:

- `RestrictedInfrastructure.lua:100-111`
- `RestrictedFrames.lua:69-104`

### Getter methods scrub returns

Most handle getters return `scrub(...)`, for example:

- `GetName` (`RestrictedFrames.lua:109-111`)
- `GetID` (`RestrictedFrames.lua:113-115`)
- `IsShown` (`RestrictedFrames.lua:117-119`)
- `GetRect` (`RestrictedFrames.lua:141-148`)
- `GetAttribute` for non-handle values (`RestrictedFrames.lua:197-207`)
- `GetEffectiveAttribute` for non-handle values (`RestrictedFrames.lua:222-242`)

This is Blizzard preventing arbitrary object graphs, secret values, or unsafe userdata from leaking back into restricted snippets.

### Attribute access is intentionally narrow

`HANDLE:GetAttribute`:

- rejects attribute names starting with `_`
- returns frame handles only if the value is already a valid handle
- otherwise scrubs the result

See `RestrictedFrames.lua:197-207`.

`HANDLE:SetAttribute`:

- rejects `_` names
- only allows primitive values or frame handles

See `RestrictedFrames.lua:520-534`.

That is important. Internal underscore attributes are where much of Blizzard's secure machinery lives. Restricted snippets are intentionally prevented from poking at those raw internals through the generic accessor path.

### Positioning APIs only allow tightly controlled relative frames

`SetPoint` and `SetAllPoints` only allow:

- a protected relative frame handle
- `$screen`
- `$cursor`
- `$parent`

See `RestrictedFrames.lua:444-517`.

Relative frame handles must resolve as protected (`RestrictedFrames.lua:472-478`, `RestrictedFrames.lua:502-507`).

### Show and Hide also maintain statehidden

The restricted handle layer is not blindly forwarding everything. Some calls maintain Blizzard's secure state bookkeeping, such as `statehidden` on visibility changes. This same pattern appears in state drivers and hover drivers.

Relevant areas:

- `RestrictedFrames.lua:399-412`
- `SecureStateDriver.lua:82-88`, `SecureStateDriver.lua:98-105`
- `SecureHoverDriver.lua:167-173`

### CallMethod is deliberately forced insecure

One of the most important lines in the whole secure stack is in `HANDLE:CallMethod`:

- `forceinsecure()` before method lookup and call (`RestrictedFrames.lua:810-819`)

The public wrapper then calls that through `securecall(pcall, ...)` with scrubbed arguments (`RestrictedFrames.lua:824-841`).

Meaning:

- secure snippets can ask Blizzard to call an addon-owned method
- Blizzard intentionally ensures that method does not run securely
- arguments are scrubbed on the way in

This is a massive clue for addon architecture. If secure code needs to notify your addon logic, Blizzard wants it to cross back into insecure addon code through a narrow, scrubbed handoff.

## Forbidden Frames And Forbidden Propagation

Forbidden status is not just checked at the point of use. Blizzard propagates it.

### Restricted execution tracks referenced frames

During restricted execution, Blizzard tracks frames touched through handles:

- `AddReferencedFrame` (`RestrictedExecution.lua:410-414`)

If the owning frame is forbidden at call time, Blizzard propagates forbidden status to those referenced frames:

- `PropagateForbiddenToReferencedFrames` (`RestrictedExecution.lua:401-408`)
- owning-frame check in `CallRestrictedClosure` (`RestrictedExecution.lua:448-453`)

This is why "I only touched a child frame" is not a safe assumption. Once restricted execution intersects forbidden state, Blizzard can widen the quarantine.

### SecureHandlers API also propagates forbidden state

`SecureHandlers.lua` does not merely reject forbidden frames. In some cases it marks other frames forbidden too:

- wrapping with a forbidden header can forbid the target frame (`SecureHandlers.lua:526-529`, `SecureHandlers.lua:664-667`)
- creating a frame ref to a forbidden value can forbid the destination frame (`SecureHandlers.lua:618-621`)

Blizzard is explicitly preventing secure wrapper relationships from being used as a back door around forbidden objects.

### Practical rule

If a Blizzard frame or subframe might be forbidden, treat it as read-mostly or hands-off unless Blizzard's public API explicitly intends you to use it.

Do not assume "it is a frame so I can restyle it" is safe.

### Forbidden can be declared for whole XML subtrees

Forbidden state is not only applied imperatively with `SetForbidden()`. Blizzard also declares entire XML scopes as forbidden:

- `Blizzard_WowTokenUI.xml:3-7`
- `Blizzard_PrivateAurasUI.xml:3-4`

The validation pass also found many more `<ScopedModifier forbidden="true">` uses across secure UI packages such as StoreUI, SimpleCheckout, PingUI, SecureTransferUI, CommunitiesSecure, and HouseEditor.

`PrivateAurasUI.xml` is especially telling because it combines:

- `forbidden="true"`
- `hideFromGlobalEnv="true"`

See `Blizzard_PrivateAurasUI.xml:3-12`.

That is Blizzard explicitly defining UI that should be both forbidden to addons and less discoverable through normal global-environment access.

## SecureHandlers: Blizzard's Secure Wrapper API

`SecureHandlers.lua` is the bridge between secure owner frames and restricted snippets.

### Core execution helpers

The two central execution helpers are:

- `SecureHandler_Self_Execute` (`SecureHandlers.lua:47-60`)
- `SecureHandler_Other_Execute` (`SecureHandlers.lua:62-76`)

They:

- obtain frame handles
- obtain the managed environment
- run the body through `CallRestrictedClosure`

### Wrapper eligibility

Wrapped script snippets only run when:

- not in combat lockdown, or
- the wrapped frame is protected

See `IsWrapEligible` (`SecureHandlers.lua:273-276`).

This is why secure wrappers can still participate around protected frames during combat, but not around arbitrary addon frames.

### Wrap/unwrap/execute/set-frame-ref all go through one protected API frame

Blizzard uses a protected `SecureFrameTemplate` frame as the helper object:

- creation: `SecureHandlers.lua:631-644`

The public APIs:

- `SecureHandlerWrapScript` (`SecureHandlers.lua:647-686`)
- `SecureHandlerUnwrapScript` (`SecureHandlers.lua:691-722`)
- `SecureHandlerExecute` (`SecureHandlers.lua:725-744`)
- `SecureHandlerSetFrameRef` (`SecureHandlers.lua:747-770`)

all drive behavior by setting attributes on that helper frame and letting `OnAttributeChanged` do the protected work.

### Explicit protection is mandatory for headers

Secure handler wrapping and execution require the header frame to be explicitly protected:

- `_wrap` path: `SecureHandlers.lua:539-542`
- public wrap path: `SecureHandlers.lua:669-671`
- public execute path: `SecureHandlers.lua:734-736`

This matches the same explicit-protection requirement seen in frame handles and managed environments.

### _frame-label is how secure code safely gets other frame handles

`_frame-<label>` stores a `frameref-<label>` handle (`SecureHandlers.lua:601-627`).

`RestrictedFrames.lua` explicitly documents this as the safe way snippets obtain relative frame handles (`RestrictedFrames.lua:9-14`).

If you see secure-header code using raw frame references instead of this pattern, it is probably wrong.

## RestrictedEnvironment: How Blizzard Curates What Snippets May Call

`RestrictedEnvironment.lua` is not a loose export of globals. It is curated.

### Base environment is tiny on purpose

The initial restricted scope only contains selected primitives, string functions, math functions, and macro-conditional style helpers:

- scope definition: `RestrictedEnvironment.lua:24-77`
- direct macro conditional names: `RestrictedEnvironment.lua:81-98`

This is far smaller than normal Lua, and intentionally so.

### Inbound and outbound scrubbing are distinct

Blizzard defines:

- `ScrubInboundValue` / `ScrubInboundValues` (`RestrictedEnvironment.lua:110-120`)
- `ScrubOutboundValue` / `ScrubOutboundValues` (`RestrictedEnvironment.lua:122-132`)

Key behavior:

- inbound tables are copied with restricted `copytable`
- non-table inbound values are scrubbed
- outbound values only preserve frame handles; everything else is scrubbed

### Outbound Lua calls must scrub arguments

Blizzard's own comment is blunt:

Because functions in the global environment can be securely hooked by addons, all outbound calls from the restricted environment must scrub their inputs first.

See `RestrictedEnvironment.lua:216-225`.

This is one of the cleanest explanations in Blizzard code for why taint can spread in surprising directions. Even Blizzard's own secure code assumes addon hooks may exist and treats them as a contamination surface.

### Return values from outbound functions are scrubbed before re-entry

Blizzard wraps outbound functions through `CreateInboundReturnScrubber` and `ImportOutboundFunctions` so their returns are sanitized before entering the restricted environment:

- `RestrictedEnvironment.lua:262-282`

### Action info is whitelisted, not passed through raw

`ENV.GetActionInfo` keeps only a safe subset of action data and collapses unknown action types to just the type string:

- `RestrictedEnvironment.lua:161-174`

That is another example of Blizzard preferring lossy safety over rich but unsafe object return shapes.

## Secure Delegates And forceinsecure

Blizzard uses two related techniques everywhere:

- secure delegates to cross from tainted code into a carefully controlled secure call site
- `forceinsecure()` to ensure risky addon code does not run securely by accident

### CreateSecureDelegate is a narrow elevation barrier

`CreateSecureDelegate` is documented as producing a "secure delegate function" (`FrameScriptDocumentation.lua:98-113`).

Blizzard uses it in several important places:

- chat filter array creation (`ChatFrameFiltersSecure.lua:3-8`)
- tooltip accessors (`TooltipDataHandler.lua:488-518`)
- action button cooldown application (`ActionButton.lua:902-930`)

### Delegates do not deep-clean tables

Blizzard calls this out directly in `ActionButton.lua`:

- "SecureDelegates will not ... clear taint off values inside of tables" (`ActionButton.lua:902-930`)

That is why `SecureCooldown_ApplyCooldown` takes a long list of primitive arguments instead of a few info tables.

This is one of the most useful practical rules in the codebase:

- do not pass tables through secure delegates if you care about taint cleanliness
- flatten to primitives or rebuild safe tables on the secure side

### Secure mixins can also be elevation barriers

Blizzard uses secure delegates, but it also uses secure mixin entry points as elevation barriers.

`ScrollingMessageFrame.lua` says its public secure mixin methods are "secure elevation barriers":

- tainted callers invoke them as-if execution were untainted
- function arguments are wrapped in closures that taint when invoked

See `ScrollingMessageFrame.lua:788-819`.

This is the same larger design pattern:

- Blizzard may offer a narrow safe entry point for tainted callers
- but it still controls how far taint-clean execution is allowed to propagate
- callback-like arguments remain dangerous and are treated accordingly

### forceinsecure is used when a callback is "at risk"

Examples:

- user-provided secure action handlers: `SecureTemplates.lua:710-736`
- restricted `CallMethod`: `RestrictedFrames.lua:810-819`
- insecure tooltip callbacks: `TooltipDataHandler.lua:181-193`

In `SecureTemplates.lua`, Blizzard marks user-provided function lookups as `atRisk` and calls `forceinsecure()` before invoking them (`SecureTemplates.lua:712-730`).

That is Blizzard explicitly refusing to let addon-defined behavior inherit secure execution just because the call started inside a secure framework.

## Secure Action Buttons And Why Delegated Clicks Check IsForbidden

`SecureTemplates.lua` shows several security choices that matter for addon authors.

### Secure actions prefer attributes and whitelisted handlers

The action button system looks up action types via modified attributes and only falls back to user-provided functions or raw methods if needed (`SecureTemplates.lua:703-736`).

### Click delegation rejects forbidden targets

`SECURE_ACTIONS.click` only forwards clicks if the delegate exists and is not forbidden:

- `SecureTemplates.lua:554-560`

That tells you Blizzard expects click delegation to be a common place where secure code could accidentally bounce through unsafe objects.

### User-provided handlers are treated as dangerous

If the action type resolves to:

- a user-provided attribute function
- or a raw method on the frame

Blizzard marks it `atRisk` and forces insecure execution before calling it (`SecureTemplates.lua:712-730`).

The intended pattern is clear:

- Blizzard-owned secure behavior may stay secure
- addon-owned custom behavior must run insecurely

## State Drivers, Hover Drivers, And Group Headers

### State drivers are attribute-driven and keep statehidden consistent

`SecureStateDriver.lua`:

- registers attribute drivers by setting attributes on `SecureStateDriverManager` (`SecureStateDriver.lua:7-23`)
- bridges state drivers and attribute drivers (`SecureStateDriver.lua:25-32`)
- updates visibility through `Show`, `Hide`, and `statehidden` (`SecureStateDriver.lua:73-89`, `SecureStateDriver.lua:95-117`)

### Unit watch now uses UnitExists or UnitIsVisible

The unit-existence cache uses:

- `UnitExists(k) or UnitIsVisible(k)` (`SecureStateDriver.lua:56-62`)

This is a subtle but important modern behavior change. Blizzard is broadening the conditions under which the secure unit watch system considers a unit worth tracking.

### Hover driver scrubs geometry

`SecureHoverDriver.lua` scrubs both scale and rectangle reads before using them:

- `GetScreenFrameRect` (`SecureHoverDriver.lua:100-106`)

That means even frame geometry is treated as something that can taint a secure hover path if read carelessly.

### Group header aura code is secret-aware

One of the best comments in the codebase appears in `SecureGroupHeaders.lua`:

- "Manually counting because indexed iteration over the next table produces secrets, which explode when fed into SetAttribute." (`SecureGroupHeaders.lua:1055-1058`)

The surrounding code uses `C_UnitAuras.GetUnitAuras(...)` and manually builds safe aura tables (`SecureGroupHeaders.lua:1055-1075`).

This is a direct statement from Blizzard that:

- aura iteration can produce secrets
- feeding those secrets into secure attribute plumbing is fatal
- safe code must repackage the data explicitly

For any addon touching aura-driven secure UI, this is not theoretical. It is the engine's current data model.

## Tooltips Are A Major Taint And Secret Boundary

Tooltips deserve their own section because Blizzard has an unusual amount of defensive code around them.

### Old tooltip state can taint future tooltip builds

`GameTooltip.lua` explains that reading previous tooltip info can taint if the tooltip was previously shown by an addon:

- `GameTooltip.lua:980-989`

Blizzard then uses:

- `securecallfunction(self.GetPrimaryTooltipInfo, self)` (`GameTooltip.lua:989`)

to keep that taint from flowing into `ProcessInfo`.

That is a concrete warning against reusing tooltip state naively.

### Tooltip health bar data is stored in attributes because Lua fields were unsafe

`GameTooltipUnitHealthBarMixin` stores the GUID in an attribute and comments that there is a taint path through some addon tooltip customizations:

- `GameTooltip.lua:1031-1068`

Blizzard then promotes helper methods into a secure mixin so tainted call paths can still invoke them safely:

- `GameTooltip.lua:1075-1087`

### TooltipDataHandler splits secure and insecure callback paths

`TooltipDataHandler.lua` maintains:

- secure pre/post callback tables
- insecure pre/post callback tables
- a forbidden attribute delegate frame that inserts and processes insecure callbacks

See `TooltipDataHandler.lua:15-37`, `TooltipDataHandler.lua:92-125`.

Insecure callbacks are executed through `securecallfunction`, not directly (`TooltipDataHandler.lua:62-72`, `TooltipDataHandler.lua:120-124`).

### Tooltip accessors are promoted to secure delegates, but with gates

Blizzard wraps tooltip `SetX` accessors with secure delegates (`TooltipDataHandler.lua:488-518`), but only after checking:

- `CheckAllowProtectedFunctions(self)` (`TooltipDataHandler.lua:506-510`)
- `CheckAllowSecretArguments(getterFunction, ...)` (`TooltipDataHandler.lua:512-515`)

It also sanitizes away illegal function-valued arguments (`TooltipDataHandler.lua:475-486`).

This is the exact pattern Blizzard uses when it wants tainted addon code to do a safe, limited thing without letting taint or secrets blow through the rest of the pipeline.

## Attribute Bridges And Split-Environment UIs

Another repeated Blizzard pattern is splitting a feature into:

- forbidden or secure UI/state
- inbound functions that are safe for tainted callers
- outbound or insecure files that are not allowed to return data back into the secure side

The comments are explicit.

Inbound modules:

- `Blizzard_WowTokenUIInbound.lua:1-22`
- `Blizzard_CatalogShop_Inbound.lua:1-67`
- `Blizzard_CatalogShopTopUpFlow_Inbound.lua:2-30`
- `Blizzard_Shared_StoreUIInbound.lua:1-25`

all say tainted code should communicate with secure code only via `SetAttribute` and `GetAttribute`.

Outbound or insecure modules:

- `Blizzard_WowTokenUIInsecure.lua:1-15`
- `Blizzard_CatalogShop_Unsecure.lua:1-10`

say they do not have access to the secure forbidden code and should never return values.

The receiving secure frames reinforce the pattern in their own handlers:

- `WowTokenRedemptionFrame_OnAttributeChanged` says attributes are how external UI should communicate so taint does not spread into the code (`Blizzard_WowTokenUI.lua:286-303`)
- `CatalogShopMixin:OnAttributeChanged` says the same (`Blizzard_CatalogShop.lua:519-538`)

This is one of Blizzard's clearest architectural answers to taint:

- treat `SetAttribute` and `GetAttribute` as IPC between tainted and secure worlds
- keep the secure side authoritative
- avoid returning arbitrary values from the insecure side back into forbidden code

Important caveat:

- attributes are a transport and contract boundary, not a magical sanitizer

Blizzard sometimes passes small structured tables through these bridges:

- `Blizzard_WowTokenUIInbound.lua:20-21`
- `Blizzard_CatalogShop_Inbound.lua:52-58`
- `Blizzard_Shared_StoreUIInbound.lua:52-75`

On the secure side, Blizzard still controls the exact shape and interpretation of those payloads, for example:

- unpacking with `securecallfunction(unpack, value)` in `Blizzard_WowTokenUI.lua:300-302`
- building a curated result table in `Blizzard_Shared_StoreUISecure.lua:1537-1569`

So the real pattern is:

- use attributes as the crossing point
- keep payloads narrow and predictable
- validate or unpack on the secure side
- do not assume "it went through SetAttribute" means it is now clean or safe

## Ordering, Call Placement, And Timing Matter

Taint is not only about what code runs. It is also about when it runs relative to other hookable or tainted paths.

Blizzard repeatedly rearranges code to perform sensitive or restricted work earlier:

- `TargetFrame.lua` moves target-of-target updates earlier "to avoid taint from functions below" (`Blizzard_UnitFrame/Mainline/TargetFrame.lua:128-131`, `Blizzard_UnitFrame/Mainline/TargetFrame.lua:162-165`)
- `UIParent.lua` performs `C_Ping.TogglePingListener` before dropdown handling because the ping toggle is restricted and doing it later would allow taint propagation (`Blizzard_UIParent/Mainline/UIParent.lua:2245-2255`)
- `Blizzard_SettingsInbound.lua` uses `securecallfunction(PrivateSettingsCategoryMixin.CreateSubcategory, ...)` specifically "to avoid taint" (`Blizzard_Settings_Shared/Blizzard_SettingsInbound.lua:182-200`)

Practical implication:

- doing the same protected or restricted call after a tainted callback chain is not equivalent to doing it before
- if a feature mixes restricted work and addon-hookable work, do the restricted work first when possible
- if a helper might be hookable or taint-sensitive, isolate it behind `securecallfunction` or a narrow barrier rather than calling it inline in the contaminated path

## Shared Containers Are Taint Multipliers

A recurring pattern in Blizzard code is that the first unsafe write into a shared container poisons later readers.

### CVar cache

`CvarUtil.lua` only writes to `cvarValueCache` when `issecure()`:

- `CvarUtil.lua:145-158`

Blizzard comment:

- if a tainted execution path caches the value, future reads of that cached value will taint execution

### Chat filter registries

`ChatFrameFiltersSecure.lua` says filter-array creation must always execute securely because the arrays are lazy-created and the first registration would otherwise taint all other filters and potentially the chat frame (`ChatFrameFiltersSecure.lua:3-8`).

`ChatFrameFilters.lua` then uses:

- `SecureTypes.CreateSecureArray()` (`ChatFrameFilters.lua:6-16`, `ChatFrameFilters.lua:76-94`)
- `SecureTypes.CreateSecureMap()`
- `canaccessvalue(...)` before invoking user callbacks on decorated sender names (`ChatFrameFilters.lua:26-46`, `ChatFrameFilters.lua:112-123`)
- `securecallfunction(...)` around filter invocation (`ChatFrameFilters.lua:57-70`, `ChatFrameFilters.lua:138-163`)

That is a full Blizzard example of how to let addons plug into a shared pipeline without letting them taint the whole thing.

### Callback registries

`CallbackRegistry.lua` uses:

- a forbidden `AttributeDelegate` (`CallbackRegistry.lua:21-49`)
- secure insertion of event keys (`CallbackRegistry.lua:106-110`, `CallbackRegistry.lua:125-126`)
- deferred callback tables during reentrant dispatch (`CallbackRegistry.lua:83-94`, `CallbackRegistry.lua:160-182`)
- `secureexecuterange` and `securecallfunction` for execution (`CallbackRegistry.lua:184-223`)

The code comment at `CallbackRegistry.lua:125-126` calls this a "taint barrier for inserting event key into callback tables."

`StaticPopup.lua` shows a related failure mode in ordinary shared arrays:

- if an addon-initiated dialog leaves a tainted `nil` behind, later `ipairs` or `ipairs_reverse` iteration over `shownDialogFrames` can taint
- Blizzard resolves that by reallocating the table through a forbidden attribute delegate when the list becomes empty

See `Blizzard_StaticPopup/StaticPopup.lua:67-82`.

### Pools

`Pools.lua` rejects secret objects from secure pools:

- `Pools.lua:265-280`

Blizzard comment:

- if one secret object enters a pool, future acquisitions become secret too

It also adds secure barriers when enumerating or releasing across secure pool collections:

- `Pools.lua:480-517`

And secure frame pool creation can use `CreateForbiddenFrame`:

- `Pools.lua:546-560`

### Frame fade and flash lists

`FrameUtil.lua` uses secure barriers around the shared `FADEFRAMES` and `FLASHFRAMES` lists:

- `UIFrameFadeContains` checks via `securecallfunction` (`FrameUtil.lua:323-328`, `FrameUtil.lua:411-413`)
- fade removal via `securecallfunction` (`FrameUtil.lua:351-353`)
- flash timer updates via `secureexecuterange` (`FrameUtil.lua:470-472`)
- flash containment and removal via `securecallfunction` (`FrameUtil.lua:523-531`)

### Tainted handler arrays

`Blizzard_MapCanvasSecureUtil.lua` provides a nice minimal pattern:

- iterate tainted arrays through `securecallfunction(rawget, ...)` (`Blizzard_MapCanvasSecureUtil.lua:15-27`)
- sort/remove handlers through secure barriers (`Blizzard_MapCanvasSecureUtil.lua:41-56`)
- invoke handlers via `securecallfunction` and `SafePack` (`Blizzard_MapCanvasSecureUtil.lua:66-76`)

## Secret State Can Affect Ordinary UI Code

One of the most important validation results is that secret-state issues are not confined to obviously secure files.

### Generic setters may reject secret-backed values

`GuildRoster.lua` has a concrete comment:

- some `memberInfo` fields are secret
- `SetEnabled` does not allow secrets
- Blizzard works around that by checking the condition directly and then calling `Enable` or `Disable`

See `GuildRoster.lua:177-185`.

This is a useful warning for addon code. If data may be secret, even ordinary widget mutators can become invalid sinks.

### Child bounds and layout can propagate secret state

`CooldownViewerSettings.xml` explicitly uses `ignoreChildrenForBounds="true"` with the comment:

- this prevents a secret icon from setting the entire settings UI as secret

See `CooldownViewerSettings.xml:16-18`.

That means secret propagation is not only about calling protected functions. It can affect layout, bounds, and frame-level secrecy through child relationships.

## Inspecting Foreign Values Safely

Even debugging helpers have to respect the secret model.

`Dump.lua` uses:

- `canaccessvalue(...)` before formatting or truncating values (`Dump.lua:97-120`)
- `canaccesstable(...)` before traversing tables (`Dump.lua:315-320`)
- `issecretvalue(...)` to label simple secret values distinctly (`Dump.lua:308-315`)

That is useful implementation guidance for addon authors too:

- do not blindly log, stringify, or iterate foreign values from restricted systems
- if a value may be secret or inaccessible, gate access first
- if you need to inspect foreign tables during debugging, assume `canaccessvalue` and `canaccesstable` checks are part of the safe path, not optional niceties

## SecureTypes: Blizzard's Safe Container Library

`SecureTypes.lua` is effectively Blizzard's standard library for taint-aware shared containers.

The top-level comment is explicit:

- secure types are expected to prevent taint propagation while accessing mixed-origin containers (`SecureTypes.lua:21-24`)

Highlights:

- `SecureMap` wraps reads with `securecallfunction(rawget, ...)` and bans secret keys/values on write (`SecureTypes.lua:27-103`)
- `SecureArray` bans secret values and indices and uses barriers around element-moving operations (`SecureTypes.lua:107-221`)
- `SecureStack` bans secret values (`SecureTypes.lua:224-247`)
- `SecureValue`, `SecureNumber`, and related wrappers use secure barriers around gets/sets (`SecureTypes.lua:249-313`)

If Blizzard expects a container to survive contact with both secure and insecure call paths, it increasingly routes it through `SecureTypes` or an equivalent pattern.

## Practical Conclusions For Addon Authors

### 1. Do not think only in terms of combat

You still need `InCombatLockdown()`, but you also need to think about:

- protected function access
- forbidden object access
- secret data flow
- cached or pooled tainted state
- restricted states outside plain combat

### 2. Treat Blizzard-owned frames as foreign territory

Safe default:

- read cautiously
- write rarely
- avoid internal child frames unless Blizzard exposes them as intended extension points
- bail out immediately on `IsForbidden()`

### 3. Do not pass tables across secure boundaries unless you fully control both sides

Blizzard repeatedly flattens data into primitives before crossing secure boundaries.

If you pass a table into:

- a secure delegate
- a secure callback bridge
- a restricted attribute path

assume the contents may still carry taint or secrets.

### 4. Prefer attributes over Lua fields when protected state must survive tainted customization paths

Blizzard does this in tooltip code (`GameTooltip.lua:1031-1068`) because Lua-field state could persist taint in ways attributes did not.

That does not mean "always use attributes." It means:

- when the state participates in secure/protected plumbing, attributes are often the intended storage surface
- when the state is purely addon-local, normal Lua tables are better

### 5. Expect user callbacks to run insecurely

This is Blizzard's normal pattern, not an exceptional one.

If secure code has to notify addon logic:

- scrub the arguments
- cross through a narrow API
- run the addon callback insecurely

### 6. Shared registries and caches need clean creation paths

If a shared container is created or seeded on a tainted path, later readers can inherit that taint.

This is exactly why Blizzard protects:

- chat filter arrays
- callback registries
- CVar caches
- frame fade/flash arrays
- object pools

## Why Addons Like Plater Usually Stay Quiet

Addons that avoid taint problems tend to converge on the same patterns Blizzard uses:

- never mutate protected or forbidden Blizzard frames during restricted states
- defer changes until safe
- use addon-owned frames and addon-owned state wherever possible
- gate writes with `InCombatLockdown()` and often `IsForbidden()`
- avoid passing secret or foreign table objects through secure code
- use secure hooks or documented entry points instead of replacing Blizzard logic
- isolate user/plugin callbacks behind insecure execution boundaries

That is not accidental. It is the behavior the Blizzard code is designed to reward.

## QuestTogether-Specific Guidance

### Hard rules

- Never mutate Blizzard-owned protected or forbidden frames directly from QuestTogether UI code unless Blizzard has clearly made that frame an intended extension point.
- Never assume aura, tooltip, nameplate, or unit-frame data is ordinary data during restricted states.
- Never pass addon tables through secure delegates expecting the contents to come out clean.
- Never use restricted snippets as a place to run addon business logic. Use snippets to move secure attributes or signal small state changes only.
- Never depend on internal underscore attributes on secure frames unless Blizzard's secure template contract explicitly says to.
- Never treat `SetAttribute` / `GetAttribute` as an automatic sanitizer. If QuestTogether uses an attribute bridge, keep the payload shape narrow and validate it on the receiving side.
- Never schedule restricted or protected work after code paths that addons commonly hook if you can perform the restricted work first.
- Never blindly dump or iterate foreign values from secure systems; gate with access checks when secrecy is possible.

### Preferred patterns

- Keep secure-facing state flat and primitive.
- Keep addon logic on addon-owned frames or plain Lua modules.
- Use secure code only to:
  - set or read allowed attributes
  - update visibility or unit-watch state through Blizzard mechanisms
  - hand off back into insecure addon code through a narrow method call
- Queue protected-layout work until restrictions end.
- Guard foreign frames with `frame:IsForbidden()` before touching them.
- Copy and sanitize foreign data before caching it.
- When a feature needs tainted-to-secure communication, design it as a narrow attribute contract rather than direct mixed-context calls.
- When a flow mixes restricted work and hookable work, perform the restricted step first or isolate the hookable helper behind a secure barrier.
- When debugging taint-sensitive data, prefer access-gated inspection over generic dumps or broad table walks.

### Testing implications for this repo

Our test rules already point in the right direction:

- do not patch Blizzard globals or shared UI tables
- do not monkeypatch secure-adjacent APIs in tests
- push logic behind QuestTogether-owned wrappers and pure functions

That is good taint hygiene, not just good test hygiene.

## Safe Patterns

### Defer protected work until safe

```lua
local pendingSecureRefresh = false

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function()
    if pendingSecureRefresh then
        pendingSecureRefresh = false
        RefreshSecureBits()
    end
end)

function RequestSecureRefresh()
    if InCombatLockdown() then
        pendingSecureRefresh = true
        return
    end

    RefreshSecureBits()
end
```

### Bail out on forbidden objects

```lua
local function SafeTouch(frame, fn, ...)
    if not frame then
        return
    end

    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    return fn(frame, ...)
end
```

### Flatten data before crossing a secure boundary

```lua
local function ApplyCooldownSecure(button, info)
    SecureCooldown_ApplyCooldownDelegate(
        button.lossOfControlCooldown,
        info.lossOfControlStartTime or 0,
        info.lossOfControlDuration or 0,
        info.lossOfControlModRate or 1,
        button.cooldown,
        info.cooldownStartTime or 0,
        info.cooldownDuration or 0,
        info.cooldownIsEnabled and true or false,
        info.cooldownModRate or 1,
        button.chargeCooldown,
        info.chargeMaxCharges or 0,
        info.chargeCurrentCharges or 0,
        info.chargeCooldownStartTime or 0,
        info.chargeCooldownDuration or 0,
        info.chargeModRate or 1
    )
end
```

The point is not that QuestTogether should literally use this helper. The point is the shape: primitives in, no foreign tables crossing the barrier.

## Risk Checklist For Reviews

When reviewing QuestTogether code for taint risk, ask these in order:

1. Does this touch a Blizzard-owned frame, region, or callback registry?
2. Could that object be protected, explicitly protected, or forbidden?
3. Could this run during combat or another addon restriction state?
4. Does this read aura, tooltip, nameplate, or unit data that may be secret?
5. Does this store foreign data into a shared cache, pool, registry, or long-lived table?
6. Does this pass a table through a secure delegate or protected callback path?
7. Does this allow addon callback code to run from a secure path without forcing it back insecure?
8. Does this assume a child frame or mixin method is safe just because it is reachable?
9. Does this rely on `SetAttribute` / `GetAttribute` as if they automatically cleanse payloads?
10. Does this do restricted work after a hookable or taint-prone helper that could have run later instead?
11. Does this debug-print or iterate values that might be secret without `canaccessvalue` / `canaccesstable` style checks?

If several answers are "yes", the design should be reworked before debugging the symptoms.

## Common Failure Patterns

These are the patterns Blizzard's own code is defending against:

- a tainted caller caching a value that later secure code reads
- a secret aura or tooltip value being copied into a restricted table or attribute
- a secure header trying to reference a forbidden frame
- addon code running as part of a secure callback chain because no `forceinsecure()` barrier existed
- a shared container being lazily created from a tainted path
- a secure delegate receiving a table whose nested fields are still tainted
- foreign frame geometry or object references leaking into secure visibility logic
- attribute bridges being treated like sanitizers instead of narrow validated contracts
- restricted work being performed after taint-prone helpers instead of before them
- debug or dump code trying to stringify or traverse secret values directly

## Source Map

These are the highest-value files from the research pass and what each one tells us.

| File | Key Lines | Why It Matters |
| --- | --- | --- |
| `Blizzard_RestrictedAddOnEnvironment/Blizzard_RestrictedAddOnEnvironment.toc` | `1-15` | Shows the modern restricted addon stack Blizzard loads. |
| `Blizzard_RestrictedAddOnEnvironment/RestrictedExecution.lua` | `52-99`, `183-253`, `401-486` | Snippet compilation limits, managed environment logic, forbidden propagation, and secure call entry conditions. |
| `Blizzard_RestrictedAddOnEnvironment/RestrictedEnvironment.lua` | `24-98`, `110-132`, `161-174`, `216-282` | Exact restricted API surface plus inbound/outbound scrubbing rules. |
| `Blizzard_RestrictedAddOnEnvironment/RestrictedInfrastructure.lua` | `92-141`, `169-217`, `291-305`, `481-527`, `556-568`, `600-637` | Frame handles, restricted tables, secret key/value bans, copytable, and explicitly protected owner requirement. |
| `Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua` | `9-14`, `73-104`, `109-148`, `197-242`, `245-309`, `444-534`, `704-841` | Frame-handle API, scrubbing, forbidden gating, safe frame refs, controlled SetPoint/SetAttribute, and forced-insecure method calls. |
| `Blizzard_RestrictedAddOnEnvironment/SecureHandlers.lua` | `47-76`, `273-276`, `473-629`, `631-770` | Secure header execution, wrap rules, explicit protection checks, and forbidden-frame propagation through the API bridge. |
| `Blizzard_FrameXML/SecureTemplates.lua` | `554-560`, `710-736` | Click delegation forbids forbidden frames; addon-defined handlers are forced insecure. |
| `Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua` | `56-117` | Macro-conditional state resolution, visibility handling, and unit-watch semantics. |
| `Blizzard_RestrictedAddOnEnvironment/SecureHoverDriver.lua` | `100-106`, `167-173` | Geometry reads are scrubbed; hide path updates `statehidden`. |
| `Blizzard_RestrictedAddOnEnvironment/SecureGroupHeaders.lua` | `1055-1075` | Aura iteration can produce secrets; secure code must manually repackage the data. |
| `Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua` | `20-35`, `48-80`, `98-113`, `227-259`, `331-416`, `487-500` | The public docs for access checks, secret helpers, secure delegates, scrubbing, and table security options. |
| `Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua` | `10-69`, `72-128` | Restriction state APIs plus blocked/forbidden events. |
| `Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua` | `5-33` | Combat is only one restriction type among several. |
| `Blizzard_APIDocumentationGenerated/SimpleFrameScriptObjectAPIDocumentation.lua` | `69-150` | `HasSecretValues`, `IsForbidden`, `SetPreventSecretValues`, `SetToDefaults`. |
| `Blizzard_APIDocumentationGenerated/SimpleScriptRegionAPIDocumentation.lua` | `492-505` | `IsProtected()` returns both overall and explicit protection state. |
| `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` | `34-69` | Secret-return metadata exists beyond tooltips; unit/game-object position APIs already participate in the secret model. |
| `Blizzard_APIDocumentationGenerated/FrameAPITooltipDocumentation.lua` | `34-121` | Tooltip object APIs with secret-aspect metadata. |
| `Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua` | `627-642`, `1043-1060`, `1195-1300` | Tooltip getters that differ on tainted-call allowance and secret behavior. |
| `Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua` | `15-37`, `92-125`, `457-518` | Secure/insecure callback split, forbidden delegate frame, protected-function and secret-argument gating. |
| `Blizzard_GameTooltip/Mainline/GameTooltip.lua` | `980-989`, `1031-1087` | Tooltip state can taint future work; attributes and secure mixins are used as barriers. |
| `Blizzard_SharedXMLBase/SecureTypes.lua` | `21-24`, `27-221` | Blizzard's taint-safe container patterns. |
| `Blizzard_ChatFrameBase/Shared/ChatFrameFiltersSecure.lua` | `3-8` | Shared filter arrays must be created securely. |
| `Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua` | `26-46`, `57-70`, `112-163` | `canaccessvalue` guards and secure callback barriers for chat filters. |
| `Blizzard_SharedXMLBase/CvarUtil.lua` | `145-158` | Cached values become taint reservoirs if written from tainted paths. |
| `Blizzard_SharedXMLBase/CallbackRegistry.lua` | `24-49`, `83-126`, `160-245` | Forbidden delegate frame, deferred registration, secure iteration. |
| `Blizzard_SharedXMLBase/TemplateInfoCache.lua` | `1-18`, `24-33`, `46-51` | Another forbidden delegate pattern that fetches data through attributes instead of direct mixed-context calls. |
| `Blizzard_SharedXMLBase/Pools.lua` | `265-280`, `480-560` | Secret objects cannot enter secure pools; forbidden frame pools exist. |
| `Blizzard_SharedXMLBase/FrameUtil.lua` | `323-328`, `351-353`, `411-413`, `470-472`, `523-531` | Shared fade/flash lists are protected by secure barriers. |
| `Blizzard_SharedXML/ScrollingMessageFrame.lua` | `788-819` | Secure mixin methods are documented as elevation barriers for tainted callers. |
| `Blizzard_MapCanvasSecureUtil/Blizzard_MapCanvasSecureUtil.lua` | `15-27`, `41-76` | Minimal example of safe enumeration and invocation over tainted handler arrays. |
| `Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua` | `41-45` | Real Blizzard example of forbidding a sensitive subframe. |
| `Blizzard_ActionBar/Shared/ActionButton.lua` | `902-930` | Explicit warning that secure delegates do not deep-clean table contents. |
| `Blizzard_WowTokenUI/Blizzard_WowTokenUI.xml` | `3-7` | Entire UI subtrees can be declared forbidden in XML. |
| `Blizzard_PrivateAurasUI/Blizzard_PrivateAurasUI.xml` | `3-12` | Forbidden XML scopes can also be hidden from the global environment. |
| `Blizzard_WowTokenUI/Blizzard_WowTokenUIInbound.lua` | `1-22` | Tainted callers are expected to use `SetAttribute`/`GetAttribute` only. |
| `Blizzard_WowTokenUI/Blizzard_WowTokenUIInsecure.lua` | `1-15` | Outbound insecure code should not return values back into secure code. |
| `Blizzard_WowTokenUI/Blizzard_WowTokenUI.lua` | `286-303` | Secure handler frame documents attributes as the taint-safe communication channel. |
| `Blizzard_CatalogShop/Blizzard_CatalogShop_Inbound.lua` | `1-67` | Repeats the same taint-safe attribute bridge pattern. |
| `Blizzard_CatalogShop/Blizzard_CatalogShop_Unsecure.lua` | `1-10` | Repeats the same "no secure access, no return values" outbound pattern. |
| `Blizzard_CatalogShop/Blizzard_CatalogShop.lua` | `519-538` | Secure side again treats attributes as the taint-safe integration boundary. |
| `Blizzard_StoreUI/Blizzard_Shared_StoreUIInbound.lua` | `1-25` | The attribute-bridge pattern is repeated beyond a single subsystem. |
| `Blizzard_StoreUI/Blizzard_Shared_StoreUISecure.lua` | `1537-1569` | Secure-side attribute handlers may still validate payloads and return tightly curated structured results. |
| `Blizzard_Settings_Shared/Blizzard_SettingsInbound.lua` | `182-200` | `securecallfunction` is used around category creation specifically to avoid taint. |
| `Blizzard_UIParent/Mainline/UIParent.lua` | `2245-2255` | Ordering matters: restricted work is done before dropdown handling to avoid taint propagation. |
| `Blizzard_UnitFrame/Mainline/TargetFrame.lua` | `128-131`, `162-165` | Even call placement inside one function can matter; Blizzard moves sensitive work earlier to avoid later taint. |
| `Blizzard_Communities/GuildRoster.lua` | `177-185` | Secret values can make even normal setter APIs invalid sinks. |
| `Blizzard_CooldownViewer/CooldownViewerSettings.xml` | `16-18` | Secret child content can infect whole-frame bounds/layout state. |
| `Blizzard_StaticPopup/StaticPopup.lua` | `67-82` | Shared arrays can be poisoned by tainted holes; Blizzard reallocates via a forbidden delegate to recover. |
| `Blizzard_SharedXML/Dump.lua` | `97-120`, `308-320` | Safe debugging/introspection of foreign values depends on `canaccessvalue`, `canaccesstable`, and `issecretvalue`. |

## Bottom Line

If a piece of addon code is involved with any of the following:

- protected frames
- secure headers
- attribute drivers
- unit buttons
- tooltips
- aura data
- shared caches or registries
- Blizzard child frames you do not own

then the safe design is:

- keep data primitive and local
- cross security boundaries explicitly and narrowly
- assume foreign tables may carry taint or secrets
- run addon-defined behavior insecurely
- refuse to touch forbidden objects
- defer protected mutations until the engine says it is safe

That is the model Blizzard's own interface code is built around.
