# UI element map

Authored UI in `StarterGui` (cloned to `PlayerGui`). Programmers wire from this list. All values in Studio are
placeholders; code overwrites them. Find elements by name and check `IsA`, per AGENTS.md.

## Theme: `StarterGui.Theme` (StyleSheet)

Every ScreenGui has a `StyleLink` to it. Tokens are attributes on the StyleSheet; rules apply them by tag
(CollectionService tags act as style classes).

| Token | Value | Use |
| --- | --- | --- |
| `Ash` | 12,8,8 | modal dimmer |
| `Panel` / `PanelRaised` | 30,22,21 / 48,34,31 | charcoal panels / buttons, wells |
| `Stroke` | 8,4,4 | outlines, text outline |
| `Ink` / `InkDim` | 255,241,226 / 196,170,152 | main / secondary text |
| `Ember` / `EmberDeep` / `Lava` | 255,110,20 / 196,60,10 / 255,62,24 | accent, CTA |
| `Gold` | 255,202,64 | coins, rewards, XP fill |
| `Alert` | 235,40,40 | badge dots |
| `Track` / `Locked` | 18,12,12 / 90,80,78 | bar tracks / locked slot |
| `RadiusS` / `RadiusM` / `RadiusPill` | 8px / 14px / 100% | corners |
| `StrokeThin` / `StrokeThick` | 2 / 3 | stroke widths |
| `FontDisplay` / `FontBody` | LuckiestGuy / FredokaOne | headings, numbers / body text |

Tags: `Panel Raised Accent Alert Track Fill XpFill Locked Dimmer` (fill), `Round RoundS Pill` (corner),
`Outline OutlineThin Highlight TextOutline` (stroke), `Shade` (vertical gradient), `Display Body` (font + scaled
text), `Dim GoldText EmberText` (text colour), `Button`.

**Override rule:** a property set directly on an instance (in Studio or from code) beats the style. So code can
set `TextColor3` or `BackgroundColor3` (e.g. rarity colour from `RarityTable`) freely. Corners and strokes come
from tags (pseudo-instances), so to change a stroke, swap the tag (e.g. `Outline` to `Highlight`); don't add a
UIStroke.

Rarity colours are **not** in the theme. They always come from `Tables/RarityTable.Color` / `.Gradient`.

## `StarterGui.StarterPickUI` (ScreenGui, `Enabled = false`, DisplayOrder 20)

Onboarding enables it; the UI module calls `Onboarding.PickStarter(id)`.

| Path | Type | Shows / does |
| --- | --- | --- |
| `Backdrop` | Frame | dims the world (no close button, per GDD §10.1) |
| `Title` | TextLabel | "PICK YOUR FIRST BALL!" |
| `Cards` | Frame | row of cards, `UIListLayout`; `Cards.UIScale` is for the pop-in |
| `Cards.<id>` | Frame | one per starter: `sprinter`, `grip`, `bouncer` (attribute `BallId` = id) |
| `Cards.<id>.Name` | TextLabel | ball name. **Use `card:FindFirstChild("Name")`**: `card.Name` is the property |
| `Cards.<id>.Identity` | TextLabel | one-line `BallTable.Identity` |
| `Cards.<id>.Rarity` | TextLabel | rarity name; set `TextColor3` from RarityTable |
| `Cards.<id>.Preview` | ImageLabel | ball image (`Image`); hide `Preview.Placeholder` once set |
| `Cards.<id>.Speed` / `.Acceleration` / `.Jump` | Frame | stat row: `.Track.Fill` Size X = stat/10, `.Value` text, `.Label` caption. `Track.Ticks` draw the 10 pips |
| `Cards.<id>.Pick` | TextButton | calls `Onboarding.PickStarter(id)` |
| `Cards.grip.EasiestTag` | Frame | "EASIEST" ribbon (`.Label`); grip card carries the `Highlight` tag |

