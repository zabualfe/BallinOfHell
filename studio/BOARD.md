# Ball of Hell Production Board

**Design doc:** `docs/GDD.md` (draft v1, awaiting Director review of §12). Architecture: `docs/ARCHITECTURE.md`
**Reference code:** `~/Documents/GitHub/Ballin Revamped` (Rojo)
**Studio place:** "ballin v2 the sequel" (placeId 122054442557559)   **Code:** files at repo root (ReplicatedFirst/, ReplicatedStorage/, ServerScriptService/, ServerStorage/), auto-synced to Studio
**UI designs:** https://www.figma.com/design/Vsk0yM8NFKD8QOLRjKNeqo/BallinOfHell?node-id=0-1 (Figma, empty as of 2026-11-07)
**Art guides:** `~/Documents/GitHub/RobloxKart/BLENDER_TO_ROBLOX_GUIDE.md`
**Last updated:** 2026-11-08 (Sprint 5 started)

> **Status: plan approved 2026-11-07. Answers to §9 are in DECISIONS.md.**

## Milestones
| # | Milestone | Goal | Status |
|---|-----------|------|--------|
| M1 | Prototype | Pick 1 of 3 starters → roll a generated 30-segment course with checkpoints/falls/finish; stats feel different; data saves | planned |
| M2 | MVP | Coins, shop/inventory (20 balls), daily, timed, wheel, starter pack, first-fall present, core purchases, HUD | planned |
| M3 | Launch | Limited ball (1000), server modifiers, upsells, analytics/flags, 45+ segments + art, VFX, mobile perf, policy/odds, QA | planned |
| M4 | Live ops | Events, segment packs, leaderboards, price A/B tests | planned |

## Production plan (2026-11-07, Director: "run all sprints")
Studio MCP isn't connected, so sprints 1–3 build all **file-based code**: server systems, Tables, pure logic with offline tests, and non-UI client controllers. Studio-only work is in the **Blocked on Studio** list below.

## Sprint 1: Foundations + rolling slice (code)
| ID | Task | Owner | Depends on | Status | Acceptance criteria |
|----|------|-------|------------|--------|---------------------|
| T-001 | GDD draft | Game Designer | — | done | Covered by DECISIONS 2026-11-07 |
| T-002 | Toolchain (project.json, aftman selene/stylua/lune), entry loaders, Utilities, offline test harness | Programmer | — | done | selene clean; loaders match AGENTS.md; `lune run tests` passes |
| T-029 | All `ReplicatedStorage/Tables` from the GDD (pure data) | Programmer | — | done | Every table named in ARCHITECTURE §3 exists with GDD numbers |
| T-003 | Network (rate-limited) + PlayerData (ProfileStore, DataTemplate, client mirror, DataLoaded) | Programmer | T-002 | done | API matches AGENTS.md; token bucket tested |
| T-030 | BallStats.Resolve + table consistency tests | Programmer | T-002, T-029 | done | GDD §13 physics + roster criteria pass in tests |
| T-005 | BallService + BallController (port feel, stats-driven, speed audit) | Programmer | T-003, T-030 | done | Attributes from BallStats; strike rule from §13 |
| T-006a | CourseService (SegmentPicker, CheckpointBuilder, FallZones) | Programmer | T-003 | done | §13 Course criteria; picker tested offline |
| T-007 | InventoryService (own/equip) + OnboardingService starter pick (server) | Programmer | T-003 | done | Non-starter pick rejected; idempotent |
| T-006b | ProgressService + RoundService (sequenced steps) | Programmer | T-006a, T-005 | done | §13 Round flow + checkpoint validation |
| T-031 | ObstacleController (tag registries) + CameraController (client) | Programmer | T-005 | done | Each tag kind registers and unregisters with no leaks; one loop drives all animated kinds |
| T-022 | Cmdr admin commands | Programmer | T-003 | done | give-coins, set-segment, reset-onboarding; admin-only |
| T-008 | Code review of sprint 1 | Programmer (2nd) | all above | done | Must-fix list resolved |

## Sprint 2: MVP systems (code)
| ID | Task | Owner | Depends on | Status |
|----|------|-------|------------|--------|
| T-010 | EconomyService + ShopService (+ Inventory duplicates → coins); checkpoint coins wired | Programmer | S1 | done |
| T-016 | PurchaseService (ProcessReceipt) + GamePassService + core product plug-ins | Programmer | S1 | done |
| T-019a | FlagService + AnalyticsService | Programmer | S1 | done |
| T-011/12 | DailyRewardService + TimedRewardService | Programmer | T-010, T-016 | done |
| T-013/14 | SpinWheelService (+PolicyService) + StarterPackService | Programmer | T-010, T-016 | done |
| T-015 | First-fall present (server + client present) | Programmer | T-010 | done |
| T-023 | ToolService + ToolController + first 3 tools | Programmer | T-010, T-016 | done |
| T-026 | TrickService + TrickController (scoring tested) | Programmer | T-010 | done |
| T-028 | SeasonService + ChallengeService + season products | Programmer | T-019a, T-016 | done |
| T-033 | Code review of sprint 2 | Programmer (2nd) | all above | done |

