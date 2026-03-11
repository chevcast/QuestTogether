# QuestTogether Notes

## Testing

- Keep `/qt test` safe for a live WoW session.
- Do not add in-game tests that patch Blizzard globals, shared UI tables, or secure-adjacent APIs such as `_G`, `LinkUtil`, `C_*` tables, chat frame globals, `issecretvalue`, `hooksecurefunc`, or Blizzard mixins.
- If behavior depends on those APIs, refactor the addon code so the logic can be tested through QuestTogether-owned wrappers or pure functions instead of monkeypatching live client objects.
- If a test cannot be made safe under those constraints, do not add it to `Tests.lua`.
