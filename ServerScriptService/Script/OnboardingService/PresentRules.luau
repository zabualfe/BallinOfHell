-- PresentRules
-- Pure decisions for the first-fall present (GDD 10.2). No engine calls.
--
--   PresentRules.ShouldSpawn({ SessionCount, Claimed, HasPending }) -> boolean
--       true only in session 1, before the gift was ever claimed, with no gift already waiting.
--   PresentRules.CanClaim({ Claimed, HasPending }) -> boolean
--       true only while a pending gift exists and the saved flag is still false (once ever).
--   PresentRules.IsFuture(endsAt, now) -> boolean
--       true when a timestamp attribute exists and lies after now (starter pack hint).

local PresentRules = {}

-- ── Tuning ──────────────────────────────────────────────────────────────
local FIRST_SESSION = 1

function PresentRules.ShouldSpawn(input)
	return input.SessionCount == FIRST_SESSION and input.Claimed == false and input.HasPending == false
end

function PresentRules.CanClaim(input)
	return input.HasPending == true and input.Claimed == false
end

function PresentRules.IsFuture(endsAt, now)
	return type(endsAt) == "number" and type(now) == "number" and endsAt > now
end

return PresentRules
