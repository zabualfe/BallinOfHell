# Agent instructions

These are my conventions for building Roblox games. They shape how systems are structured and how the game
looks and feels. They say nothing about what a game is about: genre, content, story and economy come from the
project and from me.

When existing code in a project disagrees with this file, this file wins for new code. Do not rewrite working
code unless I ask.

## Scope

- My explicit instructions take precedence over this file.
- Keep changes focused on what was asked. Do not refactor, rename or reformat unrelated code.
- In a shared project, follow the existing style of files other people own and make the smallest change that
  works there. Use these conventions for new modules.
- Ask before making material design decisions: new currencies, economy numbers, new saved data, anything that
  changes what players keep.
- Code lives in Studio, not on disk, unless the project already uses Rojo or Wally. Read and edit scripts
  through the Roblox Studio MCP tools, and remind me to save the place after changes.

## Working in Studio

- Before editing, find the code (`script_search`, `script_grep`) and read the whole script (`script_read`).
  Read every module a change touches, not only the one being edited.
- Several Studio windows may be open. Confirm which place (`list_roblox_studios`) before changing anything.
- After a change, playtest (`start_stop_play`) and check the output (`get_console_output`) for errors and
  warnings. Fix what you caused before handing back.
- Temporary debugging is fine while working, but remove all of it before handing back: `print` calls, `_G`
  handles added for inspection, debug attributes, test parts and test scripts. Never leave debug data where
  clients can read it.
- UI, maps, models and tagged objects are authored in Studio. Build UI with the Studio MCP tools (inspect the
  tree, add elements, screenshot to check). Never build UI in code unless I ask.
- If no Studio MCP is connected, say so and stop rather than guessing at code you cannot read.

## Code style

- Comments are brief and explain *why*: a reason, a pitfall, a constraint. Never narrate what a line does.
  - Good: `-- Remove in reverse order so earlier indices stay valid.`
  - Bad: `-- loop through the list`
- A system module opens with a short header comment: what it owns, how other code uses it, and any contract.
  Longer modules separate sections with divider lines:

  ```lua
  -- ── Tuning ──────────────────────────────────────────────────────────────
  ```
- No `--!strict` and no type annotations by default. Add one only where it genuinely helps readability.
- Tabs for indentation. Double-quoted strings.
- Fetch every service once at the top with `game:GetService`. Never `game.Players` or `game.TweenService` inline.
- Modern Luau only:
  - Generalized iteration: `for _, item in items do`. No `pairs` or `ipairs`.
  - Iterate an instance's `:GetChildren()` or `:GetDescendants()` explicitly, never the instance itself.
  - `task.wait`, `task.spawn`, `task.delay`, `task.defer`. Never `wait`, `spawn` or `delay`.
  - `os.clock()` for local timing, `workspace:GetServerTimeNow()` for shared time. Never `tick()`.
  - `PivotTo` / `GetPivot`, not `SetPrimaryPartCFrame`. `workspace:Raycast`, not `Ray.new`. `.Position` /
    `.Unit`, not `.p` / `.unit`.
  - `:Connect`, not `:connect`. Compound operators (`+=`) and `continue`.
  - Create one `Random` object per module and reuse it, rather than `Random.new()` on every roll.
- Early returns over nested ifs.
- No two names in the same scope that differ only by case (`chance` and `Chance`).
- Check what a signal actually passes before writing its handler. Do not assume arguments.
- Functions that grant, unlock or buy something return `true` when they did it and `false` when they did not
  (already owned, capped, not loaded), so callers can react.
- No globals. No `_G` tables or functions; share through modules.
- Delete dead code. No commented-out blocks, no `if true then return end` switches, no `Old` / `_LEGACY` copies
  and no archive folders of backups kept in the place.
- Anything that sets up temporary state (connections, spawned effects, changed attributes) collects it in one
  cleanup object (Trove, Maid or a single list) and releases it all in one place when it ends.
- No debug overrides keyed to usernames or place ids in code. Testing shortcuts go behind a Studio-only
  check or an admin command.
- Movement speed, stamina, cooldowns and perks that affect gameplay are decided or checked on the server. The
  client may predict them for feel, never own them.
