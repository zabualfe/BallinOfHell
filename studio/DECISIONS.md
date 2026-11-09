# Decisions Log

Newest first. Director decisions are marked 🎬. Routine team calls are marked 🛠.

## 2026-11-09
- 🎬 **No more lobby/round loop: the course is built once at server start and stays up.** It always chains from `workspace.Lobby.Start`'s pivot, so it runs out of the lobby. Players spawn in the lobby already in ball mode (right after the starter pick for new players) and roll onto the course; finishing returns them to the lobby after 5 s for a fresh run. The round steps, StepRunner and RoundMath are deleted. Side effects until rounds come back in some form: per-round systems (tool charges, trick caps, season rounds, modifiers) no longer reset, checkpoint coins pay again on every run, there is no round clock or finish multiplier, and the season bar unlocks on the player's first finish.
- 🎬 **Downhill is faster; uphill is unchanged.** The ground probe is now a sphere cast that records the surface normal; steering downhill multiplies the ground target speed by up to 1.57× at 45°. The speed audit allows that maximum.
- 🎬 **The cosmetic ball rolls by CFrame; jump only sets upward velocity; ground stops fast; air top speed is higher.** BallRoll spins each ball through its root Weld's C0 on every client. The Humanoid's own jump is disabled. SmoothStopRate 6 → 20. Airborne steering targets 1.25× the ground top speed (`AirTopSpeedMultiplier`, tune) and the speed audit allows it.
- 🎬 **The ball is purely cosmetic; a VectorForce moves the player's part.** The root part (a frictionless 4-stud sphere) is the only physical body. The ball model is welded to it, massless and non-colliding, and an AlignOrientation keeps anything from rolling. Why: back to basics on core movement.
- 🎬 **The player character is just a Humanoid and its root part.** `StarterPlayer.StarterCharacter` replaces the avatar (`LoadCharacterAppearance` off), and the rider animations are gone from BallController. Why: back to basics on core ball movement. Trick animations have no rider to play on until tricks get a new form.

## 2026-11-08 (Sprint 5)
- 🎬 **The Studio place is "ballin v2 the sequel"** (placeId 122054442557559). "KC Dev" is a different project; don't touch it.
- 🎬 **Remaining UI is designed in Figma this sprint.**
- 🎬 **Inventory shows every ball and is where balls are bought.** The Shop no longer sells balls. Why: Director review of the T-044 frames.
- 🎬 **Shop has no tabs:** one scrolling page of sections.
- 🎬 **HUD was too big:** redesign with a much smaller footprint (T-050). The built Studio HUD must be updated to match.
- 🎬 **HUD and Shop follow the Director's reference screenshots:** free-standing outlined icons around the screen edges, hero offer cards above a scrolling product grid, hero offer popups. Applied as layout conventions in Ball of Hell's own art and theme; no reference art, items or names are copied.
- 🎬 **First-join popups:** Starter Pack right after the ball pick, Crown of Hell after checkpoint 1. Replaces the GDD §10.1 step 6 and §10.6 timing, and adds an exception to the §11.4 first-3-minutes rule (T-052).
- 🎬 **All screens get the chunky reference style** in one restyle pass after the T-050 look is approved (T-051).
- 🎬 **Brighter UI colours:** the near-black charcoal palette is rejected. Theme token values change in Figma first, then in `docs/UI_ELEMENTS.md` and the Studio Theme.
- 🎬 **Director rejected the red UI ("sucks").** The all-crimson palette was a Chief of Staff direction and is replaced: hue-separated palette, shaded chunky art, heavier type (T-050).
- 🎬 **Figma AI image generation approved for UI art, capped at about 15 images** (T-050).
- 🎬 **T-050 direction approved.** No more AI-generated UI art for now; ball images come from Blender renders (T-054).
- 🛠 **Studio UI build waits for the Director's review of the Figma frames (T-047).** Why: changes are cheaper in Figma than in Studio.

## 2026-11-08 (first Studio integration)
- 🛠 **Require cycles broken.** EconomyService now requires GamePassService directly (the `SetPassChecker` seam is gone) and reads the `RoundMultiplier` workspace attribute instead of requiring RoundService. Why: specs load modules one at a time, so three cycles only showed up in Studio.
- 🛠 **`tools/check_requires.py` added:** run it with the specs. It catches bad `script.Parent` paths and server require cycles offline.
- 🛠 **ObstacleController waits for a tagged Model's parts before registering.** Why: under StreamingEnabled tags arrive before parts, which disabled Vanishing platforms.
- 🛠 **`ReplicatedStorage.Assets` lives only in Studio** and was removed once by a sync. If it disappears again, it needs a home the sync leaves alone.

