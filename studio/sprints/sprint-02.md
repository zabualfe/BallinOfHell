# Sprint 2 report: MVP systems (code)
**Date:** 2026-11-07   **Result:** All server systems and non-UI client controllers are done and reviewed. Nothing has been playtested.

## Done
- T-010 EconomyService (sole owner of coins; multipliers per GDD §9 and §13) + ShopService.
- T-016 PurchaseService (sole ProcessReceipt; idempotent; target store; plug-in families) + GamePassService (wired into BallService).
- T-019a FlagService (remote config, safe defaults, A/B buckets) + AnalyticsService/AnalyticsTable.
- T-011/12 Daily + Timed rewards (Restore Streak, Unlock All) · T-013/14 RewardService + SpinWheelService (PolicyService, odds) + StarterPackService.
- T-015 First-fall present · T-023 ToolService + 3 tools · T-026 TrickService/TrickController (scoring) · T-028 SeasonService + ChallengeService.
- Reviews T-033a/c, fixes T-033b/d. Among them: the Robux-ball double pay, re-claimable partial grants, the VIP maths, under-paid Assist halving, and idle "play N rounds" farming.

## Notes
GDD §7.5 example 2 is off by one (578, not 577). All product/pass ids are `0` placeholders, so nothing can be bought until real ids are set.