- No copy-pasted helpers. Number formatting, time formatting and RichText colour strings live in one shared
  helper module each.

### Naming

| Thing | Convention | Example |
| --- | --- | --- |
| Modules and files | PascalCase, named for what they are | `ShopService`, `ItemData` |
| Server systems | PascalCase ending in `Service` | `ShopService`, `QuestService` |
| Module table | Named after the file, never `module` | `local ShopService = {}` |
| Public functions | PascalCase | `ShopService.Buy(player, itemId)` |
| Per-player setup | `SetupPlayer(player)` | `QuestService.SetupPlayer(player)` |
| Locals and local functions | camelCase | `local activePrompt`, `local function getPrice(item)` |
| Constants and tuning values | UPPER_SNAKE, unit in a trailing comment | `local SCAN_RADIUS = 14 -- studs` |
| Private fields on objects | `_camelCase` | `self._connections` |
| Data table fields | PascalCase | `Icon`, `Price`, `Rarity`, `Id` |
| Saved data keys | camelCase | `inventory`, `unlockedItems` |
| Tags and attributes | PascalCase | `Interactable`, `DataLoaded` |
| Network message names | PascalCase | `BuyItem`, `QuestCompleted` |
| Log prefix | `[SystemName]` | `warn("[ShopService] Unknown item " .. itemId)` |

- Booleans read as questions: `isOpen`, `hasLoaded`, `canAfford`.
- Name things for what they are, not how they are used.

## Layout

Default layout for a new project. In an existing project, keep the folders it already has instead of adding
parallel ones.

| Place | Contents |
| --- | --- |
| `ServerScriptService.Script` | Server entry script. Server modules are its children. |
| `ServerScriptService.Script.<System>.<Child>` | Sub-modules belonging to one system. |
| `ServerStorage` | Server-only templates and assets that get cloned. |
| `ReplicatedStorage.Network` | The Network module (see Networking). |
| `ReplicatedStorage.Modules` | Client systems, auto-required by the client entry script. |
| `ReplicatedStorage.Tables` | Pure data: items, prices, rarities, upgrades. No logic. |
| `ReplicatedStorage.Utilities` | Shared helpers and third-party libraries. |
| `StarterPlayerScripts.ClientScript` | Client entry script. |
| `StarterCharacterScripts` | Per-life client code only. |
| `StarterGui` | All authored UI. |

- Everything in `ReplicatedStorage` is visible to clients. Secrets, rules, server-enforced prices and reward
  logic belong on the server.
- Tunable numbers go in `Tables` (shared) or as UPPER_SNAKE constants at the top of a server module
  (server-only). Never bury magic numbers or CFrames inline.
- A helper used by one system stays inside that system. A helper used by two or more goes in `Utilities`.

## Systems

A system is a ModuleScript that owns one area of the game: a table of functions plus its own state.

- **Server systems** own state, validation, saved data and rewards.
- **Client systems** own input, camera, UI and effects. They ask the server for changes and never decide
  outcomes.

### Startup

Modules start themselves when required. There is no `Init` step.

- **Server entry** requires every child module, each in its own thread:

  ```lua
  for _, child in script:GetChildren() do
  	if child:IsA("ModuleScript") then
  		task.spawn(function()
  			local ok, err = pcall(require, child)
  			if not ok then
  				warn(("[Loader] %s failed: %s"):format(child.Name, tostring(err)))
  			end
  		end)
  	end
  end
  ```
- **Client entry** does the same over `ReplicatedStorage.Modules`.
- The client loader owns character lifecycle wiring. A module that needs it exports
  `CharacterAdded(self, character)` and/or `CharacterRemoving(self, character)`; the loader calls
  `CharacterAdded` immediately if a character already exists and connects both for later lives. Modules do
  not connect `CharacterAdded` themselves.
- Each module connects its own events, prompts, tag signals and network messages at require time.
- A module that needs another requires it directly; that is the only ordering.
- Nothing long-running at the top level: waits for authored instances and loops go inside `task.spawn`.
- **Per-player setup** that only needs the player hooks `PlayerAdded` and also covers players already in
  the server:

  ```lua
  local function onPlayerAdded(player)
  	-- per-player setup
  end

  Players.PlayerAdded:Connect(onPlayerAdded)
  for _, player in Players:GetPlayers() do
  	task.spawn(onPlayerAdded, player)
  end
  ```

  When setup must wait for something else (data loaded, an area assigned), expose `SetupPlayer(player)` and
  call it from the one place that controls that order.

