# LLM_CONTEXT_MIN

- Read `AGENTS.md` first; treat it as hard repo policy.
- Read `LLM_CONTEXT.md` if the task touches Blizzard-facing, nameplate, tooltip, aura, or taint-sensitive code.
- Never store QuestTogether state on Blizzard-owned frames, members, child frames, or shared Blizzard tables.
- Always bail out on `IsForbidden()` before mutating a foreign frame.
- Always treat tooltip, aura, nameplate, and unit-frame data as potentially secret or inaccessible during restricted states.
- Always defer protected UI, layout, nameplate, and CVar mutations until restrictions end.
- Never pass addon tables or foreign tables across secure delegates, attribute bridges, or protected callbacks.
- Always keep secure-boundary payloads flat, primitive, copied, and validated.
- Prefer wrappers, `hooksecurefunc`, events, and public APIs over direct Blizzard mutation or function replacement.
- Keep quest logic separate from core plate lifecycle and make open-world versus instance behavior explicit.
- Treat shared caches, pools, callback lists, and CVar caches as taint multipliers; sanitize foreign data before caching.
- Keep `/qt test` safe for a live WoW session; never patch Blizzard globals, shared UI tables, or secure-adjacent APIs in tests.
