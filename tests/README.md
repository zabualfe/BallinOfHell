# Offline tests

Run from the repo root: `lune run tests` (exit code 1 on any failure). Lint: `selene tests ReplicatedStorage ServerScriptService/Script StarterPlayer`.

## Writing a spec
Create `tests/<anything>/Name.spec.luau`. `describe`, `it`, `expect`, `load`, `Random`, `Color3`... are globals:

```lua
describe("Weighted", function()
	local Weighted = load("ReplicatedStorage/Utilities/Weighted") -- repo path, no extension
	it("returns nil on empty", function()
		expect(Weighted.Pick({}, Random.new(1))):equal(nil)
	end)
end)
```
`expect(v)` offers `:equal(x)` (deep for tables), `:near(x, eps)`, `:truthy()`, `:falsy()`, `:throws(substring?)` (v is a function).
Each spec file gets a fresh module cache, so state never leaks between files.

## Fake environment
- `load(path)` requires a game module. Folders/files map like Rojo: `Name.luau`, `Name/init.luau`, `.server.luau`, `.client.luau`.
- `script` is a fake Instance: `.Name`, `.Parent`, `.ClassName`, child access by name, `GetChildren`, `GetDescendants`, `FindFirstChild`, `WaitForChild` (errors instead of hanging), `IsA`, `GetFullName`. Read-only.
- `game:GetService`: ReplicatedFirst, ReplicatedStorage, ServerScriptService, ServerStorage, StarterPlayer are filesystem-backed (`require(ReplicatedStorage.Tables.BallTable)` works). Stubs: Players, RunService, CollectionService, HttpService, TweenService (signals never fire; unknown members error). `game:SetService(name, obj)` injects your own fake.
- Globals: `task` (Lune's), `warn` (prints `[warn] ...`), `workspace` (only `GetServerTimeNow`), `Random` (own seeded PRNG; values differ from Roblox, only the API matches), Color3/Vector3/CFrame/UDim/Enum... from `@lune/roblox`.
- Not supported: real Instances, Players/characters, RemoteEvents, DataStores, physics, time passing for `task.wait` beyond real time. Test pure logic; keep engine calls behind small seams.
- Lune's `Color3:ToHex()` is uppercase; compare case-insensitively.