### When to make a new system

Make a new module when a feature has its own state, its own per-player setup or cleanup, or its own network
messages. Otherwise:

- Part of an existing feature: a child module of that system.
- Behaviour on many tagged objects: a tag-driven registry (see Tagged behaviour).
- Data: a table in `Tables`.
- A stateless helper: `Utilities`, or local to the system that uses it.

Keep entry scripts thin. Game logic goes in modules.

### Sequenced flow

When a game runs as a sequence (rounds, phases, levels, story beats), the server drives it from an ordered
list of steps, not one long script of waits:

- Each step has a `Name`, a `Run` that plays it, and a `Skip` that puts the world in the state the step ends
  in, instantly.
- A Studio-only setting names the step to start from. Everything before it is skipped, everything after runs.
- Steps are short. Anything reusable inside a step (a vote, a wave, a cutscene) is its own system that the
  step calls and waits on.

### Example system

```lua
-- DailyRewardService
-- Grants one reward per player per day.
--
-- Usage:
--   DailyRewardService.Claim(player) -> boolean   -- false if already claimed today

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(script.Parent.PlayerData)
local Network = require(ReplicatedStorage.Network)

local DailyRewardService = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local CLAIM_COOLDOWN = 24 * 60 * 60 -- seconds
local REWARD_AMOUNT = 100

function DailyRewardService.Claim(player)
	local lastClaim = PlayerData.Get(player, "lastDailyClaim") or 0
	local now = workspace:GetServerTimeNow()
	if now - lastClaim < CLAIM_COOLDOWN then
		return false
	end

	PlayerData.Set(player, "lastDailyClaim", now)
	PlayerData.Set(player, "coins", PlayerData.Get(player, "coins") + REWARD_AMOUNT)
	return true
end

Network.OnEvent("ClaimDailyReward", function(player)
	if DailyRewardService.Claim(player) then
		Network.FireClient(player, "DailyRewardClaimed", REWARD_AMOUNT)
	end
end)

return DailyRewardService
```

### Objects with many instances

When a system manages many independent things of the same kind (one area per player, one agent per NPC),
give each its own object, owned by the system in a table keyed by player or instance:

```lua
local Thing = {}
Thing.__index = Thing

function Thing.new(owner, model)
	return setmetatable({
		Owner = owner,
		Model = model,
		_connections = {},
	}, Thing)
end

function Thing:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
end

return Thing
```

- Constructor is `.new`; methods use `:` and PascalCase (`:Setup`, `:Load`, `:Save`, `:Destroy`).
- The owning system creates the object, stores it, and saves and destroys it on leave and in `BindToClose`.
- Loading replays saved state through the same code path as live play (without charging), not through a
  separate rebuild path that can drift.
- Instances cannot be saved. Convert instance keys to names or ids before saving.

### Plug-in content modules

When a feature has many variants (abilities, interactables, item types, events), each variant is its own
module in one folder, sharing a documented contract. The system scans the folder and dispatches by name,
usually from an attribute on the object.

- Write the contract at the top of the owning system and in the first variant. A system other people will
  configure or drive (AI, weapons, anything with many tunable fields) also gets a `Documentation` module
  beside it: every field with its type and meaning, the available states, and a short usage example.
- Name each module after its variant. If a variant has server and client halves, both use the same name.
- One module serves every object that uses it. The object is passed in; never read `script.Parent`.
  Per-object state lives in a table keyed by the instance.
- Variants may carry data the system acts on (rewards, costs, cooldowns). Granting and validation stay in
  the system, not in each variant.
- When the system picks variants itself (random events, encounters, spawns), each variant declares its own
  eligibility and timing as fields. The system filters to eligible variants, avoids repeating the last one,
  and picks; variants never decide when they run.

```lua
-- Contract: OnActivate(object, player)
--   object -- the tagged instance whose "Interactable" attribute names this module
--   player -- who activated it

local Lever = {}

local busy = {}

function Lever.OnActivate(object, player)
	if busy[object] then
		return
	end
	busy[object] = true

	-- behaviour

	busy[object] = nil
end

return Lever
```

