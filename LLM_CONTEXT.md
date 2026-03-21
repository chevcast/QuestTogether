# LLM_CONTEXT

- Purpose: compact operational rules for Codex and other LLM agents.
- Priority: `AGENTS.md` hard repo policy first; this file next; source research only if needed.
- Interpretation: `Critical` and `Hard Rules` are mandatory; `Preferred Patterns` are strong defaults.

## Critical

- Never store QuestTogether state on Blizzard-owned frames, members, child frames, or shared Blizzard tables.
- Always bail out on `IsForbidden()` before mutating a foreign frame.
- Always treat tooltip, aura, nameplate, and unit-frame data as potentially secret or inaccessible during restricted states.
- Always defer protected UI, layout, nameplate, and CVar mutations until restrictions end.
- Never pass addon tables or foreign tables across secure delegates, attribute bridges, or protected callbacks.
- Always keep secure-boundary payloads flat, primitive, copied, and validated.
- Prefer QuestTogether-owned wrappers, hooks, and public APIs over direct Blizzard mutation or replacement.
- Keep `/qt test` safe for a live WoW session; never patch Blizzard globals, shared UI tables, or secure-adjacent APIs in tests.
- Keep quest logic separate from core plate lifecycle and open-world policy explicit.
- Always build teardown paths as carefully as setup paths; nameplates and UI objects are recycled aggressively.

## Hard Rules

### Test Safety

- Keep `/qt test` safe for a live WoW session.
- Never patch Blizzard globals, shared UI tables, or secure-adjacent APIs in tests, including `_G`, `LinkUtil`, `C_*`, chat frame globals, `issecretvalue`, `hooksecurefunc`, and Blizzard mixins.
- If logic depends on Blizzard or secure APIs, refactor behind QuestTogether-owned wrappers or pure functions and test those instead.
- If a test cannot be made safe under those constraints, do not add it to `Tests.lua`.

### Secure Boundaries

- Treat taint as provenance, not just combat.
- Account for restriction state beyond `InCombatLockdown()`, including encounter, challenge mode, PvP, map, and activation state.
- Distinguish protected, explicitly protected, forbidden, and secret; do not collapse them into one concept.
- Treat forbidden frames as quarantined and assume forbidden state can propagate through related secure paths.
- Never assume Blizzard child frames, mixins, or underscore attributes are safe extension points just because they are reachable.
- Never use restricted snippets for addon business logic.
- Never rely on `SetAttribute` / `GetAttribute` to sanitize payloads.
- Expect secure-to-addon callbacks to run insecurely; keep the handoff narrow and validate arguments.
- Never blindly dump, stringify, or iterate foreign values that may be secret; use `canaccessvalue` / `canaccesstable` / `issecretvalue`-style gates.

### Frame Ownership And UI

- Treat Blizzard-owned frames as foreign territory: read cautiously, write rarely, prefer public APIs.
- Never store QuestTogether state on Blizzard frames or Blizzard-owned members.
- Centralize risky Blizzard, nameplate, tooltip, and frame access behind wrappers that perform forbidden, protected, and restriction checks.
- Prefer `hooksecurefunc`, events, and documented entry points over replacing Blizzard logic.
- Use guard, early return, and deferred retry instead of forcing risky work through restricted paths.
- Do restricted or protected work before hookable or taint-prone helpers, or defer it entirely.
- Separate layout mutation from volatile or secret-prone data reads.
- Reuse Blizzard infrastructure where safer than replacement, especially plate existence, widgets, resources, and structured tooltip data.
- If QuestTogether fully owns a hidden Blizzard path, disable redundant Blizzard updates or events to avoid dual ownership.
- Keep open-world, dungeon, raid, PvP, arena, and city behavior explicit in policy code.

### Data, Caches, And Extensions

- Treat shared registries, pools, callback lists, CVar caches, and long-lived tables as taint multipliers.
- Never copy foreign or secret data directly into shared caches, pools, registries, or attributes; flatten and sanitize first.
- Treat attribute bridges as narrow contracts, not general data buses.
- Isolate scripts, plugins, comms, and other extension points behind `xpcall` or equivalent error boundaries.

### Tooltip And Quest Logic

- Prefer structured Blizzard tooltip APIs over raw tooltip text.
- If tooltip parsing is required, filter aggressively to relevant line types and treat tooltip metadata as untrusted.
- Guard tooltip GUIDs, line types, and other foreign values for secrecy or inaccessibility before using them.
- Keep quest detection explicitly open-world aware; make instance behavior deliberate.
- Debounce expensive quest-cache rebuilds and other noisy boundary work.
- Mark a unit as a quest objective only when matched quest data shows unfinished progress.

### Review Gate

- Before landing Blizzard-facing code, verify: no QuestTogether state is written onto Blizzard objects, forbidden and restriction guards exist, restricted work is deferred, foreign data is sanitized before caching, and debug code uses access-gated secret checks.

## Preferred Patterns

- Prefer QuestTogether-owned wrappers around Blizzard APIs so logic can be tested, cached, and reviewed safely.
- Prefer addon-local state in QuestTogether-owned frames, side tables, or plain Lua modules.
- Prefer flat, primitive secure-boundary payloads with explicit validation on receipt.
- Prefer doing less immediately and retrying later instead of forcing work through live restricted paths.
- Prefer quest detection that can be disabled or replaced without destabilizing plate lifecycle code.
- Prefer extension isolation that can temporarily disable repeated secret-value failures.
- Treat tooltip and title-based quest inference as useful but brittle; keep localization and third-party tooltip-shaping assumptions contained.