## 2026-11-07 (Director: "get started on ALL the sprints, use best judgement on decisions")
- 🛠 **Studio MCP isn't connected, so all file-based code goes ahead.** Studio-only work is blocked until Studio connects: asset port (T-004), building UI in StarterGui, client UI modules that bind to it, and playtest QA. Server systems expose their network messages and data keys, so the UI only needs wiring later.
- 🛠 **Toolchain:** add `default.project.json` (Rojo naming: `init.server.luau`, `.client.luau`, `.luau`) mapping the root folders. Aftman gets selene, stylua and lune. ProfileStore and Trove are vendored into `ReplicatedStorage/Utilities`. Pure logic is unit-tested offline with lune.
- 🛠 **GDD §14 open questions: the GDD's proposed answers are working defaults.** Q1: prices go into the tables as proposed and stay placeholders, since nothing is published without the Director. Q2: 20 min, tunable. Q3: comeback presents are not built. Q4: troll immunity for new players. Q5: Crown keeps 21. Q6: non-adjacent repeats are OK. Q7: boost timers pause offline (remaining seconds). Q8: permanent unlocks with free per-round charges. Q9: no RoundMultiplier on trick coins. Q10: Off keeps the coins. Q11: separate 2× Trick Coins pass. Q12: 399/699 R$, 30 days, 40 tiers. Q13: seasonal items never return. Q14: Molten Monarch stays at 19. **Any of these can be reversed before launch. Q1 and Q12 prices still need the Director's sign-off before publishing.**
- 🛠 **DataTemplate additions from GDD §15.1 and §15.9 are adopted.** The store is `PlayerData_v1`, a new store, so no migration is needed yet.
- 🛠 **No git commits** until the Director decides on commits.
- 🛠 **Ball model names:** `DoomKnight` and `Imp` replace the reference models "Korblox" and "Noob". The 3D Artist renames the models when porting them (T-004).
- 🛠 **Cmdr keeps its own CmdrEvent/CmdrFunction remotes.** This is a vendored third-party exception to the one-Network rule. The server BeforeRun hook gates every command. The console key is F2.
- 🛠 **Sprint 1 review (T-008a/b) found 9 must-fixes; all were fixed in T-008c.** Among them: array paths in SetPath, StreamingEnabled-safe ball binding, Model-tagged boost pads, and leaking the boost multiplier. The speed audit also gained a position-delta check.
- 🛠 **Analytics:** EconomyService logs each coin change itself, because PlayerData.Changed carries no reason. Onboarding funnel steps dedupe per session for now. A saved `analyticsOnceSteps` key would make them once-ever (backlog, small).
- 🛠 **Trick scoring follows the GDD formula. GDD §7.5 example 2 has an arithmetic slip:** 156.25 + 421.875 = 578.125, not 577. The spec asserts 578. The GDD text needs a correction (Game Designer, with Director OK).
- 🛠 **Sprint 2 economy review (T-033a) fixes were applied in T-033b:** the Robux-ball double pay, re-claimable partial grants, and the Daily VIP maths (now ×(1 + pass + vip), so day 1 with VIP and the pass pays 125).
- 🛠 **AGENTS.md wins over the studio role briefs** where they disagree: no `--!strict`, Network may use one RemoteFunction, and tuning lives in `ReplicatedStorage/Tables`, not `Config/`.

## 2026-11-07 (Director answers to ARCHITECTURE.md §9)
- 🎬 **Shared course, rebuilt every round.**
- 🎬 **Each run draws 30 segments from a larger pool** (about 20 for the prototype, 45+ at launch).
- 🎬 **Code lives in files at the repo root** (`ReplicatedFirst/`, `ReplicatedStorage/`, `ServerScriptService/`, `ServerStorage/`) and auto-syncs to Studio. Per-task git commits not yet decided, so don't commit until asked.
- 🎬 **One currency: Cash/Coins.** No premium currency.
- 🎬 **Server-wide and troll products approved**, with caps and cooldowns.
- 🎬 **Reuse the Ballin Revamped assets** (the Director owns them). Rename the Roblox-item names.
- 🎬 **Title: "Ball of Hell".**
- 🛠 **GDD sections §7 Trick System and §8 Season Pass written (T-025).** The architecture gained ChallengeService, TrickPopupUI/TricksUI, SeasonXpBar and a `Seasonal` ball source.
- 🎬 **Tricks are automatic, with no tap or button.** Players influence them through airtime and their equipped tricks.
- 🎬 **Add a season pass** with a free and a paid track. SeasonService is in the architecture (§6.10), and the GDD section was added to T-025.
- 🎬 **Add a trick system:** airtime tricks performed by the rider, earning extra coins. TrickService is in the architecture (§6.9), and the GDD section went to the Game Designer as T-025.
- 🛠 **GDD v1 written (T-001).** The architecture now allows non-adjacent segment repeats while the pool is small, has a `GrappleAnchor` tag and has `ToolBarUI`. Why: GDD §13 follow-ups 2 and 6.
- 🎬 **The Figma file is the UI design source:** https://www.figma.com/design/Vsk0yM8NFKD8QOLRjKNeqo/BallinOfHell?node-id=0-1. One frame per UI module; the UI Designer builds Studio UI to match.
- 🎬 **Add gameplay tools** (usable items that help during a run). ToolService was added to the architecture (§6.8), and the GDD section went to the Game Designer as part of T-001.
- 🎬 **The Game Designer proposes prices; the Director sets the limited ball and starter pack prices.**

## 2026-11-07
- 🛠 **Keep the reference segment contract (`PositionParts.StartPart/EndPart` chaining) but rewrite all systems to AGENTS.md conventions.** Why: the contract makes random 30-segment courses cheap; the reference structure conflicts with AGENTS.md and has security gaps (ARCHITECTURE.md §1).
- 🛠 **All purchases go through one ProcessReceipt owner.** Why: the reference granted in PromptProductPurchaseFinished, which can lose or forge purchases.
- 🛠 **Limited ball is a dev product with DataStore UpdateAsync stock plus MemoryStore reservations.** Why: game passes can't be capped, and reservations prevent overselling.
- 🛠 **Paid wheel spins show odds and are hidden when PolicyService restricts paid random items.** Why: Roblox paid random item policy.
- 🛠 **Starter Pack timer is wall-clock from first join.** Why: real urgency, no fake timers.