### Tagged behaviour

Behaviour on world objects comes from CollectionService tags plus attributes, never from scripts cloned into
each object.

- The tag says *what* the object is. Attributes carry its configuration and state.
- Keep a registry `registry[instance] = data`. Register from `GetTagged` plus `GetInstanceAddedSignal`;
  unregister on `GetInstanceRemovedSignal`, which also fires on destroy.
- One throttled loop for all instances (an accumulator against a `SCAN_INTERVAL` constant), not a connection
  per object.
- Tags can replicate after the client starts. Per-object setup that yields runs in `task.spawn`.

### Misconfiguration and errors

- When an authored object is set up wrong, `warn` with the system prefix, the full path and what was expected,
  then disable only that object and let everything else carry on:

  ```lua
  warn(("[SystemName] %s is tagged %q but has no %s attribute"):format(object:GetFullName(), TAG, "Config"))
  return
  ```
- `error` / `assert` only for programmer mistakes that should never happen in a correct build.
- `pcall` around risky or yielding engine and web calls. `xpcall(fn, debug.traceback)` around long-running
  loops, warning on failure.
- After every yield, re-check that what you were working on still exists and still belongs to the same owner.
- Use deadlines (`os.clock() + TIMEOUT`) instead of waiting forever. Cancel stale async work with a token or
  generation counter.
- Handle the empty case: no players left, an empty list, a missing winner. Loops and "pick the best" logic
  must not index nil when everyone has left.

## Networking

All client–server messages go through one `Network` module: a single RemoteEvent (plus one RemoteFunction
when a reply is needed) carrying a string message name. Never create RemoteEvents or RemoteFunctions for a
feature, a button, a tool or an object.

If the project has no `Network` module yet, create one with this API:

| Side | API |
| --- | --- |
| Server | `Network.OnEvent(name, fn(player, ...))`, `Network.OnInvoke(name, fn(player, ...))`, `Network.FireClient(player, name, ...)`, `Network.FireAllClients(name, ...)` |
| Client | `Network.OnEvent(name, fn(...))`, `Network.FireServer(name, ...)`, `Network.Invoke(name, ...)` |

- The server side rate-limits every client message per player (a token bucket) and rejects non-string or
  overlong names before dispatch.
- The client side queues messages that arrive before a handler is registered, with a cap, and warns when the
  cap is hit.
- `OnInvoke` errors if a handler is registered twice for the same name.

Rules for handlers:

- Validate everything on the server: argument types, whitelists, ownership, quantities, ranges, state and
  cooldowns. Fail silently with `return`.
- Instances, positions and CFrames sent by a client are untrusted. Check class, tag, ownership and distance
  before using one. Never apply damage, currency or settings straight from a client value.
- Anything that costs the player: validate everything, then charge, then grant. Never charge first.
- When the client picks from options the server offered, store a seed in the player's data and regenerate the
  options on the server to check the pick.
- A purchase that acts on a specific object (skip this timer, revive that player) stores the target in a
  server-side table keyed by player before prompting. The receipt handler reads it, returns `false` if it is
  missing, and clears it after granting.
- Filter all player-entered text with TextService before storing it or showing it to others.
- Debounce buttons and prompts on the client so normal play never hits the rate limit.
- Use attributes for simple replicated values and messages for events.
- Server-wide modifiers (a temporary multiplier, an active world event) are attributes on `workspace` that
  other systems read. Whatever sets one is responsible for resetting it, including when it errors or ends
  early.

## Player data

Saved data goes through one server `PlayerData` module. Only `PlayerData` touches the storage library
(ProfileStore by default for new projects). If the project has no `PlayerData` yet, create one with this API:

| Call | Use |
| --- | --- |
| `PlayerData.Get(player, key)` | Deep copy of a key. Safe to mutate, then `Set` it back. |
| `PlayerData.Set(player, key, value)` | Save and replicate a whole key, and fire update listeners. |
| `PlayerData.SetPath(player, path, value)` | Write a single nested value. Use on hot paths. |
| `PlayerData.Peek(player, key)` | Live table, read-only. Cheap lookups only; never mutate it. |
| `PlayerData.OnUpdate(player, key, fn)` | Listen for changes. Returns an object with `Disconnect`. |

