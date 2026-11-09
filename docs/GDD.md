# Ball of Hell: Game Design Document

**Status:** v1 draft for Director review (T-001)
**Date:** 2026-11-07
**Owner:** Game Designer
**Builds on:** `docs/ARCHITECTURE.md` (approved) and `studio/DECISIONS.md`. This document does not change the architecture. Where a number here needs a new saved key or a change to an approved plan, it is listed in §15 Follow-ups. **T-025 (2026-11-07)** added §7 Trick System and §8 Season Pass (sections 9–15 renumbered from 7–13).

> **How to read this.** Every table in a box labelled `Tables/...` is meant to be copied straight into that config module. Numbers marked *(tune)* are first guesses that M1/M2 playtests must confirm. Names are originals. We don't copy another game's names, levels or art.

---

## Contents

1. Pitch, pillars, target player
2. Core loop and round flow
3. Controls and ball physics
4. Ball roster
5. The course
6. Gameplay Tools *(Director-approved scope addition)*
7. Trick System *(Director-approved scope addition)*
8. Season Pass *(Director-approved scope addition)*
9. Economy and simulation
10. Reward systems
11. Monetization
12. Analytics plan
13. Acceptance criteria
14. Open questions for the Director
15. Follow-ups (needs another owner or a Director OK)

---

## 1. Pitch, pillars, target player

### Pitch
**Ball of Hell** is a chaotic obby race. You ride on top of a rolling ball through a 30-segment course down into hell. Every round the course is rebuilt from random segments, and they get harder as you go, from the Ash Wastes at the top to the Throne of Embers at the very bottom. Everyone in the server races the same course at the same time. Every finisher speeds up the clock and raises the coin multiplier for everyone still racing. Collect balls that each roll differently, equip tools that get you out of trouble, and try to reach the bottom before the clock runs out.

### Design pillars
| # | Pillar | What it means for builders |
|---|---|---|
| P1 | **Fall, laugh, go again** | A respawn takes 1.5 s or less. A fall is never a loss of more than one segment. No menus between you and the next try. |
| P2 | **Always a next goal** | The HUD always shows one goal line ("Reach segment 5", "Buy Cinder: 320/400"). There's always a badge to tap. |
| P3 | **Every ball and tool feels different, none is required** | Stats change *how* you roll, not *whether* you can finish. Every required jump can be made with the worst stats and no tools. |
| P4 | **Hell is earned** | Paid help (skips, tools, boosts) can get you deeper, but you can't buy the Finale. The last segment must be rolled by hand. |

### Target player and session
- **Age 9–15, about 75% mobile** (phone first, then tablet, PC, console).
- **Session target:** median 20–25 min, one full round (≈21.5 min) plus lobby time. Stretch: 45 min (2 rounds) for engaged players.
- **Readability rule:** any system must be understandable in 5 seconds from an icon, a number or a coloured bar. If it needs a sentence, it needs a tip (§10.1).

---

## 2. Core loop and round flow

### Core loop
```
Join → (first time: pick starter) → Race the course → earn Coins at every checkpoint
   → Results → spend Coins on balls / tools, claim gifts, spin → next round (rebuilt course)
```
Meta loop: daily streak, playtime gifts, free spins, collecting all 21 balls, 9 tools and 10 tricks, the 30-day Season Pass (§8), wins and best-time leaderboards.
In the race: big air makes your rider do automatic tricks for bonus coins (§7).

### Round flow (`RoundService` steps)

| Step | Duration | What happens | UI |
|---|---|---|---|
| **Intermission** | 20 s | Players are in the lobby (shop, wheel, gifts open). If 0 players are in the server, the step waits. | Big "Next race in 0:20". Countdown beeps at 5..1. |
| **BuildCourse** | target ≤ 3 s (30 segments, one per frame) | `SegmentPicker` draws 30 segments (§5.3), builds them, then teleports every player into the start pen. | Lobby fades to the start pen; "Building hell…" spinner if it takes over 1 s. |
| **Countdown** | 3 s | Gate is closed, balls are frozen. | "3, 2, 1, ROLL!" |
| **Race** | 20:00 (1200 s) of *round clock* *(tune)* | Players race. Checkpoint coins are paid live. Finishers raise the multiplier and speed up the clock. | Timer, "Segment 12/30", coin multiplier badge. |
| **Results** | 10 s | Race ends when the round clock hits 0. Everyone sees a results card. | Top 3 finishers, your furthest segment, coins earned this round, "Best!" if new best time. |
| **Teardown** | ≤ 3 s | Players are reset to the lobby first, then old segments are destroyed. | Fade. |

**Full cycle:** 20 + 3 + 3 + 1200 + 10 + 3 ≈ **1,239 s (≈ 20.7 min)** at normal clock speed. The simulation's mean real race time is **18.8 min** because finishers speed up the clock.

**Late joiners** spawn at the start (checkpoint 0) of the current course and can race straight away. If under 60 s of round clock remains they wait in the lobby for the next round.

### Finish multiplier and clock speed-up

When a player crosses the finish (end of slot 30):

| Rule | Value |
|---|---|
| Coin multiplier (`RoundMultiplier`) | starts **×1.0**, **+0.5 per unique finisher**, cap **×3.0** |
| Clock rate (`ClockRate`) | starts **1.0×**, **+0.25 per unique finisher**, cap **2.5×** |
| What the multiplier affects | All checkpoint and finish coins earned by anyone for the rest of this round. Each finisher's own finish reward uses the multiplier *before* their own finish adds to it. |
| Reset | Both reset at the start of each round. |

Round clock: `remaining -= dt × ClockRate`. Shown as "Clock ×1.5" next to the timer when above 1.

**Worked example:** 2 players have finished. The multiplier is ×2.0 and the clock is 1.5×. A third player clears a Hard checkpoint (5 coins) with the 2× Coins pass: 5 × 2.0 × 2 = **20 coins**. When the third player then finishes: (100 + 20 for 3rd place) × 2.0 × 2 = **480 coins**, and the multiplier becomes ×2.5, the clock 1.75×.

UI: on each finish, all players get a toast "**{Name} finished! Coins ×2.5, clock ×1.75**" and the multiplier badge pulses.

---

## 3. Controls and ball physics

### Controls
| Action | Mobile | PC | Gamepad |
|---|---|---|---|
| Roll | Dynamic thumbstick (left half of screen) | WASD / arrow keys | Left stick |
| Camera | Drag right half | Mouse (right-drag) | Right stick |
| Jump (and double jump) | Jump button, bottom-right, 96 px | Space | A |
| Tool slot 1 / 2 / 3 | Three 64 px round buttons in an arc above-left of Jump | 1 / 2 / 3 | X / Y / RB |
| Menu | Left-edge menu buttons | M or click | Start (opens menu), then D-pad |
| Tricks | **No input.** Tricks play automatically on big air (§7) | none | none |

Mobile layout rule: no gameplay button within 24 px of the screen edge or over the thumbstick zone. Tool buttons show a radial cooldown sweep and a charge count pip (top-right of the button).

### Stat → physics formula (`BallStats.Resolve`)

Anchor: **rating 5 equals the reference `BallSystem` constants** (MaxForce 0.12, SmoothMoveRate 10, AirMoveRate 6, JumpPower 0.25). SmoothStopRate is **20** for every ball (2026-11-09: letting go on the ground stops far quicker than you accelerate). While airborne and steering, top speed is **1.25×** the ground top speed (`PhysicsTable.AirTopSpeedMultiplier`, *tune*); the speed audit allows for it. Double jump keeps the reference 1.1× JumpPower.

| Stat (1–10) | Multiplier `m(r)` | Drives | Range at r=1 … r=10 |
|---|---|---|---|
| **Speed** | `0.80 + 0.04·r` | `MaxForce = 0.12 · m` | 0.1008 … 0.1440 (0.84× … 1.20×) |
| **Acceleration** | `0.60 + 0.08·r` | `SmoothMoveRate = 10 · m`, `AirMoveRate = 6 · m` | 6.8/4.08 … 14.0/8.40 (0.68× … 1.40×) |
| **Jump** | `0.85 + 0.03·r` | `JumpPower = 0.25 · m` | 0.2200 … 0.2875 (0.88× … 1.15×). Jump **height** scales with m², so 0.77× … 1.32×. |

Modifiers applied after the stat (in this order, all multiply):
- **Turbo pass:** `MaxForce × 1.10`.
- **Slow Everyone (troll):** `MaxForce × 0.70` while active.
- **Boost panels / Rocket Burst:** temporary, see §5 and §6.
- Gravity changes (Low Gravity, Gravity Coil) change `workspace.Gravity` locally for that ball's controller, floor 0.4 × 196.2 (§6.6).

Don't round in code. Store the resolved numbers as attributes on the ball (`MaxForce`, `SmoothMoveRate`, `AirMoveRate`, `JumpPower`).

**Full table (copy into `Tables/BallStatCurve` or compute from the formula):**

| r | MaxForce | SmoothMoveRate | AirMoveRate | Time to 90% top speed (ln10 / Smooth) | JumpPower | Jump height vs r5 |
|---|---|---|---|---|---|---|
| 1 | 0.1008 | 6.8 | 4.08 | 0.34 s | 0.2200 | 0.77× |
| 2 | 0.1056 | 7.6 | 4.56 | 0.30 s | 0.2275 | 0.83× |
| 3 | 0.1104 | 8.4 | 5.04 | 0.27 s | 0.2350 | 0.88× |
| 4 | 0.1152 | 9.2 | 5.52 | 0.25 s | 0.2425 | 0.94× |
| 5 | 0.1200 | 10.0 | 6.00 | 0.23 s | 0.2500 | 1.00× |
| 6 | 0.1248 | 10.8 | 6.48 | 0.21 s | 0.2575 | 1.06× |
| 7 | 0.1296 | 11.6 | 6.96 | 0.20 s | 0.2650 | 1.12× |
| 8 | 0.1344 | 12.4 | 7.44 | 0.19 s | 0.2725 | 1.19× |
| 9 | 0.1392 | 13.2 | 7.92 | 0.17 s | 0.2800 | 1.25× |
| 10 | 0.1440 | 14.0 | 8.40 | 0.16 s | 0.2875 | 1.32× |

**Worked examples**
1. *Sprinter* (S5 A2 J2), no passes: MaxForce 0.12, Smooth 7.6 / Air 4.56, JumpPower 0.2275 (height 0.83×). Fast but slow to get going and a low jumper.
2. *Void Maw* (S9 A6 J4) with Turbo: MaxForce 0.12 × 1.16 × 1.10 = **0.1531**; Smooth 10.8 / Air 6.48; JumpPower 0.2425.
3. *Bouncer* (S2 A2 J5) during Slow Everyone: MaxForce 0.12 × 0.88 × 0.70 = **0.0739**.

**Server speed audit (`BallService`):** allowed horizontal speed = expected top speed for the resolved MaxForce × **1.25** tolerance. During a boost panel or Rocket Burst window, use the boosted value × 1.25 for the window plus **0.5 s** grace. Three over-limit samples in 2 s count as one strike (same strike counter as `ProgressService`).

> Note: the reference applied `MaxForce *= 0.6` in its normal mode (`BallSystem.lua` line 264), so the old "felt" speed may be 0.072, not 0.12. The M1 feel test decides the base; the multipliers above don't change. See §15.

UI: stat bars on ball cards are 10 pips, coloured by rarity. A small "+10%" chip on the Speed bar when Turbo is owned.

---

## 4. Ball roster

### Rarity table (`Tables/RarityTable`)

| Rarity | Stat budget (S+A+J) | Colour (hex) | Robux unlock (buy-by-rarity) | Duplicate → coins |
|---|---|---|---|---|
| Basic | 9 | `#9E9E9E` grey | 25 | 75 |
| Common | 11 | `#4CAF50` green | 49 | 200 |
| Rare | 13 | `#2196F3` blue | 99 | 600 |
| Epic | 15 | `#9C27B0` purple | 199 | 1,500 |
| Legendary | 17 | `#FF9800` orange | 399 | 2,500 |
| Mythic | 19 | `#F44336` red | 799 | 5,000 |
| Limited | 21 | `#FFD54F` gold + shimmer | n/a (own product) | n/a |

Every stat is 1–10 and each ball's stats sum to exactly its rarity budget. Exclusive balls also show an "EXCLUSIVE" ribbon in their rarity colour.

### Roster (`Tables/BallTable`)

`ModelName` reuses the Ballin Revamped model (Director owns them). The two real-item names are renamed: Korblox → **Doom Knight**, Noob → **Imp**.

