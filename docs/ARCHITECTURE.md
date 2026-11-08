# Ball of Hell: Architecture Plan

**Status:** approved 2026-11-07. §9 answers are logged in `studio/DECISIONS.md` (shared course, 30 segments from a larger pool, Coins only, server-wide and troll products approved, code files auto-sync to Studio).
**Date:** 2026-11-07
**Reference code studied:** `~/Documents/GitHub/Ballin Revamped` (Rojo project, ~5k lines of own Luau)
**UI design source:** [Figma: BallinOfHell](https://www.figma.com/design/Vsk0yM8NFKD8QOLRjKNeqo/BallinOfHell?node-id=0-1) (file key `Vsk0yM8NFKD8QOLRjKNeqo`; Page 1 was empty on 2026-11-07)
**Conventions:** `AGENTS.md` at the project root wins over the reference code for all new code.

> Genre target: a hard "roll your ball through a long hellish course" obby race, in the spirit of the
> bike-obby genre. Mechanics are genre-standard; name, art, segments and branding are our own. We do not
> copy another game's look, levels or logo.

---

## 1. What we learned from Ballin Revamped

### Worth porting (logic, not structure)

| Piece | Reference file | What it does | Plan |
|---|---|---|---|
| Segment chaining | `ServerStorage/Server/Master/RoundHandler/Round/Map/init.lua` | Each track model has `PositionParts.StartPart` / `EndPart`; segment *n* is `PivotTo`'d onto segment *n-1*'s `EndPart`. Picks random models per difficulty tier, adds a checkpoint flag at each joint, ends with an `EndTrack`. | **Keep the authoring contract.** It's what makes "30 random segments" cheap. Rewrite the generator. |
| Obstacle kinds | `.../Map/Track/*`, `Client/StageLoader/*` | BoostPanel, JumpPad, Killbrick, plus tag-driven Rotatable / Move / Disappear animated on the client. | Keep the kinds. Switch to CollectionService tags + attributes and a single registry per kind (AGENTS.md "Tagged behaviour"). |
| Ball movement | `Client/Master/BallSystem.lua` (885 lines) | Client-owned ball. Horizontal velocity blends toward `MoveDirection` (`SmoothMoveRate`, `AirMoveRate`, `SmoothStopRate`), velocity-set jump, double jump, boost with FOV punch, drop shadow, character rides the ball via AlignPosition/AlignOrientation. | **Port the feel**, but swap the hard-coded `Constants` for per-ball stats (§4). |
| Ball setup | `Server/Master/PlayerSetup.lua` | Clones the ball model, adds a trail, `SetNetworkOwner(player)`, tells the client to bind. | Port into `BallService`. |
| Round loop + finish multiplier | `RoundHandler/`, `Round/init.lua` | Round timer. Each finisher speeds up the clock (+0.5×) and raises the coin multiplier. | Keep the idea as a sequenced flow (AGENTS.md "Sequenced flow"). |
| Server modifiers | `Master/Marketplace.lua` | Paid products that change the whole server: Double Jump, Low Gravity, x2 Larger, More Time. | Good monetization. Keep, through `ModifierService` (needs Director OK, see §9). |
| Buy any ball with Robux by rarity | `MarketplaceConstants.DevProds` | One product per rarity tier, applied to the ball the player picked. | Keep, with the server-side target table from AGENTS.md. |
| Single-segment test env | `Server/BallTestEnvironment.lua`, `Client/StageLoader` | Loads one stage to test it. | Becomes a Studio-only `SegmentTest` start step. |

### Must not be ported as-is

1. **Purchases are granted in `PromptProductPurchaseFinished`**, not `ProcessReceipt`. Purchases can be lost, and a spoofed or replayed event can grant items. Rebuild on one `ProcessReceipt` owner.
2. **`PurchaseItem` trusts the client's `BallId`.** A nil lookup errors. The pending Robux target sits in a client-visible `ItemQueue` attribute.
3. **There's no anti-cheat on a client-owned ball.** Checkpoints are server `Touched` with no order, distance or time checks, so teleporting farms coins and wins.
4. **Fall boxes assume a straight +X course**, which breaks on any segment that turns.
5. **There's no rate limiting in `Network`.** It also has old patterns (`tick()`, `pairs`, a global `round`, PlaceId-gated modes, `Master:Init` wiring) that AGENTS.md replaces.
6. **Assets live only in the old Studio place.** Ball models (`ReplicatedStorage.Assets.Balls`) and track segments (`Assets.Tracks/<Tier>/<Theme>/<n>`) aren't on disk. Several ball names reference real Roblox items ("Korblox", "Noob") and must be renamed.

---

## 2. Tech stack

- **Code in files with Rojo** (the reference project already does this, which AGENTS.md allows). Aftman tools: `rojo`, `selene`, `stylua`. Wally for `ProfileStore` and `Trove`. *(Director confirms, §9.)*
- **Data:** ProfileStore, wrapped by one `PlayerData` module.
- **UI design → Studio:** screens are designed in the [Figma file](https://www.figma.com/design/Vsk0yM8NFKD8QOLRjKNeqo/BallinOfHell?node-id=0-1) first: HUD, starter pick, shop, inventory, daily, timed, wheel, starter pack, limited ball, tool hotbar, upsell popups. The UI Designer reads the frames through the Figma MCP (`get_design_context` / `get_screenshot`) and builds them in `StarterGui` to match. One Figma frame per UI module in §3, with the frame name matching the module name (e.g. `WheelUI`). Rarity colours and fonts are Figma variables, mirrored in `Tables/RarityTable`. When Figma and the GDD disagree, raise it with the Chief of Staff.
- **Authored in Studio, not on disk:** UI (`StarterGui`), segment models, ball models, VFX. AGENTS.md says to never build UI in code.
- **Admin:** Cmdr, for give-coins, set-segment, reset-onboarding, stock-debug and similar commands.
- **StreamingEnabled on.** A 30-segment course is long. Segments use `ModelStreamingMode.Atomic`, and client obstacle code only runs on streamed-in segments.

---

## 3. Place layout (AGENTS.md defaults)

```
ServerScriptService.Script                 server entry: requires each child in its own thread
  PlayerData (+ DataTemplate)              only module that touches ProfileStore
  RoundService                             sequenced steps: Intermission → BuildCourse → Race → Results → Teardown
  CourseService                            builds the 30-segment course; owns checkpoints and fall zones
    SegmentPicker, CheckpointBuilder, FallZones
  ProgressService                          per-player checkpoint, falls, finish; validation and anti-cheat
  BallService                              spawns the equipped ball, writes stat attributes, network owner, speed audit
  InventoryService                         owned balls, equip, starter pick, duplicates → coins
  EconomyService                           coins (and any other currency), multipliers
  OnboardingService                        first-join starter pick, first-fall present
  DailyRewardService                       streak calendar
  TimedRewardService                       playtime gifts
  SpinWheelService                         server-rolled wheel, free and paid spins, odds
  StarterPackService                       15-minute offer from first join
  LimitedBallService                       global 1000-unit stock, serial numbers
  ShopService                              coin purchases of balls
  PurchaseService                          the ONLY ProcessReceipt owner; product table → Effect(player)
    Products/                              one plug-in module per product family
  GamePassService                          UserOwnsGamePassAsync and pass perks
  ModifierService                          server-wide paid modifiers (workspace attributes)
  SeasonService                            season pass: XP from validated events, free/premium tiers, claims, season rollover
  ChallengeService                         daily/weekly challenges + rerolls; awards XP via SeasonService
    Objectives/                            one plug-in per objective type (ClearSegments, LandTricks, UseTool…)
  TrickService                             airtime tricks: validates airtime from replicated ball physics, ownership, caps; grants coins
  ToolService                              gameplay tools: ownership, charges, cooldowns, activation validation
    Tools/                                 one plug-in module per tool (contract: CanActivate, Activate(player, ball))
  UpsellService                            decides when to offer what (skip after N falls, etc.)
  AnalyticsService                         economy, funnel and custom events (Roblox AnalyticsService)
  FlagService                              remote-config feature flags and A/B tests
  LeaderboardService                       wins, fastest time (OrderedDataStore)
ServerStorage
  Segments/<Tier>/<SegmentName>            authored segment models (moved out of ReplicatedStorage)
  Balls/<BallId>                           ball models
  CourseParts/                             Start, EndTrack, CheckpointFlag
ReplicatedStorage
  Assets/                                  client-cloned visuals (Present, VFX templates)
  Network                                  one RemoteEvent + one RemoteFunction, rate-limited
  Tables/  BallTable, RarityTable, CourseTable, ProductTable, PassTable, DailyRewardTable,
           TimedRewardTable, WheelTable, StarterPackTable, ModifierTable, UpsellTable, ToolTable, TrickTable, SeasonTable, ChallengeTable
  Modules/ (client, auto-required)
           BallController, CameraController, ObstacleController (tag registries),
           PlayerData (client mirror), MenuManager, HUD, Notifications, RewardFly,
           StarterPickUI, ShopUI, InventoryUI, DailyRewardUI, TimedRewardUI, WheelUI,
           StarterPackUI, LimitedBallUI, FirstFallPresent, UpsellUI, SettingsUI,
           SeasonPassUI (free + premium reward rows, XP bar, challenges),
           TrickController (airtime detection, auto trick picker, character trick animations), TrickPopupUI, TricksUI (loadout/shop/upgrades),
           SeasonXpBar (HUD),
           ToolController + ToolBarUI (hotbar, input, client-predicted effects; Tools/ halves share names with server)
  Utilities/ Signal, Trove, NumberFormat, TimeFormat, RichText, Weighted (shared weighted pick)
StarterPlayerScripts.ClientScript          client entry
StarterGui                                 all UI, authored in Studio
```

---

## 4. Balls: stats and roster

Each ball has three stats that drive `BallController` directly:

| Stat | Drives (from the reference `BallSystem`) | Range |
|---|---|---|
| **Speed** | max horizontal velocity (`MaxForce`) | 1–10 |
| **Acceleration** | `SmoothMoveRate` (how fast you reach top speed) and `AirMoveRate` | 1–10 |
| **Jump** | `JumpPower` impulse | 1–10 |

- `BallTable[id] = { Name, Rarity, Speed, Acceleration, Jump, Source, Price, ModelName, Order, SeasonId? }`. `Source` is one of `Starter | Coins | Wheel | Daily | Timed | StarterPack | RobuxLimited | Seasonal`. Seasonal balls are extra, outside the 21.
- A shared `BallStats.Resolve(stats, passes, modifiers)` turns 1–10 ratings into physics numbers. The server writes the result as attributes on the ball model. The client reads them and **predicts**, and the server **audits** (AGENTS.md: speed is decided or checked on the server).
- **Budget by rarity:** total stat points grow with rarity (e.g. Basic 9, Common 11, Rare 13, Epic 15, Legendary 17, Mythic 19, Limited 21). Each ball has a distinct shape (fast-but-floaty, grippy, bouncy), so a cheaper ball can still suit a player's style.
- **Roster: 20 earnable + 1 limited = 21.**
  - 3 **starters** (Basic), picked on first join: *Sprinter* (speed), *Grip* (acceleration), *Bouncer* (jump). The two you skip are buyable later for coins.
  - 13 coin-shop balls across Common → Mythic.
  - 4 **exclusive** balls: one each from the wheel, the daily streak (day 7), timed rewards (60-min gift) and the Starter Pack.
  - 1 **Robux limited** ball, 1000 ever, with a serial number (§6.6).
  - The Game Designer finalizes names and numbers in the GDD. The reference place's 21 models can be reskinned and reused if the Director owns them.

---

## 5. The course: 30 random segments

### Segment authoring contract (one per model in `ServerStorage.Segments/<Tier>/`)

- `PositionParts.StartPart` and `PositionParts.EndPart`, kept from the reference. EndPart's CFrame is where the next segment attaches, so segments **may turn and climb**.
- Attributes: `Tier` (string), `Theme` (string), `Weight` (number, default 1), `ParTime` (seconds, used by anti-cheat and upsell).
- Obstacles are tagged `BoostPanel` / `JumpPad` / `KillBrick` / `Rotating` / `Moving` / `Vanishing` / `GrappleAnchor`, with configuration in attributes (`BoostSpeed`, `JumpPower`, `Axis`, `Period`…).
- `CourseService` validates each segment on load and **warns and skips** a broken one (AGENTS.md "Misconfiguration").

### Generation (`CourseTable`)

The difficulty curve is a list of 30 slots, each naming a tier. For example: slots 1–4 Beginner, 5–9 Easy, 10–15 Medium, 16–21 Hard, 22–27 Insane, 28–29 Hell, 30 Finale. `SegmentPicker` draws from each tier with `Weighted`, never reuses a segment in one course while the tier pool is big enough (otherwise the GDD §5.3 fallback allows non-adjacent repeats), and avoids repeating the last round's pick for each slot. It uses one `Random` per module and logs the seed, so a bad course can be rebuilt in Studio.

Building is queued (one segment per frame) so the server doesn't hitch. Old segments are destroyed only after every player is reset.

### Checkpoints, falls and finish (`ProgressService`)

- A checkpoint sits at every joint (29 + finish). The server accepts checkpoint *n* only if it's `current + 1`, the ball is within range of the flag, and at least `ParTime × MIN_PAR_FRACTION` has passed since the last one. Anything else is ignored and counted as a strike.
- Falls use **one fall volume per segment**, built from that segment's bounding box (works on turns), plus a global Y floor. On a fall the server respawns the player at their checkpoint and increments `fallsThisSegment`. That count feeds `UpsellService` (skip offer) and `OnboardingService` (first-fall present).
- The finish works like the reference: rewards, then the round clock speeds up and the multiplier rises for everyone.
- Every reward is server-side and driven by data. The client animates gains from the data update (AGENTS.md "Feedback").

### Round flow (`RoundService` steps)

`Intermission (lobby, ~20 s)` → `BuildCourse` → `Race (timer, ~20 min, tunable)` → `Results` → `Teardown`. Each step has `Run` and `Skip`. A Studio-only `START_STEP` and `SegmentTest` mode let builders drop straight into one segment.

---

## 6. Retention and reward systems

All of these are server-owned, with saved keys in `DataTemplate` (camelCase). Each gets a client UI module and an `OnUpdate`-driven HUD badge.

### 6.1 First play: pick 1 of 3 starters (`OnboardingService`)
- `hasPickedStarter = false` → client shows `StarterPickUI` (3 cards with stat bars). The ball doesn't spawn until a pick is made.
- The server whitelists the 3 starter ids. The pick grants the ball and equips it, and is idempotent.
- Next comes a quick "roll here" arrow tutorial on segment 1. The Starter Pack popup appears after the first checkpoint (better conversion than on join).

### 6.2 First-fall present
- The trigger is `ProgressService` reporting a fall while `firstFallGiftClaimed == false` and the player is in their first session (`sessionCount == 1`).
- The server records a pending gift in a runtime table. The client spawns a glowing present at the respawn point (a client-only visual cloned from `ReplicatedStorage.Assets.Present`), and tapping it fires `ClaimFirstFallGift`.
- The server checks the pending gift, grants it (e.g. coins + 2 wheel spins + 10 min of 2× coins), sets the flag and clears the pending gift. The reward flies into the HUD, then a soft upsell: "Want more? Starter Pack ends in mm:ss".
- *Proposed extension (needs approval):* "comeback presents" after 5 falls on one segment during the first 3 sessions.

### 6.3 Daily rewards (`DailyRewardService`)
- A 7-day streak calendar on UTC days from `workspace:GetServerTimeNow()`. Day 7 is the big one (exclusive ball on the first cycle, then spins and coins).
- Saved: `dailyStreak`, `lastDailyClaimDay`. Missing a day resets the streak, and a **Restore Streak** product offers to save it.
- VIP pass: +50% daily coins.

### 6.4 Timed (playtime) rewards (`TimedRewardService`)
- Gifts at session playtime milestones (e.g. 2, 5, 10, 15, 20, 30, 45, 60 min). The 60-min gift is an exclusive ball, earned once.
- Playtime counts on the server and resets each session (keeps sessions long, which helps Premium payouts).
- An **Unlock All Now** product claims every remaining gift for this session.

### 6.5 Starter Pack, 15 minutes from first join (`StarterPackService`)
- Saved: `firstJoinAt` (server time, set once), `starterPackBought`. The offer is live while `now - firstJoinAt < 15 min` and not bought.
- The countdown is **real wall-clock** time, so it keeps running if they leave. Once expired it never comes back (no fake timer).
- Contents (draft): Starter Pack exclusive ball + coins + 5 spins + 30 min of 2× coins. It's one dev product, and the pack goes through `PurchaseService`.
- Shows as an HUD button with a countdown, a popup after the first checkpoint, and a reminder at 2:00 left.

### 6.6 Spin the wheel (`SpinWheelService`)
- `WheelTable` has 8 slices with weights: coins in several sizes, spins, a 2× coins boost, a skip token, and a rare wheel-exclusive ball (a duplicate converts to coins).
- **The server rolls** (one `Random`) and saves the result before replying. The client animates the wheel to land on the server's slice.
- Spin sources: 1 free spin every 8 h, daily and timed rewards, first-fall gift, and paid spin packs (1 / 5 / 15).
- **Policy (required):** paid spins are paid random items, so the **odds are shown in the wheel UI** before purchase. Paid spin products are hidden for players whose `PolicyService` result has `ArePaidRandomItemsRestricted`. They still get free spins.

### 6.7 Limited ball, 1000 ever (`LimitedBallService`)
- It's a **dev product**, not a game pass, because passes can't be capped. One per player.
- **Global stock:** DataStore key `LimitedStock` → `{ sold, log }`, written only with `UpdateAsync`. Active checkouts are held in a MemoryStore HashMap with a 5-minute TTL.
  1. The client asks to buy. The server checks it isn't owned, then checks `sold + activeReservations < 1000` and **reserves a slot**. Only then does it prompt.
  2. In `ProcessReceipt`: an idempotent `UpdateAsync` (keyed by `PurchaseId`, so a Roblox retry can't sell twice) increments `sold` and assigns serial `#sold`. The ball goes into the profile with its serial, and the reservation is released.
  3. Sold out at receipt time should be impossible because of reservations. If it happens anyway (outage), grant a documented consolation (big coin pack + exclusive trail) and log it. Roblox can't refund.
- **Live counter:** MessagingService broadcast on each sale, plus a 60-second poll, updates `workspace:GetAttribute("LimitedRemaining")`. The UI shows "37 / 1000 left" and each owner's "#137".
- Admin (Cmdr): view stock and the sale log. The stock number shown is always the real one.

---

## 6.8 Gameplay tools (`ToolService`, added 2026-11-07)
- Usable items activated during a run (grapple, dash, shield, glider and so on). The GDD's "Gameplay Tools" section has the roster and numbers.
- **Plug-in variants.** `ToolService/Tools/<Name>` on the server and `Modules/ToolController/Tools/<Name>` on the client share the same name. `ToolTable` holds the data: `Cooldown`, `Charges`, `Duration`, `Source`, `Price`.
- **Server authority.** The client asks `UseTool(toolId)`. The server checks ownership, the equipped slot, charges, cooldown, round state, and the segment's `NoTools` / `ToolRequired` attributes, then spends the charge and applies or authorises the effect. The client predicts the motion for feel, and the ball's speed audit allows for an active tool's impulse.
- **Saved keys:** `ownedTools`, `toolCharges`, `equippedTools`. Per-round charges are runtime state in ToolService.
- **Hotbar:** 2 slots (a 3rd with a pass). Mobile buttons, PC keys 1/2/3, gamepad buttons.

## 6.9 Trick system (`TrickService`, added 2026-11-07)
- Once the ball has been airborne long enough, the rider performs tricks **automatically** (character animations, no player input) for bonus coins. Combos chain within one airtime, and landing mid-trick is a bail. The GDD's "Trick System" section has the rules and numbers.
- **Client** (`TrickController`) detects eligibility, auto-picks tricks that fit the predicted remaining airtime, plays animations (the Animator supplies them; ids in `TrickTable`) and predicts the score popup.
- **Server** (`TrickService`) samples the client-owned ball's replicated position and velocity to confirm real airtime and a clean landing. It checks trick ownership and that the trick durations fit inside the airtime, applies the per-segment and per-round caps, then grants coins through `EconomyService`. It ignores anything inside a fall volume.
- **Saved keys:** see GDD §15.9 (`ownedTricks`, `equippedTricks`, `trickLevels`, …). TrickService's 10 Hz ball sampling shares BallService's speed-audit loop.

## 6.10 Season pass (`SeasonService`, added 2026-11-07)
- Each season (around 30 days) has a free track and a premium track of tiers. XP comes only from server-validated events: checkpoints, finishes, tricks, logins, and daily/weekly challenges. Every other service reports events to `SeasonService.AddXp(player, source, amount)`, and challenges are plug-ins that listen to those same events.
- **Season id, start and end** come from remote config (`FlagService`), with a safe default. Rollover auto-claims earned but unclaimed rewards and then resets XP.
- **Premium** is a dev product bought once per season, not a game pass, because passes can't reset. The receipt sets `season.hasPremium` and retroactively unlocks the premium tiers already reached. There are also Buy-tier and bundle products.
- **Saved keys:** `season` (`id`, `xp`, `claimedFree`, `claimedPremium`, `hasPremium`) and challenge progress. Final shape comes from the GDD.

## 7. Monetization map ("monetization heavy")

The Director sets all prices. The Game Designer proposes a price sheet in the GDD.

**Game passes** (`PassTable`, checked with `UserOwnsGamePassAsync`):
VIP (2× daily, chat tag, +1 free spin/day) · 2× Coins · Double Jump (toggle in settings, from the reference) · Turbo (+10% Speed stat) · Lucky (2× free spin rate) · Trails Pack (cosmetic).

**Developer products** (`ProductTable`, one plug-in per family under `PurchaseService/Products`):

| Family | Products |
|---|---|
| Progress | Skip Segment · Skip 5 Segments · Respawn Here (keep position on next fall, once) |
| Currency | Coin packs ×5 tiers (best-value badge on the biggest) |
| Wheel | 1 / 5 / 15 spins |
| Season | Premium Pass (per season) · Premium+ bundle · Buy 1 / 10 tiers |
| Tools | Tool bundles · charge refills · permanent "unlimited" passes per tool · Shield upsell after repeated falls |
| Offers | Starter Pack (15 min) · Limited Ball (1000) · Restore Daily Streak · Unlock All Timed Gifts · 2× Coins 30 min |
| Balls | Buy-by-rarity (reference system): instantly unlock the shop ball you're looking at |
| Server-wide | Low Gravity · Double Jump for all · Giant Balls · +2 min round time (*needs Director OK*) |
| Troll | Shrink everyone · Slow everyone (15 s, capped, cooldown) (*needs Director OK*) |
| Gifting | Gift any ball or pack to another player in the server |

**When offers appear** (`UpsellService` + `UpsellTable`, all flag-controlled, each capped per session so it doesn't nag):

| Trigger | Offer |
|---|---|
| 3 falls on the same segment | Skip Segment, then Skip 5 |
| Under 60 s left in the round and not near the finish | Skip 5 / +2 min |
| Starter picked, first checkpoint reached | Starter Pack popup |
| Wheel opened with 0 spins | Spin packs |
| Locked ball viewed in shop | Coins *or* Robux unlock |
| Streak broken | Restore Streak |
| 3+ timed gifts still waiting | Unlock All |
| Limited stock under 100 | Server-wide "Only N left!" toast |

**Measurement:** `AnalyticsService` funnels for onboarding (join → pick → checkpoint 1 → first fall → present → checkpoint 5) and purchases (offer shown → prompted → bought). Economy events for every coin source and sink. `FlagService` A/B tests prices and upsell timing. Without this, monetization tuning is guesswork.

**Guardrails:** real scarcity and real timers only. Odds disclosure and PolicyService for paid random items. All grants happen in `ProcessReceipt` and return `false` to retry if data isn't loaded. Store-target purchases (buy this ball, gift this player) go in a server table keyed by player before prompting, per AGENTS.md.

---

## 8. Saved data (`DataTemplate`, first draft; changes need Director OK)

```lua
coins = 0, wins = 0, bestTime = 0,
ownedBalls = {},            -- [ballId] = { at = time, serial = n? }
equippedBall = "",
hasPickedStarter = false,
firstJoinAt = 0, sessionCount = 0, firstFallGiftClaimed = false,
dailyStreak = 0, lastDailyClaimDay = -1,
timedRewardsEverClaimed = {}, -- one-off exclusives only; per-session progress is runtime state
spins = 0, lastFreeSpinAt = 0,
starterPackBought = false,
boosts = {},                -- [boostId] = expiresAt
settings = { doubleJump = true, sound = true, otherBallVfx = true },
purchaseLog = {},           -- recent PurchaseIds, for idempotent receipts
stats = { falls = 0, segmentsCleared = 0, robuxSpent = 0 },
```

The store name is new (`PlayerData_v1`). There's no migration from the reference game's store unless the Director wants it.

---

## 9. Needs the Director's call

1. **Course model.** A shared course rebuilt every round (reference behavior, *recommended*), or persistent personal progress through one long course?
2. **"30 randomly segmented tracks".** Each run is 30 segments drawn at random from a larger pool (*recommended*; pool of ~45 at launch, ~20 for the prototype), or 30 hand-made segments shuffled?
3. **Toolchain and git.** Rojo files on disk (*recommended*) or Studio-only scripts? Commit after each reviewed task?
4. **Currency.** Coins only plus direct Robux (*recommended*, simpler), or Coins + Gems premium currency?
5. **Server-wide and troll products** (AGENTS.md requires your OK): include them?
6. **Reuse the Ballin Revamped assets** (21 ball models, track segments)? Do you own them? The Studio MCP isn't connected this session; open the new place in Studio so the team can import.
7. **Working title and theme.** Keep "BallinOfHell" with an original hell/lava art direction, or pick something less close to "Bike of Hell"?
8. **Prices.** The designer will propose a full price sheet. Limited ball and Starter Pack prices are yours.

---

## 10. Roadmap

| Milestone | Goal |
|---|---|
| **M1 Prototype** | Join → pick 1 of 3 starter balls → roll through a generated 30-segment course with checkpoints, falls and finish; per-ball stats feel different; data saves. |
| **M2 MVP** | Coins economy, shop and inventory with all 20 balls, daily, timed, wheel, starter pack, first-fall present, core purchases (skip, coins, passes), HUD. |
| **M3 Launch** | Limited ball, server modifiers, upsells, analytics and flags, 45+ segments with art pass, VFX/juice, mobile performance, policy and odds checks, QA. |
| **M4 Live ops** | Events, new segment packs, leaderboards, price A/B tests, new balls. |

Sprint 1 tasks are on `studio/BOARD.md`.