## Sprint 3: Launch systems (code)
| ID | Task | Owner | Depends on | Status |
|----|------|-------|------------|--------|
| T-017 | LimitedBallService (DataStore + MemoryStore + MessagingService) | Programmer | S2 | done |
| T-018 | ModifierService + server-wide/troll products | Programmer | S2 | done |
| T-019b | UpsellService | Programmer | S2 | done |
| T-024 | Remaining tools | Programmer | T-023 | done |
| T-032 | LeaderboardService | Programmer | S2 | done |
| T-034 | Code review of sprint 3 | Programmer (2nd) | all above | done |

## Sprint 4: Studio integration (2026-11-07, Studio MCP connected)
| ID | Task | Owner | Status | Notes |
|----|------|-------|--------|-------|
| T-004 | 20 prototype segments | Director | done | Already authored in `ServerStorage.Segments`; all pass the contract |
| T-004b | CourseParts, 23 placeholder balls, Lobby, Assets (Present/Trail/DropShadow/Sounds) | Programmer | done | |
| T-035a | Theme StyleSheet + StarterPickUI + HUD | UI Designer | done | Element map in `docs/UI_ELEMENTS.md` |
| T-042 | Get current code into Studio (sync) | Director | done | 213 scripts, no duplicates. StarterPlayer is not synced, so ClientScript was copied by hand |
| T-043 | First full playtest + console fix pass | Chief of Staff | done | Round runs, course builds, ball rolls, checkpoint + coins work |
| T-035b | Wire HUD/StarterPickUI to the client modules | Programmer | done | |
| T-035c | Remaining screens (Shop, Inventory, Daily, Timed, Wheel, StarterPack, Season, Tools, Settings, Upsell) | UI Designer | todo | |

## Sprint 5: Figma UI design, then remaining screens (2026-11-08)
Goal: every remaining screen designed in Figma, approved by the Director, then built in Studio and wired. Figma is the UI source (DECISIONS 2026-11-07): one frame per UI module.
| ID | Task | Owner | Depends on | Status | Acceptance criteria |
|----|------|-------|------------|--------|---------------------|
| T-044 | Figma foundations (variables from Theme tokens, shared components) + HUD, StarterPickUI, Shop, Inventory frames | UI Designer | — | done | Tokens match `docs/UI_ELEMENTS.md`; one 750×390 frame per module; 44 px touch targets; layer names match Studio element names |
| T-045 | Figma: Daily, Timed, Wheel (with odds), StarterPack, Limited | UI Designer | T-044 | done | Same bar; built from T-044 components |
| T-046 | Figma: SeasonPass, Tricks, Tools loadout, Settings, Upsell | UI Designer | T-044 | done | Same bar; built from T-044 components |
| T-050 | Director rework in Figma: smaller HUD, Inventory shows all balls and buys them, Shop is one tabless scrolling page | UI Designer | T-044 | done | See DECISIONS 2026-11-08 |
| T-053 | Figma polish: smaller HUD (under 13% coverage), bigger popups, Starter Pack label, brighter panels | UI Designer | T-050 | done | See brief |
| T-051a | Figma restyle: Daily, Timed, Wheel, StarterPack, Limited, plus Limited sold-out and serial states | UI Designer | T-050, T-045 | done | Matches approved Shop/Inventory look |
| T-051b | Figma restyle: SeasonPass, Tricks, Tools, Settings, Upsell | UI Designer | T-050, T-046 | done | Matches approved Shop/Inventory look |
| T-054 | Blender ball renders for UI (all 23 balls), replacing placeholders in Figma and Studio | 3D Artist | Blender connected | todo | One consistent render style; registered in ASSETS.md |
| T-052 | GDD §10.1, §10.6, §11.4 popup timing update, then UpsellTable/Onboarding to match | Game Designer → Programmer | Director OK (given) | todo | Starter Pack after pick, Crown after checkpoint 1, 90 s popup rule kept |
| T-047 | Director review of Figma frames | Director | T-044–46 | in progress | Frames approved or changes listed |
| T-035c | Build the approved screens in Studio, and update the HUD to the T-050 design | UI Designer | T-047 | blocked | Matches Figma; element map added to `docs/UI_ELEMENTS.md` |
| T-048 | Wire the new screens to client modules | Programmer | T-035c | blocked | Each screen opens and shows live data in play |
| T-049 | QA pass, including T-039 feel test and the unexercised paths in sprint-04 | QA | T-048 | blocked | All acceptance criteria checked; bugs filed |