| Order | Id | Name | Rarity | Spd | Acc | Jmp | Sum | Source | Coin price | Robux | ModelName | Identity |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `sprinter` | Sprinter | Basic | 5 | 2 | 2 | 9 | Starter (else Coins) | 150 | 25 | Default | Fast once it gets going. |
| 2 | `grip` | Grip | Basic | 2 | 5 | 2 | 9 | Starter (else Coins) | 150 | 25 | Earth | Turns on a coin, safest for beginners. |
| 3 | `bouncer` | Bouncer | Basic | 2 | 2 | 5 | 9 | Starter (else Coins) | 150 | 25 | BeachBall | Jumps high, rolls slow. |
| 4 | `cinder` | Cinder | Common | 5 | 3 | 3 | 11 | Coins | 400 | 49 | Coconut | A charred all-rounder with a speed lean. |
| 5 | `ashrock` | Ash Rock | Common | 3 | 5 | 3 | 11 | Coins | 450 | 49 | Asteroid | Heavy grip for twisty paths. |
| 6 | `boneroller` | Bone Roller | Common | 3 | 3 | 5 | 11 | Coins | 500 | 49 | Skeleton | Rattling hopper. |
| 7 | `jackoblaze` | Jack-o'-Blaze | Rare | 6 | 4 | 3 | 13 | Coins | 1,200 | 99 | Pumpkin | Burning pumpkin built for straights. |
| 8 | `hexcode` | Hex Code | Rare | 4 | 6 | 3 | 13 | Coins | 1,250 | 99 | Binary | Precise and twitchy. |
| 9 | `stormcell` | Storm Cell | Rare | 4 | 3 | 6 | 13 | Coins | 1,300 | 99 | Electricity | Crackling high jumper. |
| 10 | `brimstar` | Brimstar | Epic | 7 | 4 | 4 | 15 | Coins | 3,000 | 199 | StarBall | A falling star of sulphur. |
| 11 | `cursedglyph` | Cursed Glyph | Epic | 4 | 7 | 4 | 15 | Coins | 3,100 | 199 | Hieroglyph | Ancient grip, never slides. |
| 12 | `doomknight` | Doom Knight | Epic | 5 | 5 | 5 | 15 | Coins | 3,250 | 199 | Korblox | Perfectly balanced dark armour. |
| 13 | `ringoffire` | Ring of Fire | Legendary | 8 | 5 | 4 | 17 | Coins | 7,500 | 399 | Saturn | Planet wrapped in flame, a speedster. |
| 14 | `hellcomet` | Hell Comet | Legendary | 6 | 4 | 7 | 17 | Coins | 8,000 | 399 | CometBall | Leaves a burning tail, flies far. |
| 15 | `voidmaw` | Void Maw | Mythic | 9 | 6 | 4 | 19 | Coins | 17,500 | 799 | BlackHole | The fastest thing in hell. |
| 16 | `soulshard` | Soul Shard | Mythic | 6 | 6 | 7 | 19 | Coins | 19,000 | 799 | ShardBall | Crystal of trapped souls, does everything well. |
| 17 | `smokewraith` | Smoke Wraith | Legendary | 6 | 7 | 4 | 17 | Wheel (exclusive) | n/a | n/a | SmokeBall | Drifts like smoke, 2% wheel slice. |
| 18 | `emberglow` | Ember Glow | Epic | 5 | 6 | 4 | 15 | Daily day 7 (exclusive) | n/a | n/a | GlowingBall | A loyal glowing coal. |
| 19 | `hellfirekick` | Hellfire Kick | Epic | 4 | 5 | 6 | 15 | Timed 60-min gift (exclusive) | n/a | n/a | ChargedSoccerball | Charged ball that loves to hop. |
| 20 | `imp` | Imp | Legendary | 7 | 5 | 5 | 17 | Starter Pack (exclusive) | n/a | n/a | Noob (reskin with horns + tail) | A grinning little devil. |
| 21 | `crownofhell` | Crown of Hell | Limited | 8 | 7 | 6 | 21 | Robux limited, 1,000 ever | n/a | Director sets: suggested 1,499 | NorthStarBall (gold reskin) | Serial-numbered crown of the underworld. |

Rules:
- The two starters a player didn't pick show in the shop as Coins 150 / Robux 25.
- Exclusive balls are never sold for Coins or by rarity, and can't be gifted.
- **Equip** is free and instant in the lobby. During a race, equipping takes effect on your next respawn (the ball is swapped at the checkpoint).
- Source values map to the architecture's enum: `Starter | Coins | Wheel | Daily | Timed | StarterPack | RobuxLimited`, plus **`Seasonal`** for season-pass balls (§8.5). Seasonal balls are extra to the 21-ball roster and its collection count.

---

## 5. The course

### 5.1 Tiers (`Tables/CourseTable.Tiers`)

| Tier | Theme(s) preferred | ParTime target (s) | Min path width (studs) | Checkpoint coins | Obstacles allowed | Tool cap per segment (§6.6) |
|---|---|---|---|---|---|---|
| Beginner | Ash Wastes | 12 | 16 | 2 | BoostPanel, JumpPad, edge KillBricks | no cap |
| Easy | Ash Wastes, Brimstone Caves | 15 | 12 | 3 | + slow Rotating, Moving | no cap |
| Medium | Brimstone Caves, Lava Falls | 18 | 10 | 4 | + KillBrick floors, faster Rotating | no cap |
| Hard | Lava Falls, Bone Yard | 22 | 8 | 5 | + Vanishing | 3 |
| Insane | Bone Yard, Inferno Forge | 26 | 6 | 7 | all, combined | 2 |
| Hell | Soul Abyss | 30 | 5 | 10 | all, fast timings | 1 |
| Finale | Throne of Embers | 40 | 5 | finish reward | signature set-piece | 1, and no skips |

### 5.2 The 30-slot difficulty curve (`CourseTable.Slots`)

| Slots | Tier | Count | Par sum (s) | Coins at ×1 |
|---|---|---|---|---|
| 1–4 | Beginner | 4 | 48 | 8 |
| 5–9 | Easy | 5 | 75 | 15 |
| 10–15 | Medium | 6 | 108 | 24 |
| 16–21 | Hard | 6 | 132 | 30 |
| 22–27 | Insane | 6 | 156 | 42 |
| 28–29 | Hell | 2 | 60 | 20 |
| 30 | Finale | 1 | 40 | finish 100 (+50/30/20 for 1st/2nd/3rd) |
| **Total** | | **30** | **619 s ≈ 10.3 min clean** | **139 + finish** |

A clean expert run is ≈ 10–12 min. An average player falls a lot and, in simulation, reaches **segment ~27** in the 20-min timer. Only ~5% of average players and ~96% of skilled players finish (§9.4). That makes the finish feel earned, and the late tiers are where Skip and tools sell.

### 5.3 Segment picker rules (`SegmentPicker`)
1. For each slot in order, collect segments of that tier that pass validation.
2. Remove segments already used in this course. Weighted-pick from the rest (`Weight`, default 1).
3. Avoid the segment used in the same slot last round (soft rule: skip if there's another choice).
4. **Small pool fallback (prototype):** if a tier runs out, reuse that tier's least-recently-used segment, but never in two adjacent slots. *(The architecture says "never reuses", which can't work with a 20-segment pool. See §15.)*
5. At most **3 `ToolRequired` segments** per course, and never two in a row.
6. One `Random` per module. Log the seed and the 30 segment names at build.

**Pool sizes:** prototype 20 (Beginner 4, Easy 4, Medium 3, Hard 3, Insane 3, Hell 2, Finale 1). Launch 45 (Beginner 6, Easy 7, Medium 8, Hard 8, Insane 8, Hell 5, Finale 3).

### 5.4 Segment authoring rules (for level designers)

**Contract (per model in `ServerStorage.Segments/<Tier>/`):**

| Item | Type | Rule |
|---|---|---|
| `PositionParts.StartPart` / `EndPart` | Part | Required. EndPart's CFrame is where the next segment attaches. EndPart must be level (pitch and roll within ±2°), so the next segment doesn't tilt. |
| `Tier` | string | One of the 7 tiers. Must match the folder. |
| `Theme` | string | One of the 7 themes (§5.6). |
| `Weight` | number | Default 1. Range 0.25–3. |
| `ParTime` | number (s) | Clean run time by a designer on a 5/5/5 test ball, no tools, no falls. Must be within ±25% of the tier target. |
| `NoTools` | bool | Optional. Disables all tools in this segment. Max 1 per tier in the pool. |
| `ToolsAllowed` | string | Optional comma list of tool ids. If set, only those work here. |
| `ToolRequired` | string | Optional tool id (`grapple`, `glider` or `spring` only). Spawns a free pickup (§6.6). |

**Obstacle tags and attributes:**

