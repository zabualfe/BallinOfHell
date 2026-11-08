# Tables

Pure data ModuleScripts (no logic, no requires). Numbers come from `docs/GDD.md`; prices are placeholders until the Director signs off.
Product and pass `Id = 0` are placeholders; PurchaseService builds the id -> product lookup at runtime.

| Table | GDD section |
| --- | --- |
| `RarityTable` | 4 (rarity table, colours) |
| `BallTable` | 4 roster, 8.5 seasonal balls |
| `PhysicsTable` | 3 stat -> physics constants, 5.4 obstacle defaults |
| `CourseTable` | 5 tiers, 30 slots, picker, checkpoints/anti-cheat |
| `RoundTable` | 2 round steps, finish multiplier and clock |
| `EconomyTable` | 9 multipliers and coin sources, 10.2 first-fall present |
| `ToolTable` | 6 tools, loadout, charges |
| `TrickTable` | 7 airtime config, tricks, scoring, caps, upgrades |
| `SeasonTable` | 8.2-8.6 season config and Season 1 reward tracks |
| `ChallengeTable` | 8.4 daily and weekly pools |
| `DailyRewardTable` | 10.3 |
| `TimedRewardTable` | 10.4 |
| `WheelTable` | 10.5 |
| `StarterPackTable` | 10.6 |
| `PassTable` | 11.1 |
| `ProductTable` | 11.2, 6.7, 7.10, 8.7 |
| `ModifierTable` | 11.3 |
| `UpsellTable` | 11.4 |
| `AnalyticsTable` | 12 funnels, economy transaction types, custom event names |
