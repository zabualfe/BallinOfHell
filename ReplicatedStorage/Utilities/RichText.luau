-- RichText
-- Builds RichText strings. The only place colour markup is assembled.
--
-- Usage:
--   RichText.Color("Legendary", color3) -> '<font color="#ffaa00">Legendary</font>'
--   RichText.Bold("Coins") -> "<b>Coins</b>"

local RichText = {}

function RichText.Color(text, color)
	return ('<font color="#%s">%s</font>'):format(color:ToHex(), tostring(text))
end

function RichText.Bold(text)
	return "<b>" .. tostring(text) .. "</b>"
end

return RichText
