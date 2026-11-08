# Sprint 3 report: Launch systems (code)
**Date:** 2026-11-07   **Result:** All code tasks are done and reviewed. The Launch milestone still needs the Studio work (art, UI, VFX, animations, QA).

## Done
- T-017 LimitedBallService. 1,200 simulated concurrent buys sell exactly 1,000 with unique serials. MemoryStore reservations, `_Studio` stores, Cmdr stock/log.
- T-018 ModifierService + server-wide/troll products: always-reset attributes, a 90 s troll cooldown and queue, immunity for the buyer, Finale players and new players.
- T-019b UpsellService: 19 trigger plug-ins, 90 s spacing, session caps, the Shield/Skip A/B test, and it owns the Starter Pack popup.
- T-024 the remaining 6 tools (all 9 now) + a client speed/gravity multiplier stack · T-032 LeaderboardService (wins, fastest; skipped runs set no record).
- Reviews T-034a/c, fixes T-034b/d.

## Final verification (2026-11-07)
`lune run tests` gives 567 passed across 44 spec files. selene shows 0 errors/0 warnings, stylua is clean and rojo builds. No `pairs`/`_G`/`wait`/`tick`, one RemoteEvent + one RemoteFunction (+ Cmdr's own) and one ProcessReceipt setter. About 20.8k lines of our own Luau.