## Blocked on Studio (open the place with Studio MCP connected)
T-004 asset port (balls + segments) · all UI (StarterPickUI, HUD, Shop, Inventory, Daily, Timed, Wheel, StarterPack, Limited, ToolBar, Tricks, SeasonPass, Upsell, Settings) and their client modules · T-020 segment pool/art · T-021 VFX · T-027 trick animations · T-009 and every QA playtest · M4 live ops.

Statuses: todo · in progress · review · done · blocked

## Backlog (after the Studio work)
| ID | Task | Owner | Notes |
|----|------|-------|-------|
| T-035 | Client UI modules for every system (wire to the authored StarterGui) | UI Designer → Programmer | Network messages are listed in each service header |
| T-036 | `analyticsOnceSteps` saved key, so onboarding funnel steps fire once ever | Programmer | Small; needs a DataTemplate key |
| T-037 | Timed gift AFK stop (`AfkStopSeconds`) | Programmer | Needs a client activity signal |
| T-038 | GDD §7.5 example 2 typo (577 → 578) | Game Designer | Director OK |
| T-039 | M1 feel test: set `PhysicsTable.AnchorTopSpeed`/`JumpVelocityScale`, measure airtime for `MIN_AIRTIME` | Programmer + QA | Studio |
| T-040 | Delete or move `ServerStorage/Archive_PreGDD` (AGENTS.md bans archive folders) | Director | Not ours; it appeared mid-session |
| T-041 | Remove dead `DailyRewardTable.VipCoins` | Programmer | Trivial |

## Blocked on Studio (open the place with Studio MCP connected)
T-004 asset port (balls + segments) · all UI (StarterPickUI, HUD, Shop, Inventory, Daily, Timed, Wheel, StarterPack, Limited, ToolBar, Tricks, SeasonPass, Upsell, Settings) and their client modules · T-020 segment pool/art · T-021 VFX · T-027 trick animations · T-009 and every QA playtest · M4 live ops.

Statuses: todo · in progress · review · done · blocked

## Backlog
| ID | Task | Owner | Milestone | Notes |
|----|------|-------|-----------|-------|
| T-010 | EconomyService + ShopService + InventoryUI/ShopUI (20 balls) | Programmer/UI | M2 | |
| T-011 | DailyRewardService + UI | Programmer/UI | M2 | Restore Streak product |
| T-012 | TimedRewardService + UI | Programmer/UI | M2 | Unlock All product |
| T-013 | SpinWheelService + WheelUI with odds + PolicyService gating | Programmer/UI | M2 | |
| T-014 | StarterPackService + popup/countdown | Programmer/UI | M2 | 15 min from firstJoinAt |
| T-015 | First-fall present (OnboardingService + FirstFallPresent + VFX) | Programmer/VFX | M2 | |
| T-016 | PurchaseService (ProcessReceipt) + GamePassService + core products | Programmer | M2 | Before any paid feature ships |
| T-017 | LimitedBallService (DataStore + MemoryStore reservations + MessagingService) | Programmer | M3 | Needs heavy review + QA |
| T-018 | ModifierService + server-wide/troll products | Programmer | M3 | Needs Director OK |
| T-019 | UpsellService + AnalyticsService funnels + FlagService | Programmer | M3 | |
| T-020 | Segment pool to 45+, art/theme pass | 3D Artist + Designer | M3 | |
| T-021 | Juice pass: boost, checkpoint, reward-fly, wheel VFX + sounds | VFX | M3 | |
| T-022 | Cmdr admin commands | Programmer | M1/M2 | |
| T-025 | GDD: Trick System + Season Pass sections | Game Designer | T-001 | done | Rules, trick list, scoring, caps, sim before/after, prices |
| T-028 | SeasonService + ChallengeService + SeasonPassUI + premium products | Programmer/UI | M2 | Design the UI frame in Figma first |
| T-026 | TrickService + TrickController + trick popups | Programmer/UI | M2 | after T-005 |
| T-027 | 12 rider trick animations + landing blend | Animator | M2 | GDD §7.4 durations ±0.05 s |
| T-023 | ToolService + ToolController + first 3 tools + hotbar UI | Programmer/UI | M2 | Numbers from GDD Gameplay Tools section |
| T-024 | Remaining tools + tool VFX + tool products/passes | Programmer/VFX | M3 | |