## `StarterGui.HUD` (ScreenGui, enabled, DisplayOrder 5)

| Path | Type | Shows / does |
| --- | --- | --- |
| `TopBar.Coins.CoinsLabel` | TextLabel | coin balance ("1,250"); bump + RewardFly target is `TopBar.Coins.Icon` |
| `TopBar.Timer.TimerLabel` | TextLabel | round clock "mm:ss" |
| `TopBar.Multiplier.MultiplierLabel` | TextLabel | "×1.5"; `TopBar.Multiplier.UIScale` pulses on finisher |
| `TopBar.Progress.ProgressLabel` | TextLabel | checkpoint progress "12 / 30" |
| `GoalLabel` | TextLabel (RichText) | goal line (GDD §10.1) |
| `SeasonXp` | Frame | hide until the first round ends (§10.1 step 9) |
| `SeasonXp.TierBadge.TierLabel` | TextLabel | tier number |
| `SeasonXp.Bar.Fill` | Frame | Size X = xp / tierXp |
| `SeasonXp.XpLabel` | TextLabel | "430 / 900" |
| `Menu.<Shop\|Inventory\|Daily\|Wheel\|Season\|Settings>` | TextButton | opens the menu; each has `.UIScale`, `.Icon`, `.Caption` |
| `Menu.<name>.Badge` | Frame | red dot, toggle `Visible`; `.Badge.CountLabel` = count |
| `StarterPack` | TextButton | opens the Starter Pack offer; hide when not live |
| `StarterPack.TimerLabel` | TextLabel | countdown "⏰ mm:ss" |
| `Hotbar.Slot0` | TextButton | temp tool slot (attribute `Slot` = 0); `ChargesLabel` shows time left |
| `Hotbar.Slot1..3` | TextButton | equipped tools (attribute `Slot` = 1–3) → `UseTool(slot)` |
| `Hotbar.SlotN.Icon` | ImageLabel | tool icon; hide `Icon.Placeholder` once set |
| `Hotbar.SlotN.KeyHint` | TextLabel | "1/2/3" on keyboard; hide on touch, gamepad glyph on gamepad |
| `Hotbar.SlotN.ChargesLabel` | TextLabel | "×3" charges ("" when unlimited) |
| `Hotbar.SlotN.Cooldown` | Frame | dark overlay, `Visible` during cooldown; `.CooldownLabel` seconds |
| `Hotbar.Slot3.Lock` | Frame | shown without Tool Belt pass; tapping Slot3 opens the pass offer |
| `TrickPopup` | Frame (`Visible = false`) | trick feedback (§7.7); `.UIScale` for the pop-in |
| `TrickPopup.TrickLabel` | TextLabel | trick name |
| `TrickPopup.ChainLabel` | TextLabel | "×1.5" chain multiplier |
| `TrickPopup.ResultLabel` | TextLabel | "CLEAN! 577" (set `TextColor3`: gold / orange / red for Clean / Sloppy / Bail) |
| `TrickPopup.MaxTag` / `.MixedLabel` | TextLabel (hidden) | "MAX" segment cap / "MIXED +25%" |
| `Toasts` | Frame + UIListLayout | parent for toast clones (newest via LayoutOrder) |
| `Templates.Toast` | Frame (invisible template) | clone into `Toasts`, set `Visible = true`; `.TextLabel` (RichText), `.UIScale` |

## Layout notes

- Both ScreenGuis use `ScreenInsets = CoreUISafeInsets`, `ResetOnSpawn = false`, Scale sizing and
  `UIAspectRatioConstraint`s. Checked at 1366×913 and a 750×390 phone-landscape frame.
- The hotbar arcs around the Roblox jump button and leaves the bottom-right corner empty (GDD §6.3).
- The menu is a 2×3 grid in the upper left, so it stays clear of the thumbstick zone on the lower left.
- Touch targets have `UISizeConstraint` MinSize 44.