- Pattern: `Get` the key, change the copy, `Set` it back.
- A `DataTemplate` table holds every key with a safe default; missing keys are filled in on load. Ask me
  before renaming or removing a key or changing the store name.
- The server sets a `DataLoaded` attribute on the player once data is ready. Anything that reads data waits
  for it. The client reads replicated data through a client `PlayerData` with `Get(key)` and an update signal.
- Unsaved per-player runtime state lives in the system that owns it, in a table keyed by player, cleared on
  leave.
- Never reset or wipe progress to fix bad data. Migrate it.
- When removing items from a list while iterating, collect the indices first, then remove in reverse order.

## Visual design

### UI

- UI is authored in `StarterGui` and driven from client modules. Find elements by name and check `IsA` before
  use, so a renamed element fails visibly.
- Menus that should be one-open-at-a-time share one small manager that opens, closes and blurs the background
  behind them, rather than each menu handling it. A menu can opt out of the blur with an attribute.
- Player-facing text uses RichText. Colour strings are built by the shared helper from `Color3:ToHex()`.
- Colour carries meaning consistently: each rarity, currency or item type has one colour (or gradient for the
  top tiers), defined once in `Tables` and used everywhere that thing is named.
- Short notifications start with an emoji that sets the tone (a warning, a reward, an unlock).
- Support small screens, touch and gamepad as well as mouse and keyboard. Check `ViewportSize` and compact the
  layout on small screens.

### Motion

- UI motion is short and snappy: 0.1–0.3 s tweens, `Back` easing for things appearing, `Quad` for moving and
  fading.
- Opening a panel pops it in: its `UIScale` starts slightly small and tweens to full size.
- A value that changes (a counter, a stock count) bumps: a quick scale down-and-back on its label.
- Scripted world motion (doors, levers, lifts) steps a timer on `Heartbeat` and lerps between two CFrames with
  an eased alpha from `TweenService:GetValue`, so it can be interrupted and chained.
- Every tween, spring and eased value reads its duration and style from constants at the top of the module.

### Feedback

- Every player action gets feedback: a sound plus a visual (a particle burst, a scale bump, a flash).
- Held or repeated actions escalate: pitch rises on each repeat, resetting when the player lets go.
- Gains are shown, not just applied. Rewards fly from where they were earned into the HUD counter, driven by
  the data update (listen to the key's update signal, compare with the last value, animate the difference).
  The server does not send a separate "play effect" message for something the data change already says.
- Near-identical UI or effects for several variants (one per currency, one per event) are one module driven by
  a config table per variant, never a copy per variant.

### Visual performance

- Effects and cosmetics run on the client. The server owns the state they show.
- Anything expensive to render (ViewportFrames, particles, many animated models) is built only near the
  camera, torn down when far (with a gap between the two distances so it does not flicker), and capped at a
  fixed budget.
- Heavy setup is queued and built one at a time, nearest first, rather than all at once.
- Poses that never change are frozen animation frames, not looping tracks.

## Purchases

- One module owns `MarketplaceService.ProcessReceipt`. Nothing else sets it.
- Developer products live in one table keyed by product id, each with a `Name` and an `Effect(player)` that
  grants through the owning system and returns `true` once granted. Return `false` so Roblox retries later.
- Product and pass ids live in `Tables`, not scattered through scripts.
- Never grant rewards from a client message. The client only prompts the purchase.
- Check game passes on the server with `UserOwnsGamePassAsync`, not through receipts.
- Ask me before adding a purchase whose reward lives outside the player's saved data (server-wide effects).

## Experiments and feature flags

- A/B tests and feature flags are plug-in modules too: each declares its config key, a default state, a
  `Disabled` switch and a handler per state. One controller loads the remote configs and runs them; gameplay
  code asks the controller for a value instead of hard-coding variants.
- Every flag has a safe default that applies if remote config never loads.

## Admin

If the project has an admin console, add debug commands there rather than temporary chat hooks or test
buttons. Default to Cmdr when a project needs one.