| Tag | Attributes (default) | Behaviour |
|---|---|---|
| `BoostPanel` | `BoostSpeed` (1.6 = × ball's MaxForce), `Duration` (2 s) | Tween to boosted MaxForce in 0.5 s, hold, tween back in 0.5 s. FOV punch. |
| `JumpPad` | `JumpPower` (0.40) | Sets vertical velocity like the reference `ApplyJumpPad`. Ignores the Jump stat. |
| `KillBrick` | none | Touch → respawn at checkpoint (or Shield, §6). |
| `Rotating` | `Axis` ("Y"), `Period` (4 s per turn), `Direction` (1 / −1) | Client-animated. |
| `Moving` | `Offset` (Vector3, studs), `Period` (3 s), `Easing` ("Sine") | Ping-pong between the start position and start + Offset. |
| `Vanishing` | `OnTime` (2 s), `OffTime` (1.5 s), `Phase` (0 s) | Fades 0.3 s before it goes. |
| `GrappleAnchor` | `Range` (optional override, studs) | Glowing hook point for the Grapple Hook (§6). |

**Length target:** path length ≈ `ParTime × 0.7 × V5`, where V5 is the measured top speed of a Speed-5 ball in studs/s. M1 measures V5. Until then, use **V5 ≈ 40 studs/s** *(tune)*, giving Beginner ≈ 340 studs, Hell ≈ 840 studs, Finale ≈ 1,120 studs.

**Fairness rules (checked in `SegmentTest`):**
1. Every **required** jump is cleared by a **1/1/1** test ball (`SegmentTest` with forced stats) with no tools, no passes, with room to spare. Shortcuts may need Jump 7+ or a tool.
2. Every death hazard is visible for at least 1 s before you reach it at Speed 10.
3. Every segment can be finished with **zero** tools. Exception: `ToolRequired` segments, which give the tool for free.
4. No blind drops: the landing must be visible from the take-off.
5. A segment's fall volume is its bounding box +10 studs. Nothing playable may hang outside it.
6. The first two Beginner slots have no KillBrick on the main path, only on the edges (FTUE).

### 5.5 Prototype segment list (20)

| # | Name | Tier | Theme | Idea |
|---|---|---|---|---|
| 1 | Ash Ramp | Beginner | Ash Wastes | Wide downhill with two boost panels. Teaches rolling. |
| 2 | Ember Steps | Beginner | Ash Wastes | Three low wide steps. Teaches jump. |
| 3 | Gutter Run | Beginner | Ash Wastes | Curved half-pipe with lava edges. Teaches steering. |
| 4 | First Bend | Beginner | Ash Wastes | Two 90° turns and one jump pad. |
| 5 | Pad Alley | Easy | Ash Wastes | Chain of jump pads over a lava pool. |
| 6 | Brimstone Bridge | Easy | Brimstone Caves | Narrowing bridge with one slow sweeper. |
| 7 | Cave Slalom | Easy | Brimstone Caves | Weave between stalagmite posts. |
| 8 | Tilted Tiles | Easy | Brimstone Caves | Slow moving platforms in a line. |
| 9 | Lava Falls Climb | Medium | Lava Falls | Uphill switchbacks with falling-lava KillBrick columns. |
| 10 | Spin Cycle | Medium | Lava Falls | Two rotating discs to cross. |
| 11 | Magma Conveyor | Medium | Brimstone Caves | Moving floor sections and a boost into a jump. |
| 12 | Bone Yard Gaps | Hard | Bone Yard | Vanishing rib-bone platforms. |
| 13 | Chain Gap | Hard | Bone Yard | Big chasm with grapple anchors (`ToolRequired = grapple`). Optional low route without the tool is slower. |
| 14 | Pendulum Pass | Hard | Lava Falls | Swinging skull pendulums over a narrow path. |
| 15 | Forge Hammers | Insane | Inferno Forge | Timed piston hammers on a 6-stud path. |
| 16 | Updraft Chasm | Insane | Inferno Forge | Long drop with lava vents (`ToolRequired = glider`). |
| 17 | Skull Spiral | Insane | Bone Yard | Climbing spiral with vanishing tiles. |
| 18 | Soul Ladder | Hell | Soul Abyss | Tiny moving platforms in the dark, lit only by soul flames. |
| 19 | Abyss Run | Hell | Soul Abyss | Full combo: boost into vanishing tiles into a rotating gate. |
| 20 | Throne of Embers | Finale | Throne of Embers | Climb the throne steps through hammers and lava waves to the crown gate. |

### 5.6 Themes
**Ash Wastes** (grey ash, soft orange sky), **Brimstone Caves** (yellow sulphur crystals), **Lava Falls** (red-orange cascades), **Bone Yard** (giant ribs and skulls), **Inferno Forge** (iron, chains, sparks), **Soul Abyss** (black and teal soul fire), **Throne of Embers** (gold and molten red finale).

### 5.7 Checkpoints, falls, anti-cheat (numbers for `ProgressService`)

| Rule | Value |
|---|---|
| Checkpoint accept range | ball within **20 studs** of the flag |
| `MIN_PAR_FRACTION` | **0.35** × ParTime since last checkpoint. **0.25** if the player used a movement tool (Rocket, Grapple, Glider, Spring, Coil) in that segment. |
| Strike | Any rejected checkpoint or speed-audit fail. **5 strikes in one round** → player is moved back to their last valid checkpoint, logged as `AntiCheatFlag`. |
| Respawn time | ≤ 1.5 s (fade 0.3 s, place, unfreeze) |
| Global Y floor | 200 studs below the lowest built segment |

---

## 6. Gameplay Tools

*Director-approved scope addition (2026-11-07).* Tools are items you activate during a run to get out of trouble or roll faster. They support P1 (fewer frustrating falls) and P3 (style choice), and they're limited so they can't break P4 (Hell is earned).

### 6.1 How tools work (the 5-second version)
- You **own** a tool (permanent unlock) or hold **charges** of it (consumables).
- Each round, every owned tool gives you its **free charges per round**. When those run out, the tool uses your **stored charges** (`toolCharges`).
- You can equip a tool if you own it **or** have at least 1 stored charge.
- A tool button shows: icon, rarity-coloured ring, charge count, radial cooldown. Grey = can't use here (with a tiny lock icon).

### 6.2 Tool roster (`Tables/ToolTable`)

All forces are relative to the ball's resolved stats where possible, so they scale with ball choice. Absolute stud numbers are *(tune)* until V5 is measured.

| Id | Name | Rarity | Effect (exact) | Cooldown | Free charges / round (if owned) | Coin price | Robux unlock |
|---|---|---|---|---|---|---|---|
| `brake` | Brake Anchor | Common | Horizontal velocity set to 0 instantly, then `SmoothStopRate × 4` for 1.0 s. Works in the air (kills horizontal drift only). | 8 s | 3 | 300 | 49 |
| `spring` | Super Spring | Common | Grounded only. One jump at `JumpPower × 1.6` (≈2.56× normal height). | 15 s | 2 | 500 | 49 |
| `rocket` | Rocket Burst | Common | Horizontal velocity set to `top speed × 1.6` in camera-forward direction (flattened), held 0.6 s, then normal blend. FOV punch. Ground or air. | 10 s | 3 | 600 | 49 |
| `coil` | Gravity Coil | Rare | Your gravity × 0.6 for 6 s. | 25 s | 2 | 1,200 | 99 |
| `glider` | Glider | Rare | Airborne only. Fall speed capped at 18 studs/s and `AirMoveRate × 1.5`, up to 4 s or until you land. | 20 s | 2 | 1,400 | 99 |
| `shield` | Shield Bubble | Rare | Bubble for 20 s or until used. Absorbs **one** KillBrick touch (you bounce off, 0.5 s invulnerable) **or one fall** (rescued to your last safe ground point, §6.5). The fall doesn't count. | 30 s | 1 | 1,500 | 99 |
| `grapple` | Grapple Hook | Epic | Latches to the nearest `GrappleAnchor` within **60 studs** and a 30° cone of camera-forward. Pulls at **80 studs/s** for up to 1.5 s, releases at the anchor with your momentum. No anchor in range → button shows "no target" and no charge is used. | 12 s | 3 | 3,500 | 149 |
| `timeslow` | Time Slow | Epic | For 5 s, `Moving`, `Rotating` and `Vanishing` obstacles within 80 studs run at **0.5×** speed *for you only* (client-side animation). | 40 s | 1 | 4,000 | 149 |
| `pocket` | Pocket Checkpoint | Legendary | Places a personal respawn flag where you stand (grounded, not on a KillBrick/Moving/Vanishing part, inside this segment's volume). Falls in this segment respawn there. Removed at the next checkpoint. 1 per segment. **Not allowed in Hell or Finale.** | n/a (1 per segment) | 2 | 8,000 | 249 |

Tool rarity colours are the ball rarity colours (§4). "Coin Magnet" from the brief was dropped because there are no coin pickups on the course. Coins come from checkpoints.

### 6.3 Loadout
| Rule | Value |
|---|---|
| Slots | **2**. A 3rd slot with the **Tool Belt** pass. |
| Changing loadout | Free in the lobby. During a race, changes apply at your next checkpoint or respawn. |
| Keys | PC 1/2/3 · Gamepad X/Y/RB · Mobile: 3 buttons in an arc above Jump (slot 3 hidden without the pass, shown with a lock icon that opens the pass offer). |
| Global cooldown | 2 s between any two tool activations. |
| Defaults | New players get **Shield Bubble** in slot 1 with 3 stored charges (FTUE, §10.1). |

### 6.4 Server authority
1. Client presses → sends `UseTool(slot)` (rate-limited to 4/s).
2. Server checks: tool equipped in that slot; owned-with-free-charge or `toolCharges[id] > 0`; cooldown and global cooldown done; segment rules (§6.6) allow it; player is racing (not lobby/countdown/results).
3. If OK: spend charge (free first, then stored), start cooldown, record `{tool, segment, time}`, reply `true`. The server applies server-side effects (shield state, pocket position, speed-audit window, gravity attribute). The client plays the movement effect.
4. Client **predicts** the press (plays the effect at once). If the server says no within 300 ms, the client cancels and shows the reason ("On cooldown", "No tools here").

**Saved keys** (need Director OK, §15): `ownedTools = { [toolId] = true }`, `toolCharges = { [toolId] = n }` (cap 99 each), `equippedTools = { "shield", "", "" }`.
**Runtime (not saved):** free charges left this round, cooldown end times, uses this segment, active shield / pocket.

### 6.5 Shield rescue point
The client reports the last grounded position every 0.5 s. The server keeps the newest point that is inside the current segment's fall volume, is ≥ 3 studs from any KillBrick and isn't on a Moving/Vanishing part. On a shielded fall, the ball goes there with zero velocity. If no valid point exists, use the checkpoint (the fall still doesn't count). `Respawn Here` (§11) uses the same point.

### 6.6 Balance guardrails
| Guardrail | Rule |
|---|---|
| Per-segment cap | Activations per player per segment: Beginner/Easy/Medium no cap · Hard **3** · Insane **2** · Hell **1** · Finale **1**. |
| Segment flags | `NoTools` disables all tools. `ToolsAllowed` whitelists. `ToolRequired` puts a free **pickup** at the segment start: 1 temporary charge of that tool, refilled on every respawn in that segment, lost when you leave it. No segment ever needs a bought tool. |
| Pocket Checkpoint | Banned in Hell and Finale. |
| Shield in Hell/Finale | Counts toward the 1-per-segment cap like any tool. |
| Stats interaction | Rocket scales with your top speed, Spring with your JumpPower, Glider with your AirMoveRate. Grapple, Time Slow and Brake ignore stats. |
| Server modifiers | Gravity multipliers stack by multiplying (Low Gravity × Coil), floor **0.4 × 196.2**. Slow Everyone lowers top speed, so Rocket is also slower. Giant/Shrink don't change tool numbers. Double Jump modifier works with Spring. Shield does **not** block troll effects. |
| Anti-cheat | Movement tool use lowers `MIN_PAR_FRACTION` to 0.25 for that segment and opens a speed-audit window (Rocket 0.6 s + 0.5 s grace at 1.6×; Grapple 1.5 s at 80 studs/s). |
| Unlimited pass | Removes the free-charge limit only. Cooldown, global cooldown and per-segment caps still apply. |

### 6.7 Tool monetization
| Item | Type | Price (R$) | Contents |
|---|---|---|---|
| Tool unlock by rarity | Product | 49 / 99 / 149 / 249 | Unlock the tool you're viewing (Common / Rare / Epic / Legendary). |
| Tool Refill | Product | 25 | +5 stored charges of the tool you're viewing. |
| Tool Crate | Product | 99 | +3 stored charges of every tool except Pocket. |
| Survival Bundle | Product | 199 | Shield + Glider unlocks + 5 charges of each. |
| Speedrunner Bundle | Product | 199 | Rocket + Grapple unlocks + 5 charges of each. |
| Tool Belt | Game pass | 199 | 3rd tool slot. |
| Unlimited Rockets | Game pass | 399 | No free-charge limit on Rocket Burst (§6.6). |
| Coin refill | Coins | 100 coins | +3 stored charges of an **owned** tool. Max 1 per tool per round (late-game coin sink). |

If a bundle unlock is already owned at receipt time, that part converts to +10 stored charges of the same tool.

---

## 7. Trick System

*Director-approved scope addition (2026-11-07, T-025).* When your ball gets big air, your rider **does tricks automatically** and you earn bonus Coins when you land. You never press a trick button. You get more tricks by getting more air (jump pads, big drops, a high Jump stat, Super Spring) and by owning better tricks. This supports P1 (falling and flying is fun) and P3 (style choice), and caps keep it from out-earning racing.

### 7.1 How tricks work (the 5-second version)
- **Big air → your rider tricks by themselves → land → bonus Coins.**
- The more air you get, the more tricks chain together, and each trick in the chain is worth more (×1, ×1.5, ×2…).
- You choose **which** tricks can play by equipping up to **4** in the Tricks tab. Better tricks score more and look cooler.
- Falling into the void during a jump loses that jump's tricks ("Bail!"). Nothing else can go wrong: the auto-picker only starts tricks it expects to finish.

### 7.2 Trigger: airborne and airtime (`TrickTable.Config`)

| Config key | Value | Rule |
|---|---|---|
| `GROUND_RAY` | ball radius + **0.5** studs | Ray cast straight down from the ball centre, ignoring balls, characters and non-collidable parts. A hit within this length means **grounded**. |
| `AIR_CLEARANCE` | ball radius + **3** studs | No hit within this length means **airborne**. Between the two lengths the state doesn't change (hysteresis, so bumpy ground doesn't flicker). |
| `MIN_AIRTIME` | **0.6 s** *(tune)* | Continuous airborne time before the first trick may start. Rule for tuning: **a normal single jump on flat ground must never qualify.** M1 measures the single-jump airtime of a Jump-10 ball; if it is ≥ 0.6 s, set `MIN_AIRTIME` = that airtime + 0.1 s. Double jumps, jump pads, ramps and big drops should qualify. |
| `PICK_MARGIN` | **0.10 s** | Safety margin. A trick only starts if it finishes this long before the predicted landing. |
| `PREDICT_MAX_DROP` | **200 studs** | If the down ray finds no ground within 200 studs, the ball is heading for the void: **no trick starts** (checked again every 0.1 s). |
| `LAND_CONFIRM` | **0.5 s** | After touchdown, the ball must stay out of fall volumes and not respawn for 0.5 s before the tricks pay. |
| Active states | Race only | No tricks in the lobby, countdown or Results, or while frozen/respawning. |

**What doesn't count or counts less** (the "assist" rules):

| Situation | Effect on this airtime's trick points |
|---|---|
| Airtime ends in a fall volume, below the Y floor, on a KillBrick, in a Shield rescue, a respawn, a Skip, or the round ends | **Void ("Bail!")**: the whole airtime scores 0. |
| Glider active at any moment | No new trick starts while gliding (the rider holds the glider). Points ×**0.5** ("Assisted"). |
| Grapple pulling at any moment | No new trick starts while pulling. Points ×**0.5**. |
| Gravity Coil active at any moment | Tricks play normally. Points ×**0.5**. |
| Super Spring, jump pads, double jump, Rocket Burst | Full value. Super Spring is the "trick tool". |
| Low Gravity server modifier | Full value (a paid fun moment for the whole server; caps still apply). |
| Several assists in one airtime | ×0.5 once (doesn't stack). |

### 7.3 Auto-picker (client, `TrickController`)
1. When airtime reaches `MIN_AIRTIME` (and again each time a trick ends), predict the time left in the air: cast a ray down to find the ground height `h` below the ball, then `tLand = (vy + √(vy² + 2·g·h)) / g`, where `vy` is the current vertical velocity (up is positive) and `g` is the ball's current gravity. No ground within 200 studs → stop (no trick).
2. **Plan:** try every sequence of up to 5 tricks from your **equipped** tricks whose total duration ≤ `tLand − PICK_MARGIN`, with no trick twice in a row. Score each sequence with the §7.5 rules and keep the best. Ties go to the sequence with the most different tricks. With 4 equipped tricks this is ≤ 1,024 sequences: cheap enough to run every time.
3. Play the **first** trick of the best plan. When it ends, go back to step 1 (the prediction updates, so a ramp that gives more air than expected adds tricks).
4. Tricks play back to back with a **0.1 s** blend between them. If nothing fits, the rider holds the normal riding pose.

### 7.4 Trick roster (`Tables/TrickTable.Tricks`)

`Tier` drives the card colour and upgrade cost: Free = Basic grey, Coins = Rare blue, Reward = Epic purple, Premium = Legendary orange, Seasonal = card shows the season ribbon (§8.5). Points per second rise with tier, so **premium tricks score more and look better**.

| Order | Id | Name | Tier | Duration (s) | Base points | Points/s | Unlock source | Coin price | Robux | Animation (one line, for the Animator) |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `tuck` | Ember Tuck | Free | 0.4 | 50 | 125 | Starter (everyone) | n/a | n/a | Rider crouches and hugs knees on top of the ball, then pops back up. |
| 2 | `horns` | Horn Salute | Free | 0.4 | 50 | 125 | Starter (everyone) | n/a | n/a | Rider stands tall, throws both hands up in "devil horns" and leans back. |
| 3 | `spin` | Cinder Spin | Free | 0.5 | 60 | 120 | Starter (everyone) | n/a | n/a | Rider does a full 360° spin standing on the ball, arms out. |
| 4 | `hellbird` | Hellbird | Coins | 0.6 | 100 | 167 | Coins | 750 | 25 | Rider lies flat above the ball, arms forward like flying, then snaps back to standing. |
| 5 | `backflip` | Backflip Inferno | Coins | 0.7 | 125 | 179 | Coins | 1,500 | 49 | Full backflip off the top of the ball, landing back on it. |
| 6 | `handstand` | Brimstone Handstand | Coins | 0.7 | 125 | 179 | Coins | 2,500 | 49 | One-hand handstand on top of the ball, legs kicking like flames. |
| 7 | `skullsplit` | Skull Split | Reward | 0.6 | 110 | 183 | Timed 45-min gift (once ever, §10.4) | n/a | n/a | Rider jumps up off the ball into a mid-air side split, touches toes, drops back on. |
| 8 | `throne` | Throne Sit | Premium | 0.8 | 175 | 219 | Robux / Trick Pack / Season premium tier 15 | n/a | 79 | Rider floats cross-legged above the ball, arms folded, slowly turning like a king on a throne. |
| 9 | `doubleflip` | Double Damnation | Premium | 1.0 | 225 | 225 | Robux / Trick Pack | n/a | 99 | Two forward flips high above the ball, fire trail from the feet. |
| 10 | `corkscrew` | Comet Corkscrew | Premium | 1.2 | 275 | 229 | Robux / Trick Pack | n/a | 129 | Body goes horizontal and does a 720° sideways corkscrew, ends in a pointing pose. |
| 11 | `howl` | Hellhound Howl | Seasonal (S1) | 0.6 | 110 | 183 | Season 1 free tier 20 (§8.6) | n/a | n/a | Rider drops to all fours on the ball and howls at the sky, head thrown back. |
| 12 | `soulsurf` | Soul Surf | Seasonal (S1) | 1.0 | 230 | 230 | Season 1 premium tier 30 (§8.6) | n/a | n/a | Rider stands sideways on the ball like a surfer, carving with arms out, teal soul-flame trail. |

Fields: `{ Id, Name, Tier, Duration, BasePoints, Source, Price, RobuxProduct, AnimationId, Order, SeasonId? }`. Every trick also needs a 0.15 s **landing blend** back to the riding pose (one shared animation, see §7.6). Rider tricks are character animations on the rig that rides the ball (the ball keeps rolling normally under it).

**Loadout:** 4 trick slots (`equippedTricks`). New players start with Ember Tuck, Horn Salute and Cinder Spin equipped and slot 4 empty. Changing the loadout works anywhere, applies from the next airtime. Owning a trick and not equipping it means it never plays.

### 7.5 Scoring
Per airtime:

`airtime points = ( Σ BasePoints_i × Level_i × Chain_i × Fresh_i × Landing_i ) × Variety × Assist`

| Factor | Value |
|---|---|
| `Level_i` (upgrade, §7.8) | L1 ×1.00 · L2 ×1.25 · L3 ×1.50 |
| `Chain_i` (the i-th trick in this airtime) | `min(1 + 0.5 × (i − 1), 2.5)`: ×1, ×1.5, ×2, ×2.5, ×2.5 |
| `Fresh_i` (no repeat spam) | ×0.5 if the same trick already played in this airtime, else ×1 |
| `Landing_i` | ×1 clean; for the trick cut short by an early landing see §7.6 |
| `Variety` | ×**1.25** if the airtime had **3 or more different** tricks ("MIXED!"), else ×1 |
| `Assist` | ×0.5 if Glider, Grapple or Gravity Coil was active (§7.2), else ×1 |

Airtime points are rounded down to a whole number.

**Points → Coins:** **200 trick points = 1 base trick coin**. Points carry over within a round (runtime remainder), so 150 + 150 points = 1 coin + 100 left. Paid after `LAND_CONFIRM`.

**Caps (on base trick coins, before personal multipliers):**

| Cap | Value |
|---|---|
| Per segment (segment where the airtime **started**) | that tier's checkpoint coins: Beginner 2 · Easy 3 · Medium 4 · Hard 5 · Insane 7 · Hell 10 · Finale 10. Retries after falls share the same segment cap. |
| Per round | **25** base trick coins |

**Multipliers on trick coins:** `trick coins = capped base × TrickPersonalMultiplier`, where `TrickPersonalMultiplier = 1 + (2× Coins pass) + (2× Coins boost active) + (2× Trick Coins pass)`, max **×4**. The **RoundMultiplier (finish multiplier) does not apply** to trick coins: it's a racing reward, and leaving it out keeps the caps meaningful.

**Style vs speed:** tricks never slow the ball or change steering (they're automatic, so a penalty would be unfair). The trade-off is the route: chasing jump pads, high lines and Spring jumps is usually slower than the racing line. In the sim, trick-hunting players earn ~4% fewer race coins (§9.4).

**Worked examples**
1. *Average player*, tricks Ember Tuck, Horn Salute, Cinder Spin, Hellbird (all L1). A jump pad gives 1.9 s of air. Window = 1.9 − 0.6 = 1.3 s, plan must fit 1.2 s. Best plan: Cinder Spin (0.5) then Hellbird (0.6) = 1.1 s → 60 × 1 + 100 × 1.5 = **210 points**. Clean landing → 1 base coin + 10 points carried. With the 2× Coins pass: 2 coins.
2. *Trick-heavy player*, Backflip Inferno, Double Damnation, Throne Sit, Comet Corkscrew, all L2 (×1.25). A big drop gives 2.4 s. Window 1.8 s, plan must fit 1.7 s. Best plan: Backflip (0.7) then Double Damnation (1.0) = 1.7 s → 125 × 1.25 × 1 + 225 × 1.25 × 1.5 = 156.25 + 421.875 = 577.125 → **577 points** → 2 base coins + 177 carried. With 2× Coins pass + 2× Trick Coins pass (×3): 6 coins. If this was a Hard segment that already paid 4 trick coins, only 1 more base coin fits the segment cap of 5.
3. *Early landing:* same player, but the ball clips a ledge 0.3 s early, 0.7 s into Double Damnation (70% done). Backflip 156.25 + Double Damnation 421.875 × 0.5 (Sloppy) = 367.19 → **367 points**.

### 7.6 Landing: Clean, Sloppy, Bail
| Result | When | Points | What the player sees |
|---|---|---|---|
| **Clean** | Touchdown when no trick is playing (the normal case, because of the picker) | full | Gold "CLEAN! 210" |
| **Sloppy** | Touchdown while a trick is playing (hit a ledge, a moving platform, a wall) | Earlier tricks in this airtime keep full value. The cut trick: ≥ 50% done → ×0.5; < 50% done → 0. The combo is **never lost** by an early landing. | Orange "SLOPPY! 367". The animation blends to the riding pose in 0.15 s. No slow-down, no stumble. |
| **Bail** | The airtime is void (§7.2 table: fall, KillBrick, Shield rescue, skip, respawn, round end) | 0 for the whole airtime | Red "BAIL!" over the normal fall/respawn |

Landing on any collidable part counts (ground, moving or vanishing platforms, another player's ball). Landing on a KillBrick is a Bail.

### 7.7 Feedback
| Moment | Popup (centre, above the ball) | Sound | Camera |
|---|---|---|---|
| Trick starts | Trick name in white, e.g. "HELLBIRD" | Whoosh; pitch +2 semitones per chain step | none |
| 2nd+ trick in a chain | "×1.5", "×2", "×2.5" next to the name, growing | Rising chime | 3rd trick and up: FOV +5 for 0.3 s |
| 3+ different tricks | "MIXED +25%" | Sparkle | none |
| Clean | "CLEAN! 577" gold, then "+2" coin icon flies to the coin counter | Landing thud + coin chime | small 0.1 s landing bump |
| Sloppy | "SLOPPY! 367" orange | Comic "boing" | none |
| Bail | "BAIL!" red, small (the fall feedback stays the main thing) | Sad trombone, short | none |
| Segment cap reached | Small grey "MAX" tag beside the points | none | none |
| Round cap reached | Once per round: "Trick coins maxed this round!" toast | none | none |

Popups use the shared `Notifications`/`RewardFly` modules. Text ≤ 14 characters, readable at phone size (min 28 px). No camera spins or rolls ever (motion comfort).

**Settings toggle "Show tricks: On/Off"** (`settings.showTricks`, default On). Off = the rider stays in the riding pose and no trick animations or FOV punches play, but **points, popups and coins work the same** (the client still runs the picker and reports the plan). This protects motion-sensitive players and costs them nothing.

### 7.8 Player agency: air, loadout, upgrades
Players can't press a trick button, so they choose in three places:
1. **Get more air.** Jump pads, ramps and big drops (level designers: every Medium+ segment should have at least one optional "trick line" with ≥ 1.5 s of air that is a little slower than the main line). A high Jump stat, the Double Jump pass and Super Spring all add airtime at full value. Glider, Grapple and Gravity Coil add air but score ×0.5.
2. **Loadout.** 4 equipped tricks decide what the picker can use. Short tricks fill short jumps; long premium tricks pay best on big air. Only 3 free tricks means a 4th trick in the same airtime repeats at ×0.5, a soft reason to own a 4th.
3. **Upgrades** (`TrickTable.Upgrades`): each trick can go L1 → L2 → L3. L2 adds an ember trail on hands and feet, L3 adds a flame burst at the end of the trick.

| Trick tier | L2 cost (coins) | L3 cost (coins) | Points |
|---|---|---|---|
| Free | 300 | 900 | L2 ×1.25, L3 ×1.5 |
| Coins | 600 | 1,800 | same |
| Reward / Premium / Seasonal | 1,000 | 3,000 | same |

### 7.9 Server authority (`TrickService`)
The client plays animations and predicts the score. The server decides what pays.
1. **Server airtime record.** For every racing player the server samples the ball's replicated `CFrame` and `AssemblyLinearVelocity` at **10 Hz** and runs the same grounded/airborne ray test (§7.2). It keeps `{ airId, startT, endT, startSegment, minClearance, assistFlags }`. Assist flags come from `ToolService` (Glider, Grapple, Coil windows). Falls, respawns and skips come from `ProgressService`.
2. **Client report.** After touchdown the client sends `ReportTricks(airId, { {trickId, progress}, … })`, at most 1 per airtime and rate-limited to 3 per second. The client's point total is sent for logging only.
3. **Checks.**
   - Every trick id is owned (`ownedTricks`, or a free trick) and equipped (`equippedTricks`) at the time of the airtime.
   - **Fit:** sum of reported durations (the last one × its progress) ≤ server airtime − `MIN_AIRTIME` + **0.2 s** tolerance (10 Hz sampling jitter). If it doesn't fit, the server pays only the tricks that fit, in order. If it's over by more than **0.5 s**, it also adds one strike (same counter as §5.7).
   - **Ballistic sanity:** during the airtime, vertical velocity may not rise by more than **15 studs/s** between samples unless a jump pad, double jump, Spring or Grapple event explains it. Otherwise the airtime pays 0 and adds a strike.
   - Server airtime ≥ `MIN_AIRTIME`, race state active, no void event before `LAND_CONFIRM` ends.
4. **Grant.** The server recomputes points from `TrickTable` (never trusts client points), applies Level, Chain, Fresh, Landing, Variety and Assist, adds the remainder, applies the segment and round caps, multiplies, grants coins (`EconomyService`, economy event source `Gameplay`, sku `Tricks`) and replies with the granted amount. The client corrects its popup if the server number is lower.
5. Trick purchases, upgrades and loadout changes are normal server requests (`BuyTrick`, `UpgradeTrick`, `EquipTricks`) with ownership and price checks.

**Saved keys** (need Director OK, §15): `ownedTricks = { [trickId] = true }` (free tricks are implicit), `equippedTricks = { "tuck", "horns", "spin", "" }`, `trickLevels = { [trickId] = 1..3 }` (missing = 1), `settings.showTricks = true`, and `stats.tricksLanded`, `stats.bestTrickPoints`.
**Runtime (not saved):** current airtime record, trick coins this round and per segment, carried points.
**Tables:** `Tables/TrickTable` with `Tricks` (§7.4), `Config` (§7.2) and `Upgrades` (§7.8).

### 7.10 Trick monetization
| Item | Type | Price | Contents |
|---|---|---|---|
| Coin tricks | Coins | 750 / 1,500 / 2,500 | Hellbird, Backflip Inferno, Brimstone Handstand |
| Coin trick Robux unlock | Product | 25 / 49 / 49 | Unlock the coin trick you're viewing |
| Premium tricks | Product | 79 / 99 / 129 R$ | Throne Sit / Double Damnation / Comet Corkscrew |
| **Trick Pack** | Product | **249 R$** | All 3 premium tricks, already at **L2**, + 30 min 2× Coins boost. (Bought separately: 307 R$ before upgrades.) Owned parts at receipt → that trick's next level instead (L3 if already L2, else 1,000 coins). |
| Max This Trick | Product | 49 R$ | Sets the trick you're viewing to L3. |
| **2× Trick Coins** | Game pass | **149 R$** | +1 to `TrickPersonalMultiplier` (§7.5). Stacks additively with 2× Coins pass and boosts, max ×4. Caps are on base coins, so the pass really doubles trick income. |
| Seasonal tricks | Season Pass | §8 | Hellhound Howl (free tier 20), Soul Surf (premium tier 30), Throne Sit (premium tier 15) |

Upsells are in §11.4 (rows marked *Tricks*).

---

## 8. Season Pass

*Director-approved scope addition (2026-11-07, T-025).* A 30-day season with **40 tiers**. Everything you already do (checkpoints, finishes, tricks, gifts, challenges) earns **Season XP**. Every tier has a **free** reward and a **premium** reward. The premium track is a one-time purchase per season.

### 8.1 How it works (the 5-second version)
- **Play → XP bar fills → new tier → tap to claim.** Top row free, bottom row premium (gold, locked until bought).
- Daily and weekly **challenges** give big chunks of XP.
- The last free tier is a season-only ball. The last premium tier is a better season-only ball.
- Buy Premium any time in the season: every premium reward you already reached unlocks at once.

### 8.2 Season timing and config (`Tables/SeasonTable`, `FlagService`)
| Item | Rule |
|---|---|
| Length | **30 days** *(tune)*. Season 1 name: **Emberfall**. Start date: Director sets. |
| Config | `SeasonTable.Seasons[id] = { Name, StartUtc, EndUtc, Tiers = 40, XpPerTier = 900, Free = {...}, Premium = {...}, Products = {...} }`. The active season is the one whose id equals the remote-config flag **`ActiveSeasonId`** and where `StartUtc ≤ now < EndUtc` (`workspace:GetServerTimeNow()`). An optional flag `SeasonEndOverrideUtc` can extend a season without a code update. |
| Off-season | If no season is active, the Season button shows "Season 2 starts in 2d 4h" (only if the next season has a `StartUtc`). No XP is earned and challenges are hidden. Target gap: 0–2 days. |
| Season end | XP stops at `EndUtc`. Premium and tier products are hidden in the last **1 hour** (no receipt can arrive for an ended season). |
| Close-out | On the player's next join after the end (or right away if they're online), the server **auto-claims every earned, unclaimed reward** (free, plus premium if `hasPremium`), shows a "Season 1 rewards" summary, writes `seasonHistory[id] = { tier, hasPremium }`, then resets `season` for the new id (XP 0, nothing claimed, no premium). |
| Kept forever | Season balls, tricks and trails stay owned. Tool charges, spins, boosts and tokens are normal inventory. |
| New players mid-season | Start at tier 0. The Season screen and HUD XP bar unlock after their first round's Results (keeps the FTUE simple). Catch-up bonus below helps them. |

### 8.3 Tiers and XP
- **40 tiers × 900 XP = 36,000 XP** for the whole free and premium track. Tier = `min(40, floor(xp / 900))`.
- **Catch-up bonus:** while your tier is below the **days elapsed** since `StartUtc` (rounded down), all season XP × **1.5**. Shown as a "Catch-up ×1.5 XP" chip on the bar. It helps late joiners and players who missed days, and switches off as soon as you're on pace.
- **After tier 40:** every further **1,800 XP** gives a **Bonus Chest** (free: 100 coins; premium adds 1 spin), max **10** per season.

| XP source | XP | Notes |
|---|---|---|
| Checkpoint | 10 | 29 per course. Skipped segments give 0. |
| Finish | 100 | |
| Trick airtime landed (Clean or Sloppy, ≥ 1 trick) | 5 | Max 100 XP per round from tricks |
| Daily reward claim | 100 | |
| Timed gift claim | 25 each | |
| Daily challenge | 150 each | 3 per day |
| Weekly challenge | 500 each | 5 per week |

**Worked example (average player, one 30-min day at average skill):** ~1.45 rounds × 377 XP (27 checkpoints + trick XP + a rare finish) ≈ 547, + 100 daily claim + 6 timed gifts × 25 = 150, + 2.5 dailies × 150 = 375, + 4 weeklies per 7 days × 500 / 7 ≈ 286 → **≈ 1,460 XP/day → tier 40 on day ≈ 25**.

### 8.4 Challenges (`Tables/ChallengeTable`)
Objective types are data-driven. Each challenge row: `{ Id, Scope = "Daily" | "Weekly", Type, Params, Target, Xp, Weight, Text }`. Progress counts only from server events, in the Race state, for the active season.

| Type | Params | Counts when |
|---|---|---|
| `ClearSegments` | `minTier?` | `ProgressService` accepts a checkpoint (tier ≥ `minTier` if set) |
| `ReachSegment` | `slot` | furthest checkpoint this round ≥ `slot` (counts 1 per round) |
| `FinishRace` | | a hand-rolled finish |
| `PlayRounds` | | you were racing when Results started |
| `LandTricks` | `minChain?` | a Clean or Sloppy airtime with ≥ 1 trick (≥ `minChain` tricks if set) |
| `TrickPoints` | | server-granted trick points (sum) |
| `UseTool` | `toolId?` | `ToolService` accepts an activation |
| `SpinWheel` | | a server wheel roll (free or paid) |
| `EarnCoins` | `source = "Race"` | race coins granted (checkpoint, finish, tricks) |
| `ClaimGifts` | | timed gift claims |

**Daily pool (3 picked per UTC day):**

| Id | Text | Type | Target | XP |
|---|---|---|---|---|
| `d_clear15` | Clear 15 segments | `ClearSegments` | 15 | 150 |
| `d_clear5med` | Clear 5 Medium-or-harder segments | `ClearSegments {minTier="Medium"}` | 5 | 150 |
| `d_reach20` | Reach segment 20 | `ReachSegment {slot=20}` | 1 | 150 |
| `d_tricks10` | Land 10 trick jumps | `LandTricks` | 10 | 150 |
| `d_combo3` | Land 2 jumps with 3+ tricks | `LandTricks {minChain=3}` | 2 | 150 |
| `d_tools3` | Use tools 3 times | `UseTool` | 3 | 150 |
| `d_spin1` | Spin the wheel | `SpinWheel` | 1 | 150 |
| `d_play2` | Race 2 rounds | `PlayRounds` | 2 | 150 |
| `d_gifts3` | Claim 3 timed gifts | `ClaimGifts` | 3 | 150 |

**Weekly pool (5 picked per UTC week, Monday 00:00):**

| Id | Text | Type | Target | XP |
|---|---|---|---|---|
| `w_clear150` | Clear 150 segments | `ClearSegments` | 150 | 500 |
| `w_clear30hard` | Clear 30 Hard-or-harder segments | `ClearSegments {minTier="Hard"}` | 30 | 500 |
| `w_finish1` | Finish a race | `FinishRace` | 1 | 500 |
| `w_play10` | Race 10 rounds | `PlayRounds` | 10 | 500 |
| `w_tricks75` | Land 75 trick jumps | `LandTricks` | 75 | 500 |
| `w_trickpts` | Score 15,000 trick points | `TrickPoints` | 15000 | 500 |
| `w_tools20` | Use tools 20 times | `UseTool` | 20 | 500 |
| `w_coins1500` | Earn 1,500 race coins | `EarnCoins` | 1500 | 500 |

Rules: the server picks with a `Random` seeded by `(UserId, dayNumber)` / `(UserId, weekNumber)` and weights, no duplicates, so rejoining doesn't reroll. **1 free reroll per day** for one daily challenge (Premium: 2). `w_finish1` is only offered to players who have finished at least once (`wins ≥ 1`), otherwise it's replaced by `w_play10`. Completed challenges grant XP at once with a toast "Challenge done! +150 XP" (no claim tap).

### 8.5 Rewards and premium rules
- Rewards must be **tapped to claim** (a "Claim all" button claims everything reached). The HUD badge shows how many are waiting.
- **Premium is retroactive:** buying it unlocks every premium reward for tiers already reached, ready to claim.
- **Seasonal ball rule** (`BallTable`): new `Source = "Seasonal"` and field `SeasonId`. A seasonal ball uses a normal rarity's stat budget and colour, shows a "SEASON 1" ribbon, can't be bought (coins, by rarity), gifted or obtained twice, and is **not counted** in the 21-ball collection. If granted while owned (shouldn't happen), it converts to its rarity's duplicate coins.
- If a tool unlock in the track is already owned, it converts to +10 stored charges of that tool. If a trick is already owned, it becomes that trick's next upgrade level (or 1,000 coins at L3).

**Season balls (Season 1)**

| Id | Name | Rarity budget | Spd | Acc | Jmp | Track | Identity |
|---|---|---|---|---|---|---|---|
| `cinderhound` | Cinderhound | Epic (15) | 6 | 5 | 4 | Free tier 40 | A smouldering hound-skull ball that runs hot. |
| `moltenmonarch` | Molten Monarch | Mythic (19) | 7 | 5 | 7 | Premium tier 40 (chase reward) | A crowned orb of molten gold, Season 1 only. |

### 8.6 Reward table (Season 1 "Emberfall", `SeasonTable.Seasons.S1`)
Coins in the free track are **not** doubled by the 2× Coins pass (they're track rewards, not "reward coins" from §9.1).

| Tier | Free | Premium |
|---|---|---|
| 1 | 100 coins | **Hellfire Wake** trail + 30 min 2× Coins boost |
| 2 | 1 spin | 250 coins |
| 3 | 3 Shield charges | 2 spins |
| 4 | 100 coins | 5 Shield charges |
| 5 | 15 min 2× Coins boost | 250 coins |
| 6 | 150 coins | 1 Skip token |
| 7 | 3 Rocket charges | 30 min 2× Coins boost |
| 8 | 1 spin | 300 coins |
| 9 | 150 coins | 2 spins |
| 10 | **Cinder Wake** trail | **Soul Wake** trail |
| 11 | 150 coins | 300 coins |
| 12 | 3 Spring charges | 5 Rocket charges |
| 13 | 1 spin | 2 spins |
| 14 | 200 coins | 350 coins |
| 15 | 15 min 2× Coins boost | **Throne Sit** trick |
| 16 | 200 coins | 5 Spring charges |
| 17 | 3 Shield charges | 350 coins |
| 18 | 1 spin | 30 min 2× Coins boost |
| 19 | 200 coins | 3 spins |
| 20 | **Hellhound Howl** trick | **Gold Ember** trail + "Emberlord" title |
| 21 | 200 coins | 400 coins |
| 22 | 3 Glider charges | 2 Pocket Checkpoint charges |
| 23 | 2 spins | 3 spins |
| 24 | 250 coins | 400 coins |
| 25 | 15 min 2× Coins boost | 2 Skip tokens |
| 26 | 250 coins | 5 Grapple charges |
| 27 | 3 Grapple charges | 450 coins |
| 28 | 2 spins | 30 min 2× Coins boost |
| 29 | 250 coins | 3 spins |
| 30 | 1 Skip token | **Soul Surf** trick |
| 31 | 300 coins | 500 coins |
| 32 | 3 Shield charges | 5 Glider charges |
| 33 | 2 spins | 3 spins |
| 34 | 300 coins | 500 coins |
| 35 | 30 min 2× Coins boost | **Glider** unlock |
| 36 | 300 coins | 550 coins |
| 37 | 3 Gravity Coil charges | 5 Shield charges |
| 38 | 3 spins | 5 spins |
| 39 | 400 coins | 1,000 coins |
| 40 | **Cinderhound** ball (Epic, season-exclusive) | **Molten Monarch** ball (Mythic, season-exclusive) + Monarch crown trail |
| **Totals** | **3,500 coins, 13 spins, 75 min boost, 1 trick, 1 trail, 1 ball, 1 skip, 24 tool charges** | **5,600 coins, 23 spins, 120 min boost, 2 tricks, 4 trails + title, 1 ball, 1 tool unlock, 3 skips, 32 tool charges** |

Skip tokens follow the Skip Segment rules (§11.2). Pocket Checkpoint charges follow §6.6 (not in Hell or Finale).

### 8.7 Season monetization
| Product | Type | Price (R$) | Rule |
|---|---|---|---|
| **Premium Pass** | Developer product (one per season, not a game pass, because it resets) | **399** *(Director sets)* | Sets `season.hasPremium = true` for the season active at receipt. Already premium at receipt → grants 10 tiers instead. No season active at receipt → stored as `seasonPremiumCredit` and applied to the next season. |
| **Premium+** | Product | **699** | Premium + **10 tiers** (Premium 399 + 10 tiers 399 = 798 separately). |
| Buy a Tier | Product | 49 | +900 XP. Hidden at tier 40. |
| Buy 10 Tiers | Product | 399 | +9,000 XP, capped at tier 40. Hidden above tier 30. |
| Season Ending: 10 Tiers | Product | 299 | Replaces Buy 10 Tiers in the **last 7 days**. A real price for that window, not a fake discount; copy: "Season ends in 5d: 10 tiers for 299". |

**Upsells** (added to §11.4): reaching a tier with a premium reward you can't claim → inline glow on the locked card, and a popup at the **1st, 10th, 20th and 30th** such tier: "You'd have earned **{reward}**. Unlock Premium to claim {N} rewards now!" (cap 2 per session). Season end in **3 days** and **24 h** → Season button pulses with countdown; one popup at 24 h if not premium and tier ≥ 10. A non-premium player who reaches tier 40 → popup showing Molten Monarch + every premium reward they'd unlock.

### 8.8 Season UI
- **`SeasonPassUI` (full screen):** header "SEASON 1: EMBERFALL · 12d 4h left". Progress bar "Tier 14 · 430 / 900 XP" with catch-up chip if active. Two horizontally scrolling rows of 96 × 96 reward cards: **FREE** (top) and **PREMIUM** (bottom, gold frame, padlock overlay until bought). The current tier is centred on open. Reached-and-unclaimed cards glow with a "CLAIM" button. Buttons: "Claim all", "Unlock Premium 399", "Buy tiers". A **Challenges** tab: 3 daily bars with "resets in 6h", 5 weekly bars, reroll button. Seasonal items show a "SEASON 1" ribbon.
- **HUD:** a thin (6 px) XP bar under the goal line with the tier number in a round badge on its left. "+10 XP" floaters on checkpoints (small, under the coin floater). The Season menu button has a red badge with the number of claimable rewards.
- The **goal line** (§10.1) gets one new entry after (5): "Claim season reward!" when ≥ 1 is waiting.

### 8.9 Server authority (`SeasonService`, `ChallengeService`)
1. XP is granted **only by server code** through `SeasonService:AddXp(player, source, amount)`, called by `ProgressService` (checkpoints, finish), `TrickService` (landed airtimes, after its own validation), `DailyRewardService`, `TimedRewardService` and `ChallengeService`. No remote grants XP. The catch-up multiplier is applied inside `AddXp`.
2. Claims: `ClaimSeasonReward(tier, track)` / `ClaimAllSeasonRewards()`. The server checks the season is active (or it's the close-out), `tier ≤ current tier`, not already claimed, and `hasPremium` for the premium track, then grants through the normal services (coins via `EconomyService`, balls via `InventoryService`, tool charges via `ToolService`).
3. Premium and tier products are granted in `ProcessReceipt` only, idempotent by `PurchaseId`.
4. Challenge progress is updated from the same server events and saved with the profile. Day and week numbers come from `workspace:GetServerTimeNow()`.

**Saved keys** (need Director OK, §15): `season = { id = "", xp = 0, claimedFree = {}, claimedPremium = {}, hasPremium = false, bonusChests = 0 }`, `seasonHistory = { [seasonId] = { tier, hasPremium } }`, `seasonPremiumCredit = false`, `challenges = { day = -1, daily = { {id, progress, done} ×3 }, week = -1, weekly = { … ×5 }, rerollsUsed = 0 }`.
**Tables:** `Tables/SeasonTable` (§8.2, §8.6), `Tables/ChallengeTable` (§8.4).

---

## 9. Economy

**One currency: Coins** (UI label "Coins", gold coin icon; players may call it Cash). No premium currency.

### 9.1 Multipliers
- `RoundMultiplier` ×1.0 to ×3.0 (§2). Applies to checkpoint and finish coins.
- **Personal multiplier** = 1 + (2× Coins pass ? 1 : 0) + (2× Coins boost active ? 1 : 0). Max **×3**. Applies to checkpoint and finish coins.
- **2× Coins pass** also doubles **reward coins** (daily, timed, wheel, first-fall present). It does not double coin packs, Starter Pack coins, duplicate refunds or refunds from purchases.
- **2× Coins boost** (timed, `boosts.coins2x = expiresAt`) only affects race coins. More boost time adds to the end; bank cap **120 min**. Boost time runs on real server time while in-game only (paused while offline: store remaining seconds, not an end time). *(§15: the architecture stores `expiresAt`, this needs a decision.)*
- **VIP**: +50% coins from daily rewards (adds: pass + VIP = ×2.5 on daily coins).
- **Trick coins** (§7.5): `capped base × TrickPersonalMultiplier`, where `TrickPersonalMultiplier` = Personal multiplier + (2× Trick Coins pass ? 1 : 0), max **×4**. RoundMultiplier does **not** apply. Caps (per segment = tier checkpoint coins, per round 25) are on base coins.
- **Season track coins** (§8.6) are not multiplied by anything.

Formula: `race coins = base × RoundMultiplier × PersonalMultiplier`, rounded down, minimum 1.

### 9.2 Sources

| Source | Amount (base) | Notes |
|---|---|---|
| Checkpoint | 2 / 3 / 4 / 5 / 7 / 10 by tier | 29 per course. Not paid for skipped segments. |
| Finish | 100 + 50 / 30 / 20 for 1st / 2nd / 3rd | Must be rolled by hand. +1 Win. |
| Daily reward | 50–500 (§10.3) | |
| Timed gifts | 25–300 (§10.4) | |
| Wheel | 50 / 150 / 400 per slice (§10.5) | EV ≈ 78 coins per spin |
| First-fall present | 150 | Once ever |
| Duplicates | by rarity (§4) | Wheel ball duplicate = 2,500 |
| Coin packs (Robux) | 1,000–50,000 (§11) | |
| Starter Pack | 2,500 | |
| Tricks (§7.5) | 200 points = 1 base coin | Cap 2–10 per segment (tier checkpoint coins), 25 per round. Sim: ≈ 18–25 base coins per round. |
| Season Pass free track (§8.6) | 3,500 coins + 13 spins per season | Premium track: 5,600 coins + 23 spins |
| Season Bonus Chests (§8.3) | 100 coins each | After tier 40, max 10 per season |

### 9.3 Sinks
| Sink | Total |
|---|---|
| 2 un-picked starters | 300 |
| 13 coin-shop balls | 66,900 |
| 9 tools | 21,000 |
| 3 coin tricks (§7.4) | 4,750 |
| Trick upgrades for the 6 free/coin tricks (§7.8) | 10,800 (another 4,000 per owned reward/premium/seasonal trick) |
| Coin refills (optional, ongoing) | 100 per 3 charges |
| **Total to own everything buyable** | **92,950** (103,750 with free/coin trick upgrades) |

### 9.4 Simulation results

Script: Python Monte Carlo in the designer's scratch area (not in the repo). 3,000 simulated rounds in 12-player servers (40% novice, 45% average, 15% skilled), with clock speed-up and multipliers. Per segment: success chance per try by tier and skill, try time = ParTime × skill pace, a fall costs 0.6 × ParTime + 2 s.

| Archetype | Coins per round (mean / median) | Avg furthest segment | Finish rate |
|---|---|---|---|
| Novice | 103 / 102 | 23.3 | 0% |
| Average | 148 / 139 | 27.4 | 5% |
| Skilled | 317 / 289 | 30.0 | 96% |

Mean real race length: 18.8 min.

**Time to milestone** (cumulative purchases in the order below, skill grows: novice for the first 2 h, average until 15 h, then skilled). Includes daily rewards (1 session/day), timed gifts, 1 free spin/day, the first-fall present, and a modelled +8% race earnings once the player owns starter tools. Format: play hours / day number.

| # | Item | Cost | Free, 30 min/day | 2× pass, 30 min/day | Free, 60 min/day | 2× pass, 60 min/day |
|---|---|---|---|---|---|---|
| 1 | Cinder (ball) | 400 | 0.1 h / d1 | 0.1 h / d1 | 0.1 h / d1 | 0.1 h / d1 |
| 2 | Brake Anchor (tool) | 300 | 0.2 h / d1 | 0.1 h / d1 | 0.2 h / d1 | 0.1 h / d1 |
| 3 | Super Spring (tool) | 500 | 0.5 h / d2 | 0.2 h / d1 | 0.8 h / d1 | 0.2 h / d1 |
| 4 | Ash Rock (ball) | 450 | 0.8 h / d2 | 0.3 h / d1 | 1.0 h / d1 | 0.3 h / d1 |
| 5 | Rocket Burst (tool) | 600 | 1.2 h / d3 | 0.5 h / d2 | 1.3 h / d2 | 0.7 h / d1 |
| 6 | Bone Roller (ball) | 500 | 1.5 h / d4 | 0.7 h / d2 | 1.8 h / d2 | 0.8 h / d1 |
| 7 | 2 un-picked starters | 300 | 1.7 h / d4 | 0.8 h / d2 | 2.0 h / d2 | 1.0 h / d1 |
| 8 | Gravity Coil (tool) | 1,200 | 2.3 h / d5 | 1.1 h / d3 | 2.7 h / d3 | 1.3 h / d2 |
| 9 | Jack-o'-Blaze (ball) | 1,200 | 3.0 h / d6 | 1.5 h / d4 | 3.3 h / d4 | 1.8 h / d2 |
| 10 | Glider (tool) | 1,400 | 3.4 h / d7 | 2.0 h / d5 | 4.0 h / d5 | 2.1 h / d3 |
| 11 | Shield Bubble (tool) | 1,500 | 4.2 h / d9 | 2.5 h / d5 | 5.0 h / d6 | 2.8 h / d3 |
| 12 | Hex Code (ball) | 1,250 | 5.0 h / d10 | 2.7 h / d6 | 5.8 h / d6 | 3.0 h / d4 |
| 13 | Storm Cell (ball) | 1,300 | 5.5 h / d12 | 3.0 h / d7 | 6.1 h / d7 | 3.5 h / d4 |
| 14 | Brimstar (ball) | 3,000 | 6.8 h / d14 | 3.5 h / d8 | 8.0 h / d9 | 4.3 h / d5 |
| 15 | Grapple Hook (tool) | 3,500 | 8.8 h / d18 | 4.5 h / d10 | 10.1 h / d11 | 5.3 h / d6 |
| 16 | Cursed Glyph (ball) | 3,100 | 10.0 h / d21 | 5.5 h / d12 | 12.0 h / d12 | 6.0 h / d7 |
| 17 | Doom Knight (ball) | 3,250 | 11.8 h / d24 | 6.3 h / d13 | 13.5 h / d14 | 7.0 h / d7 |
| 18 | Time Slow (tool) | 4,000 | 13.5 h / d28 | 7.1 h / d15 | 15.8 h / d16 | 8.2 h / d9 |
| 19 | Ring of Fire (ball) | 7,500 | 16.8 h / d34 | 9.3 h / d19 | 19.0 h / d19 | 10.6 h / d11 |
| 20 | Pocket Checkpoint (tool) | 8,000 | 19.6 h / d40 | 11.1 h / d23 | 22.1 h / d23 | 13.0 h / d13 |
| 21 | Hell Comet (ball) | 8,000 | 22.5 h / d46 | 13.4 h / d27 | 25.5 h / d26 | 15.0 h / d16 |
| 22 | Void Maw (ball) | 17,500 | 28.7 h / d58 | 17.0 h / d35 | 33.0 h / d33 | 19.0 h / d20 |
| 23 | Soul Shard (ball) | 19,000 | 35.5 h / d71 | 20.5 h / d42 | 40.9 h / d41 | 23.0 h / d24 |

**Reading the results**
- **First purchase in the first session** (≈5 min, helped by the first-fall present). Strong early hook.
- **First Rare ≈ 3 h, first Epic ≈ 7 h, first Legendary ≈ 17 h, everything ≈ 36–41 h** for a free player. The 2× pass gets there **≈1.75× faster** (≈20–23 h). It's not a full 2× because the pass and 2× boosts add rather than multiply (×3, not ×4), and the first purchases are paced by gifts, not coins.
- 60-min-a-day players take *more play hours* than 30-min players because daily rewards make up a bigger share for short daily sessions. That's intended: it rewards coming back.
- Assumptions to check with real data: skill-curve timing, the fall model, 1 free spin per day, and no coin refills or Robux coins. A ±20% change in race coins moves late milestones by about ±15%.

#### 9.4.1 Tricks and Season Pass impact (T-025, `sim4.py`)

`sim4.py` (scratch area) is `sim3` plus the auto-trick model and the free season track. Per clean attempt a segment gives Beginner 0.8 → Finale 2.0 qualifying-ish airtimes (half on a failed attempt; 30% of fails void the last one). Airtime ~ triangular(0.3, 2.8, mode 0.9 s × style). The picker is the greedy version of §7.3 (slightly conservative), with 10% of airtimes landing up to 0.4 s early (Sloppy). Trick styles: **casual** = 3 free tricks, no air-hunting; **average** = free tricks + Hellbird, +20% airtimes; **heavy** = 4 premium/coin tricks at L2, +60% airtimes and longer air, but 3% slower segments. Season: casual plays 15 min 4 days a week, average 30 min daily, heavy 60 min daily. Purchases are checked once per session in sim4, so its baseline is a little coarser than the table above but matches it at the end (35.5 h).

**Tuning done:** points-per-coin was tuned from 50 to **200** and the round cap from 40 to **25**, because at the first values tricks added +27–40% to an average player's coins (more than the per-round cap target). Season XP per tier was tuned 800 → **900** to hit the day-25 target.

**Coins per hour (race + tricks, free player, no boosts)**

| Skill \ trick style | Before (no tricks) | Casual | Average | Heavy |
|---|---|---|---|---|
| Novice | 301 | 348 (+16%) | 363 (+21%) | 367 (+22%) |
| Average | 429 | 484 (+13%) | 494 (+15%) | 484 (+13%) |
| Skilled | 922 | 981 (+6%) | 990 (+7%) | 994 (+8%) |

Trick coins per round: casual ≈ 16–19, average ≈ 22–24, heavy = 25 (the cap). The cap binds for heavy players, and their slower air-hunting route costs ~4% race coins, so **heavy trick players don't out-earn average ones** (style vs speed). Tricks matter most for novices, which helps the early game and never beats racing.

**Time to milestone, free player (play hours / day)**

| Item | Avg 30 min/day: before | + tricks | + tricks + season | Casual 15 min ×4/wk: before → after | Heavy 60 min/day: before → after | 2× pass avg 30 min: before → after |
|---|---|---|---|---|---|---|
| Cinder (first ball) | 0.5 h / d1 | 0.5 h / d1 | 0.5 h / d1 | 0.2 h / d1 → 0.2 h / d1 | 1.0 h / d1 → 1.0 h / d1 | 0.5 h / d1 → 0.5 h / d1 |
| Jack-o'-Blaze (first Rare) | 3.0 h / d6 | 3.5 h / d7 | 3.0 h / d6 | 3.0 h / d18 → 2.8 h / d17 | 4.0 h / d4 → 4.0 h / d4 | 2.0 h / d4 → 2.0 h / d4 |
| Brimstar (first Epic) | 7.0 h / d14 | 8.0 h / d16 | 7.0 h / d14 | 7.0 h / d46 → 6.5 h / d44 | 9.0 h / d9 → 8.0 h / d8 | 4.0 h / d8 → 4.0 h / d8 |
| Brimstone Handstand (last coin trick) | n/a | 9.0 h / d18 | 8.0 h / d16 | n/a → 7.8 h / d52 | n/a → 10.0 h / d10 | n/a → 4.5 h / d9 |
| Ring of Fire (first Legendary) | 17.0 h / d34 | 18.0 h / d36 | 16.5 h / d33 | 16.8 h / d115 → 16.8 h / d115 | 19.0 h / d19 → 19.0 h / d19 | 9.5 h / d19 → 9.5 h / d19 |
| Void Maw | 29.0 h / d58 | 29.5 h / d59 | 28.0 h / d56 | 27.5 h / d191 → 27.2 h / d190 | 33.0 h / d33 → 32.0 h / d32 | 17.5 h / d35 → 16.5 h / d33 |
| Soul Shard (last item: everything bought) | 35.5 h / d71 | 36.0 h / d72 | **34.5 h / d69** | 33.8 h / d234 → 33.2 h / d232 | 41.0 h / d41 → 40.0 h / d40 | 21.0 h / d42 → 20.0 h / d40 |

"Before" buys the 23 old items; "after" also buys the 3 coin tricks (4,750 coins) along the way. Trick upgrades and premium-track coins aren't in the milestone runs.

**Reading it:** tricks alone are almost pacing-neutral (+13–15% income, paid back into the new trick sink). Adding the free season track makes everything ≈ **3% faster** for an average player (35.5 h → 34.5 h), within the pacing target. Premium-track owners get ≈ 5,600 coins + 23 spins (≈ 7,400 coin value) more per season, about the price of Ring of Fire: a clear but not game-breaking paid lead.

**Season tier pace (day each tier is reached)**

| Player | Tier 10 | Tier 20 | Tier 30 | Tier 40 | Final tier at day 30 |
|---|---|---|---|---|---|
| Casual (15 min, 4 days/week) | d11 | d24 | n/a | n/a | **26** |
| Average (30 min daily) | d7 | d13 | d19 | **d25** (target ≈ 25) | 40 |
| Heavy (60 min daily) | d5 | d9 | d13 | d17 | 40 + Bonus Chests |

Casual players reach tier 26 (they get the Hellhound Howl trick at 20 but not the ball); that's the main audience for Buy 10 Tiers and the season-end offer.

---

## 10. Reward systems

### 10.1 FTUE and starter pick (`OnboardingService`)

| Step | Trigger | What the player sees | Tip text (≤ 8 words) |
|---|---|---|---|
| 1 | First join, `hasPickedStarter = false` | `StarterPickUI`: 3 cards (Sprinter, Grip, Bouncer) with 10-pip stat bars and a one-line identity. Grip is pre-highlighted as "Easiest". No close button. | "Pick your first ball!" |
| 2 | Pick | Ball granted + equipped. **3 Shield Bubble charges** granted, equipped in slot 1. Spawn at start of the current course (or the start pen next round). | |
| 3 | Segment 1 | Floor arrows along the path, thumbstick ghost hand on mobile for 3 s. | "Drag to roll" / "WASD to roll" |
| 4 | First jump gap | Jump button pulses. | "Tap JUMP!" |
| 5 | Within 30 studs of the first KillBrick | Shield button pulses once. | "Shield saves you from one hit" |
| 6 | Checkpoint 1 | Coins fly to HUD. Starter Pack popup (§10.6). | "+2 Coins! Checkpoints pay." |
| 7 | First fall | First-fall present (§10.2). | "A gift! Tap it!" |
| 8 | First airtime that plays a trick (§7.2), once ever (`stats.tricksLanded == 0`) | After the landing popup, a 3 s banner with a rider-flip icon. No pause, no button. | "Big air = auto tricks = bonus coins!" |
| 9 | After the first round's Results | Shop button pulses with goal line "Buy Cinder: x/400". The Season Pass button and HUD XP bar appear (§8.2) with a one-time pulse. | "Spend Coins on new balls" / "Season Pass: free rewards!" |

**Goal line (always visible under the timer),** first match wins: (1) pick a ball, (2) reach checkpoint 1, (3) tap your present, (4) reach segment 5, (5) a claimable gift/daily/free spin → "Claim your gift!", (5b) a claimable season reward → "Claim season reward!", (6) the cheapest unowned ball or tool you can almost afford → "Buy X: have/price", (7) "Reach segment N" where N = your best + 1.

The pick is idempotent and only accepts `sprinter`, `grip`, `bouncer`. A second pick request is ignored.

### 10.2 First-fall present
| Rule | Value |
|---|---|
| Eligible | `firstFallGiftClaimed == false` and `sessionCount == 1` |
| Trigger | The first fall (KillBrick or fall volume) |
| Visual | Glowing present at the respawn point, 3 studs in front of the ball. Also a HUD present button until claimed. |
| Contents | **150 coins + 2 wheel spins + 10 min 2× Coins boost + 2 Shield charges** |
| Expiry | Stays pending for the whole first session. If they leave without tapping, it's gone (session 2 isn't eligible). |
| After claim | Reward flies into the HUD, then soft upsell toast: "Want more? Starter Pack ends in mm:ss" (only if live). |

*Proposed extension (needs approval, §14):* "comeback present" after 5 falls on one segment in sessions 1–3: 50 coins + 1 Shield charge, max 1 per session.

### 10.3 Daily rewards (`Tables/DailyRewardTable`)
UTC days from `workspace:GetServerTimeNow()`. Day number = `floor(t / 86400)`.

| Day | Reward | VIP |
|---|---|---|
| 1 | 50 coins | 75 |
| 2 | 1 spin | |
| 3 | 100 coins + 3 Rocket charges | 150 |
| 4 | 15 min 2× Coins boost | |
| 5 | 200 coins | 300 |
| 6 | 2 spins + 3 Shield charges | |
| 7 | 500 coins + 3 spins. **First time only:** + Ember Glow ball | 750 |

Rules: claim once per UTC day. If `today == lastDailyClaimDay + 1` the streak continues. If `today - lastDailyClaimDay` is 2 or 3 (missed one or two days, i.e. within 48 h), the daily screen first shows **Restore Streak** (39 R$), which continues the streak as if no day was missed. If they claim without restoring, or the gap is 4+, the streak resets to day 1. `dailyStreak` isn't reset until that claim, so no new saved key is needed. After day 7, the cycle restarts at day 1. If Ember Glow is already owned on a later day 7, there's no ball. UI: 7 boxes with a glowing "Claim" on today, a red dot badge on the HUD button.

### 10.4 Timed (playtime) gifts (`Tables/TimedRewardTable`)
Session playtime counted on the server (resets each session; AFK over 10 min stops the count).

| Minute | Reward |
|---|---|
| 2 | 25 coins |
| 5 | 1 spin |
| 10 | 50 coins |
| 15 | 10 min 2× Coins boost |
| 20 | 100 coins |
| 30 | 100 coins + 1 spin + 2 Shield charges |
| 45 | 200 coins + **Skull Split** trick (first time only, saved in `timedRewardsEverClaimed`) |
| 60 | **Hellfire Kick** ball (once ever, saved in `timedRewardsEverClaimed`). If already owned: 300 coins + 2 spins. |

Gifts must be tapped to claim (badge shows how many are waiting). **Unlock All** (99 R$) claims all remaining gifts this session at once, including the 60-min ball.

### 10.5 Spin the wheel (`Tables/WheelTable`)

| Slice | Reward | Weight | Odds |
|---|---|---|---|
| 1 | 50 coins | 30 | 30% |
| 2 | 150 coins | 20 | 20% |
| 3 | 400 coins | 6 | 6% |
| 4 | +1 spin | 12 | 12% |
| 5 | 15 min 2× Coins boost | 10 | 10% |
| 6 | Skip token (one Skip Segment) | 8 | 8% |
| 7 | 3 Shield charges | 12 | 12% |
| 8 | **Smoke Wraith** (wheel-exclusive ball). Duplicate → 2,500 coins | 2 | 2% |
| | **Total** | **100** | **100%** |

Expected value ≈ 78 coins per spin from coin slices (including re-spins), plus boosts, tokens and charges.

Spin sources: free spin every **8 h** (**4 h** with Lucky), VIP +1 free spin per day, daily, timed, first-fall present, Starter Pack, paid packs. Free spins don't bank: at most 1 free spin waiting (the timer pauses while one is unclaimed).
Rules: the server rolls with one `Random`, saves the result, then replies. The client spins for 4 s and lands on the server's slice. The odds table is always visible on the wheel screen ("Odds" button) **before** any paid spin is offered. If `PolicyService` says `ArePaidRandomItemsRestricted`, paid spin products are hidden (free spins still work).

### 10.6 Starter Pack (`Tables/StarterPackTable`)
| Item | Value |
|---|---|
| Window | 15:00 real wall-clock from `firstJoinAt`, while not bought. Never comes back. |
| Price | **Director sets: suggested 99 R$** |
| Contents | **Imp** (Legendary exclusive ball) + **Grapple Hook** unlock + **2,500 coins** + **5 spins** + **30 min 2× Coins boost** |
| Shows | HUD button with countdown (always), popup after checkpoint 1 (once), reminder popup at 2:00 left (once, only if in-game) |
| Upsell copy | "Starter Pack: 87% OFF!" is **not** allowed (no fake discounts). Copy: "New player pack, ends in 12:41". |

### 10.7 Limited ball: Crown of Hell
| Item | Value |
|---|---|
| Stock | 1,000 ever. Serial = sale order (#1–#1000). One per player. |
| Price | **Director sets: suggested 1,499 R$** |
| Stats | S8 A7 J6 (Limited budget 21) |
| UI | Shop card with "**37 / 1000 left**" from `LimitedRemaining`. Owners see their "#137" on the ball card and above their head in the lobby. |
| Toast | When stock < 100: server-wide toast "Only N Crowns of Hell left!" at most once per 10 min per server. |
| Sold out | Card stays as "SOLD OUT", showing owners count. |
| Consolation (outage case) | 25,000 coins + "Ashen Crown" exclusive trail, logged. |
| Reservation | 5-min hold (MemoryStore TTL) per architecture §6.7. |

---

## 11. Monetization

### 11.1 Game passes (`Tables/PassTable`)
| Pass | Price (R$) | Perk |
|---|---|---|
| VIP | 349 | +50% daily coins, +1 free spin per day, gold chat tag, VIP lobby spot |
| 2× Coins | 299 | Personal ×2 on race coins, trick coins and reward coins (§9.1) |
| Double Jump | 149 | Double jump (toggle in settings) |
| Turbo | 249 | MaxForce × 1.10 |
| Lucky | 199 | Free spin every 4 h instead of 8 h |
| Trails Pack | 99 | 6 cosmetic trails (Ember, Smoke, Soul, Bone Dust, Gold, Lava Drip) |
| Tool Belt | 199 | 3rd tool slot |
| Unlimited Rockets | 399 | No free-charge limit on Rocket Burst |
| 2× Trick Coins | 149 | +1 trick coin multiplier, max ×4 total (§7.5, §7.10) |

### 11.2 Developer products (`Tables/ProductTable`)
| Family | Product | Price (R$) | Effect / rules |
|---|---|---|---|
| Progress | Skip Segment | 19 | Move to the next checkpoint. No coins for it. Not usable on slot 30 or during countdown. |
| Progress | Skip 5 Segments | 59 | As above, up to 5, stops at slot 29. |
| Progress | Respawn Here | 15 | Next fall respawns at your last safe ground point (§6.5), once. |
| Currency | 1,000 coins | 49 | |
| Currency | 3,000 coins | 129 | |
| Currency | 7,500 coins | 279 | |
| Currency | 20,000 coins | 649 | |
| Currency | 50,000 coins | 1,399 | "Best value" badge |
| Wheel | 1 spin | 39 | Hidden if paid random items restricted |
| Wheel | 5 spins | 169 | Hidden if restricted |
| Wheel | 15 spins | 449 | Hidden if restricted |
| Offers | Starter Pack | Director sets: suggested 99 | §10.6 |
| Offers | Crown of Hell (limited) | Director sets: suggested 1,499 | §10.7 |
| Offers | Restore Daily Streak | 39 | Only offered within 48 h of a break |
| Offers | Unlock All Timed Gifts | 99 | Only when ≥ 1 gift remains this session |
| Offers | 2× Coins 30 min | 49 | Adds 30 min to boost bank (cap 120) |
| Balls | Buy-by-rarity | 25 / 49 / 99 / 199 / 399 / 799 | Unlocks the coin-shop ball you're viewing (Basic → Mythic). Already owned at receipt → coins equal to its coin price. |
| Tools | §6.7 | 25–249 | |
| Tricks | Coin trick unlock (Hellbird / Backflip Inferno / Brimstone Handstand) | 25 / 49 / 49 | Unlocks the coin trick you're viewing. Already owned at receipt → next upgrade level. |
| Tricks | Throne Sit / Double Damnation / Comet Corkscrew | 79 / 99 / 129 | Premium tricks (§7.4). |
| Tricks | Trick Pack | 249 | 3 premium tricks at L2 + 30 min 2× Coins boost (§7.10). |
| Tricks | Max This Trick | 49 | Sets the viewed trick to L3. |
| Season | Premium Pass | Director sets: suggested 399 | One per season; retroactive (§8.7). |
| Season | Premium+ | 699 | Premium + 10 tiers. |
| Season | Buy a Tier | 49 | +900 XP, hidden at tier 40. |
| Season | Buy 10 Tiers | 399 (299 in the last 7 days) | +9,000 XP, capped at tier 40, hidden above tier 30. |
| Server-wide | Low Gravity | 99 | §11.3 |
| Server-wide | Double Jump for All | 79 | §11.3 |
| Server-wide | Giant Balls | 49 | §11.3 |
| Server-wide | +2 Min Round Time | 99 | §11.3 |
| Troll | Shrink Everyone | 49 | §11.3 |
| Troll | Slow Everyone | 79 | §11.3 |
| Gifting | Gift a ball / coin pack / tool | same price as the item | Target must be in the server and not own the item. Exclusives, Limited and Starter Pack can't be gifted. If the target leaves before the receipt, the buyer gets the item (or its coin price if already owned). |

### 11.3 Server-wide and troll rules (`Tables/ModifierTable`)
| Modifier | Effect | Duration | Cooldown after it ends | Max per round | Stacking |
|---|---|---|---|---|---|
| Low Gravity | Gravity 196.2 → 110 (×0.56) | 60 s | 30 s | 3 | Same product while active adds time, max 120 s remaining |
| Double Jump for All | Everyone can double jump | 120 s | 30 s | 3 | adds time, max 240 s |
| Giant Balls | Ball scale ×2 | 60 s | 30 s | 3 | adds time, max 120 s |
| +2 Min Round Time | Round clock +120 s | instant | 60 s | 3 (race ≤ 26 min of clock) | n/a |
| Shrink Everyone (troll) | Ball scale ×0.5 | 15 s | **90 s server-wide for any troll** | **4 trolls total** | Doesn't extend; can't buy while one troll is active. Shrink beats Giant while active. |
| Slow Everyone (troll) | MaxForce ×0.70 | 15 s | same | same | same |

Troll rules: the buyer is immune. Players on slot 30 (Finale) are immune. Players in their first 10 min of their first session are immune. Each player can buy at most **1 troll per 3 min**. Banner: "**{Name}** used SLOW EVERYONE! 15s" with buyer name. Different modifiers can run at once.
**Edge case:** the server checks the cooldown/cap before prompting. If a receipt arrives when the cap or cooldown blocks it (race), the effect is **queued** and starts as soon as allowed. If the round ends first, it starts 5 s after the next race starts. Never drop a paid effect.

### 11.4 Upsells (`Tables/UpsellTable`)
Global rules: at most **1 popup per 90 s**, never during countdown or in the first 3 min of a first session (except the Starter Pack after checkpoint 1), never more than one per segment. Close button always visible, 1 tap.

| Trigger | Offer | Cap per session |
|---|---|---|
| 3 falls on the same segment, tools allowed there | Shield ×5 (Tool Refill 25) if Shield charges = 0, else Skip Segment | 3 |
| 5 falls on the same segment | Skip Segment (19) | 3 |
| 8 falls on the same segment | Skip 5 (59) | 2 |
| < 60 s round clock left, not within 3 segments of the finish | +2 Min (99) / Skip 5 | 1 |
| Checkpoint 1 in the first session | Starter Pack | 1 |
| Starter Pack 2:00 left | Starter Pack | 1 |
| Wheel opened with 0 spins | Spin packs (if allowed by policy) | 2 |
| Locked ball or tool viewed | Coins button + Robux unlock button | no popup (inline) |
| Pressed a tool with 0 charges | Tool Refill (25) | 2 |
| Streak broken | Restore Streak | 1 |
| 3+ timed gifts waiting | Unlock All | 1 |
| Limited stock < 100 | Server toast | 1 per 10 min per server |
| *Tricks:* first airtime of the session where a premium trick would have scored ≥ 50% more (client re-plans with Comet Corkscrew) | Inline toast "Comet Corkscrew: +{N} pts on that jump!" → Trick Pack | 1 (toast, not a popup) |
| *Tricks:* Results screen, round trick coins ≥ 20 (near the cap), no 2× Trick Coins pass | Results card "Double your trick coins" → 2× Trick Coins | 1 |
| *Tricks:* locked trick viewed | Coins button + Robux unlock (inline) | no popup |
| *Season:* reached the 1st / 10th / 20th / 30th tier whose premium reward you can't claim | "You'd have earned {reward}. Unlock Premium to claim {N} rewards now!" → Premium Pass | 2 |
| *Season:* 24 h left in the season, not premium, tier ≥ 10 | Premium Pass (+ Season Ending 10 Tiers if tier < 40) | 1 |
| *Season:* reached tier 40 without premium | Molten Monarch preview + all premium rewards → Premium Pass | 1 |
| *Season:* tier < days elapsed − 5 in the last 7 days | Season Ending: 10 Tiers (299) | 1 |

All triggers are `FlagService` flags, so they can be A/B tested (first test: Shield-first vs Skip-first at 3 falls).

---

## 12. Analytics plan

Use Roblox `AnalyticsService`. All event names below are constants in one `Tables/AnalyticsTable` module.

### 12.1 Funnels
**Onboarding** (`LogOnboardingFunnelStepEvent`): 1 Joined → 2 Starter picked → 3 Segment 1 cleared (checkpoint 1) → 4 First fall → 5 Present claimed → 6 First tool used → 7 First trick landed → 8 Checkpoint 5 → 9 Checkpoint 10 → 10 First round ended → 11 First shop purchase → 12 Second session (D1 return).
**Season** (funnel `Season_<id>`, per player per season): Season screen opened → tier 1 → 5 → 10 → 20 → 30 → 40 → Premium bought (separate step, any time).
**Purchase** (`LogFunnelStepEvent`, funnel `Purchase`, step key = product id): 1 Offer shown (with trigger) → 2 Offer tapped → 3 Prompt shown → 4 Receipt granted.
**Round** (funnel `Round`, per session): Race started → checkpoint 5 / 10 / 15 / 20 / 25 / 29 → Finished.

### 12.2 Economy events (`LogEconomyEvent`, currency `Coins`)
Source events with `transactionType` and `itemSku`: `Gameplay` (checkpoint, finish, `Tricks`), `SeasonPass` custom type (sku `SeasonTier_<n>_<Free|Premium>`, `SeasonBonusChest`), `TimedReward` (daily, timed, wheel, present), `IAP` (coin packs, Starter Pack), `Onboarding` (present). Sink events with `Shop` (ball, tool, refill, trick, trick upgrade). Every grant includes the multiplier in a custom field.

### 12.3 Custom events (`LogCustomEvent`)
| Event | Fields |
|---|---|
| `SegmentFall` | segment name, tier, slot, falls on this segment |
| `SegmentClear` | segment name, slot, time taken, falls, tools used |
| `SegmentSkip` | slot, source (product / token) |
| `ToolUsed` | tool id, slot, tier, free or stored charge |
| `ToolDenied` | tool id, reason (cooldown, cap, NoTools, no charges) |
| `ToolSavedFall` | tool id (shield / pocket), tier |
| `WheelSpin` | slice, free / paid |
| `UpsellShown` / `UpsellClosed` | trigger, offer |
| `ModifierActivated` | modifier, buyer, queued (bool) |
| `AntiCheatFlag` | reason, segment, strikes |
| `RoundEnd` | players, finishers, final multiplier, real race length |
| `TrickRoundSummary` | per player per round: airtimes with tricks, clean / sloppy / bail counts, total points, base trick coins, hit round cap (bool), segments that hit the cap, best airtime points, equipped tricks |
| `TrickRejected` | reason (not owned, not equipped, didn't fit, ballistic, no airtime), overshoot seconds |
| `TrickPurchased` / `TrickUpgraded` | trick id, level, coins or Robux |
| `SeasonTierReached` | season id, tier, hasPremium, day of season |
| `SeasonRewardClaimed` | season id, tier, track, reward kind |
| `SeasonPremiumBought` | season id, product (Premium / Premium+), tier at purchase, day, premium rewards unlocked retroactively |
| `SeasonTiersBought` | season id, tiers, price, tier after |
| `ChallengeCompleted` / `ChallengeRerolled` | challenge id, type, scope (daily / weekly) |
| `SeasonClosed` | season id, final tier, hasPremium, rewards auto-claimed |

**Key dashboards:** falls per segment (find unfair segments: any segment where > 40% of average players fall 5+ times is flagged for redesign), D1/D7 retention, Starter Pack conversion, coins per round, tool use per tier, trick coins per round vs race coins (alarm if the median passes 20% of race coins), Sloppy rate (target < 15% of trick airtimes; higher means the picker margin is too small), season tier distribution by day (target: median active player at tier 40 on day ≈ 25), premium conversion and the tier it happened at.

---

## 13. Acceptance criteria

**Round flow**
- [ ] Intermission lasts 20 s, countdown 3 s, race 1200 s of round clock, results 10 s.
- [ ] After N unique finishers the multiplier is min(1 + 0.5N, 3.0) and clock rate min(1 + 0.25N, 2.5).
- [ ] A player joining with < 60 s left waits in the lobby.

**Physics**
- [ ] A ball with S/A/J = r has the attribute values in the §3 table (within 0.0001).
- [ ] Turbo multiplies MaxForce by exactly 1.10.
- [ ] A Speed-10 ball held at 1.6× its normal top speed for 2 s without a boost/tool earns a strike.

**Roster**
- [ ] All 21 balls exist in `BallTable` with stats summing to their rarity budget and each stat 1–10.
- [ ] No ball is named Korblox or Noob.
- [ ] Exclusives can't be bought with Coins, by rarity, or gifted.

**Course**
- [ ] A built course has 30 segments with slots matching §5.2; the seed and names are logged.
- [ ] No segment appears twice in a course when the tier pool is big enough; with the prototype pool, no segment appears in two adjacent slots.
- [ ] A segment missing `PositionParts` or `ParTime` is skipped with a warning, and the course still builds.
- [ ] Every prototype segment is finished by a 1/1/1 ball with no tools in `SegmentTest`.
- [ ] Checkpoint *n* is rejected if *n* ≠ current + 1, if over 20 studs away, or before 0.35 × ParTime.

**Tools**
- [ ] Activation is rejected (and the client rolls back) when on cooldown, out of charges, over the per-segment cap, in a `NoTools` segment, or during countdown.
- [ ] Free charges reset every round; stored charges only go down after free charges are used up.
- [ ] Pocket Checkpoint can't be placed in Hell or Finale.
- [ ] A Shield absorbs exactly one KillBrick touch or one fall, and that fall isn't counted toward upsells.
- [ ] A `ToolRequired` segment gives 1 temporary charge at start and after every respawn there.
- [ ] Tool Belt shows the 3rd slot; without it, slot 3 shows a lock.

**Tricks**
- [ ] A single jump on flat ground with a Jump-10 ball never starts a trick; a jump pad (`JumpPower` 0.40) always does.
- [ ] No trick starts before `MIN_AIRTIME` of continuous airtime, while gliding or grappling, outside the Race state, or when no ground is found within 200 studs below.
- [ ] The auto-picker never starts a trick that its own prediction says ends less than 0.1 s before landing; only equipped tricks ever play, and never the same trick twice in a row.
- [ ] Worked examples 1–3 in §7.5 give exactly 210, 577 and 367 points in a unit test of the scoring function.
- [ ] An early landing never loses earlier tricks: a cut trick at ≥ 50% scores ×0.5, below 50% scores 0, and "SLOPPY!" shows.
- [ ] Falling into a fall volume, touching a KillBrick, a Shield rescue, a skip or a respawn within 0.5 s of touchdown pays 0 and shows "BAIL!".
- [ ] Glider, Grapple or Coil during the airtime halves its points once; Spring and jump pads don't.
- [ ] Trick coins never exceed the segment cap (tier checkpoint coins) or 25 base per round; RoundMultiplier doesn't apply; 2× Coins pass + boost + 2× Trick Coins gives ×4.
- [ ] The server rejects tricks not owned or not equipped, pays only the tricks that fit its own airtime (+0.2 s tolerance), and adds a strike for an overshoot > 0.5 s or an unexplained vertical speed gain > 15 studs/s.
- [ ] With "Show tricks" off, no trick animation or FOV change plays, and the same coins are granted.
- [ ] The first trick ever shows "Big air = auto tricks = bonus coins!" once.

**Season Pass**
- [ ] The active season comes only from `ActiveSeasonId` + `StartUtc`/`EndUtc`; changing the flag in remote config switches it without a code update.
- [ ] XP is only added by server services; no remote can add XP. 40 tiers × 900 XP; tier = min(40, floor(xp/900)).
- [ ] Catch-up ×1.5 applies exactly while tier < days elapsed.
- [ ] A reward can be claimed once, only if reached, and premium only with `hasPremium`; buying Premium unlocks all reached premium rewards at once.
- [ ] Premium Pass, Premium+, Buy a Tier and Buy 10 Tiers grant only in `ProcessReceipt`, idempotently; tier products never push past tier 40; all season products are hidden in the last hour.
- [ ] At season end, a returning player gets every earned, unclaimed reward auto-claimed, `seasonHistory` is written, and XP resets to 0 for the new season; seasonal balls/tricks/trails stay owned.
- [ ] 3 daily and 5 weekly challenges are assigned deterministically per (UserId, day/week); rejoining doesn't change them; 1 free reroll per day (2 with Premium).
- [ ] Seasonal balls can't be bought, gifted or bought by rarity, and aren't counted in the 21-ball collection.

**Economy**
- [ ] Checkpoint coins = tier base × round multiplier × personal multiplier (rounded down, minimum 1).
- [ ] 2× pass + 2× boost gives ×3, not ×4.
- [ ] Skipped segments pay 0 coins and the finish can't be skipped.

**FTUE / present**
- [ ] A new player can't spawn a ball before picking; picking a non-starter id does nothing.
- [ ] New players start with 3 Shield charges equipped in slot 1.
- [ ] First fall in session 1 spawns a present; tapping grants 150 coins, 2 spins, 10 min boost, 2 Shield charges, once ever.
- [ ] A player in session 2 who never claimed doesn't get a present.

**Daily / timed**
- [ ] Claiming twice on one UTC day fails.
- [ ] Missing a day resets to day 1; Restore Streak within 48 h restores it.
- [ ] Day 7 grants Ember Glow only on the first cycle.
- [ ] Timed gifts unlock at 2/5/10/15/20/30/45/60 min of session playtime; the 60-min ball is given once ever.

**Wheel**
- [ ] Weights sum to 100 and the odds screen matches `WheelTable`.
- [ ] Over 100,000 server rolls, each slice is within ±0.5 percentage points of its odds.
- [ ] With `ArePaidRandomItemsRestricted`, paid spin products don't appear anywhere; free spins work.
- [ ] The result is saved before the client animation starts.

**Starter Pack / Limited**
- [ ] The offer disappears exactly 15:00 after `firstJoinAt`, including time spent offline.
- [ ] Buying grants Imp, Grapple Hook, 2,500 coins, 5 spins, 30 min boost, once.
- [ ] 1,000 simulated concurrent buys never assign a duplicate serial or exceed 1,000.
- [ ] "N / 1000 left" matches the DataStore within 60 s.

**Monetization**
- [ ] Every product grants only in `ProcessReceipt` and is idempotent by `PurchaseId`.
- [ ] Troll products: buyer and Finale players are immune; second troll within 90 s is blocked at prompt time and queued if the receipt arrives anyway.
- [ ] No more than 1 upsell popup per 90 s, and each trigger respects its session cap.

**Analytics**
- [ ] Every funnel step in §12.1 fires once per player in a scripted test run.
- [ ] Every coin change has a matching economy event.
- [ ] One `TrickRoundSummary` per racing player per round; `SeasonTierReached` fires once per tier per season.

---

## 14. Open questions for the Director

1. **Prices:** Starter Pack (suggested 99 R$) and Crown of Hell (suggested 1,499 R$). Approve the rest of the price sheet (§11) for M2, with A/B tests after launch?
2. **Race timer:** 20 min (sim says ~5% of average players finish). Is that the right difficulty, or should we aim for ~15% (e.g. 24 min or easier Insane tier)?
3. **Comeback presents** (§10.2): approve the extension?
4. **Troll immunity for new players** (first 10 min): OK? It lowers troll value slightly but protects FTUE.
5. **Limited ball stats:** Crown of Hell's 21-point budget beats Mythics. Keep it a small power edge, or make it cosmetic-equal to Mythic (19)?
6. **Prototype course reuse:** with 20 segments, some repeat in one course (not adjacent). OK until the pool reaches 45?
7. **Boost timers** pause while offline (our proposal) or keep running in real time like `expiresAt` suggests?
8. **Tool unlock vs rental:** permanent tool unlocks with free per-round charges (proposed), or consumable-only?
9. **Trick coins and the finish multiplier:** we leave RoundMultiplier off trick coins so caps stay meaningful. OK?
10. **"Show tricks: Off" keeps the coins** (proposed, for motion-sensitive players). OK, or should Off also turn off trick coins?
11. **2× Trick Coins** as its own 149 R$ pass (proposed), or fold it into the 2× Coins pass?
12. **Season Pass price:** Premium 399 R$ and Premium+ 699 R$ (suggested). Season length 30 days with 40 tiers?
13. **Seasonal items return?** Proposed: Season 1 balls, tricks and trails never come back (real scarcity). Or a "Vault" re-release a year later?
14. **Molten Monarch** has a Mythic budget (19) and is paid-only. OK for P3, or cap seasonal premium balls at Legendary (17)?

---

## 15. Follow-ups (other owners / Director OK)

1. **DataTemplate additions** (needs Director OK): `ownedTools`, `toolCharges`, `equippedTools`, `skipTokens`, and boosts as remaining seconds if Q7 goes that way.
2. **ARCHITECTURE §5.3 "never reuses a segment"** conflicts with a 20-segment prototype pool. Adopt the fallback in §5.3 rule 4.
3. **Reference `MaxForce *= 0.6`** in normal mode: M1 feel test decides whether rating 5 maps to 0.12 or 0.072.
4. **V5 measurement:** programmers measure a Speed-5 ball's top speed in studs/s in M1 so segment lengths and tool stud values (Grapple 80 studs/s, Glider 18 studs/s) can be confirmed.
5. **UpsellTable change:** 3-fall trigger now offers Shield first (A/B against Skip-first). Architecture lists Skip at 3 falls.
6. **New ARCHITECTURE pieces for tools:** a `ToolService` (server), `ToolController` + `ToolBarUI` (client), `ToolTable`, and `GrappleAnchor` tag. Architect to place them.
7. **Late-game coin sink:** after ~40 h nothing is left to buy except coin refills. Plan M4 content (trails for Coins, seasonal balls).
8. **Time Slow is client-only**, so it can't be verified on the server. Acceptable because obstacles are client-animated already; the KillBrick check is client-side too. Security review in M3.
9. **DataTemplate additions for T-025** (needs Director OK): `ownedTricks`, `equippedTricks`, `trickLevels`, `settings.showTricks`, `stats.tricksLanded`, `stats.bestTrickPoints`, `season`, `seasonHistory`, `seasonPremiumCredit`, `challenges`.
10. **New ARCHITECTURE pieces for T-025:** server `TrickService`, `SeasonService`, `ChallengeService`; client `TrickController` (airtime, picker, animation), `TrickPopupUI`, `TricksUI` (loadout/shop/upgrades), `SeasonPassUI`, HUD XP bar; Tables `TrickTable`, `SeasonTable`, `ChallengeTable`; `BallTable` Source enum gains `Seasonal` and a `SeasonId` field. Architect to place them. The 10 Hz server ball sampling for tricks could share the `BallService` speed audit loop.
11. **Animator:** 12 rider trick animations (§7.4), one shared 0.15 s landing blend, and L2/L3 VFX (ember trail, flame burst) for the VFX artist. Durations in §7.4 are exact targets (±0.05 s).
12. **M1 measurements:** single-jump airtime for Jump 1/5/10 balls (sets `MIN_AIRTIME`), and typical airtime of a 0.40 jump pad. Level designers add one optional "trick line" (≥ 1.5 s air) to every Medium+ segment (§7.8); add it to the §5.4 authoring checklist after M1.
13. **Figma frames** needed: `TricksUI`, `TrickPopupUI`, `SeasonPassUI`, HUD XP bar and the Season button badge.
14. **Analytics limits:** check Roblox custom-event limits; tricks log one summary per round (not per jump) for that reason.
