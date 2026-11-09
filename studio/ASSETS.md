# Asset Registry

| Name | Type | Owner | Source file | In place at | Status | Notes |
|------|------|-------|-------------|-------------|--------|-------|
| Start | Model | Programmer (T-004b) | Studio | `ServerStorage.CourseParts.Start` (StartPart origin, EndPart 30 studs ahead; 60-wide pen) | placeholder | |
| EndTrack | Model | Programmer (T-004b) | Studio | `ServerStorage.CourseParts.EndTrack` (finish platform + arch, no EndPart) | placeholder | |
| CheckpointFlag | Model | Programmer (T-004b) | Studio | `ServerStorage.CourseParts.CheckpointFlag` (non-colliding joint arch) | placeholder | |
| Ball models (23, by ModelName) | Model | Programmer (T-004b) | Studio | `ServerStorage.Balls.<ModelName>` (Ball part, 4 stud sphere, rarity colour) | placeholder | |
| StarterCharacter | Model | Programmer | Studio | `StarterPlayer.StarterCharacter` (Humanoid + 4-stud white sphere HumanoidRootPart with RootAttachment, frictionless CustomPhysicalProperties; `LoadCharacterAppearance` off) | placeholder | The root part is the only physical body; the ball is a cosmetic shell welded to it |
| Lobby | Model | Programmer (T-004b) | Studio | `Workspace.Lobby` (Spawn SpawnLocation at 0,21.5,300) | placeholder | |
| Present | Model | Programmer (T-004b) | Studio | `ReplicatedStorage.Assets.Present` (ProximityPrompt) | placeholder | |
| Trail | VFX | Programmer (T-004b) | Studio | `ReplicatedStorage.Assets.Trail` | placeholder | |
| DropShadow | VFX | Programmer (T-004b) | Studio | `ReplicatedStorage.Assets.DropShadow` | placeholder | |
| Sounds | Audio | Programmer (T-004b) | Studio | `ReplicatedStorage.Assets.Sounds` (empty folder) | placeholder | |
| Figma foundations + HUD, StarterPickUI, ShopUI, InventoryUI frames | UI | UI Designer (T-044) | Figma Vsk0yM8NFKD8QOLRjKNeqo (Foundations 15:830; HUD 11:59, StarterPickUI 11:159, ShopUI 14:286, InventoryUI 14:471, ShopUI Desktop 14:635) | not built (HUD, StarterPickUI exist in Studio) | in progress | Awaiting Director review (T-047) |
| Figma DailyUI, TimedUI, WheelUI, StarterPackUI, LimitedUI frames | UI | UI Designer (T-045) | Figma Vsk0yM8NFKD8QOLRjKNeqo (20:905, 20:1067, 21:958, 21:1115, 21:1260) | not built | in progress | Restyle in T-051. Missing: Limited SOLD OUT and owner serial states, Grapple Hook and Rocket icons |
| Figma SeasonPassUI, TricksUI, ToolsUI, SettingsUI, UpsellUI frames + RewardCard, LoadoutSlot, Toggle, ToolRow | UI | UI Designer (T-046) | Figma Vsk0yM8NFKD8QOLRjKNeqo (20:1670, 20:1722, 20:1774, 20:1826, 20:1878; components 20:1322, 20:1329, 20:1336, 20:1385) | not built | in progress | Restyle in T-051. Missing: tool art, WEEKLY content, Premium+, Max This Trick, Robux Tool Refill on ToolsUI |
| Figma T-050 rework: HUD, InventoryUI, ShopUI + Desktop, OfferPopupUI, OfferPopupUI_Crown, 15 generated art images | UI | UI Designer (T-050) | Figma Vsk0yM8NFKD8QOLRjKNeqo (11:59, 14:471, 14:286, 14:635, 34:2706, 34:2749) | not built | in progress | Awaiting Director approval. Needs art: passes, tools, tricks, products, 17 balls. Studio Theme and `docs/UI_ELEMENTS.md` need the new token values, `Menu.Timed` and `CrownOffer` |
| Figma T-053 token changes (for Studio Theme) | UI | UI Designer (T-053) | Ash 40,30,130; Panel 70,56,240; PanelRaised 108,96,255; Track 36,28,130, on top of the T-050 tokens | not built | in progress | HUD buttons must stay 44×48.7 in Studio, since instance bounds are the hit area |

Types: Model · UI · VFX · Animation · Audio · Texture
Statuses: placeholder · in progress · final · needs rework

## Required by code, not yet authored (Studio)
| Name | Type | Expected at | Used by | Status |
|------|------|-------------|---------|--------|
| Ball models (21 + 2 seasonal) | Model | `ServerStorage.Balls.<ModelName>` (BallTable; DoomKnight/Imp renamed) | BallService (sphere fallback) | placeholder (T-004b) |
| Segments (20 for the prototype) | Model | `ServerStorage.Segments/<Tier>/<Name>` | CourseService | done (Director) |
| Start, EndTrack, CheckpointFlag | Model | `ServerStorage.CourseParts` | CourseService | placeholder (T-004b) |
| Lobby spawn | Part | `workspace.Lobby.Spawn` | RoundService | placeholder (T-004b) |
| Present | Model | `ReplicatedStorage.Assets.Present` (ProximityPrompt/ClickDetector inside) | FirstFallPresent | needed |
| Trail, DropShadow | VFX | `ReplicatedStorage.Assets.Trail`, `.DropShadow` | BallService, BallController | placeholder (T-004b) |
| Sounds | Audio | `ReplicatedStorage.Assets.Sounds.<BoostPanel/JumpPad/KillBrick…>` | ObstacleController | needed |
| StarterPickUI + HUD (others still needed) | UI | `StarterGui` | Onboarding + T-035 | StarterPickUI/HUD built (T-035a) |
| 12 trick animations | Animation | ids in `TrickTable` | TrickController | needed |
