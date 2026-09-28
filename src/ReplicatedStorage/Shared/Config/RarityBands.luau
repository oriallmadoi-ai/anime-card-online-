--!strict
-- Rarity is a per-card DENOMINATOR now ("1 in 25,000"), not a named tier.
-- These bands exist purely for presentation: what colour to tint a card and
-- how loudly to celebrate it. They never influence a roll outcome.
--
-- Keeping this presentation-only is deliberate. The moment a band starts
-- affecting drop rates you have two sources of truth for rarity and they
-- will drift apart.

local RarityBands = {}

-- minDenominator, ascending. Highest matching band wins.
RarityBands.Bands = {
	{ min = 1,          name = "Common",    color = Color3.fromRGB(185, 190, 205), announce = false, reveal = "quick" },
	{ min = 100,        name = "Uncommon",  color = Color3.fromRGB(120, 220, 140), announce = false, reveal = "quick" },
	{ min = 2500,       name = "Rare",      color = Color3.fromRGB(90, 165, 255),  announce = false, reveal = "normal" },
	{ min = 50000,      name = "Epic",      color = Color3.fromRGB(190, 110, 255), announce = false, reveal = "normal" },
	{ min = 1000000,    name = "Mythic",    color = Color3.fromRGB(255, 120, 90),  announce = true,  reveal = "major" },
	{ min = 50000000,   name = "Forbidden", color = Color3.fromRGB(255, 60, 150),  announce = true,  reveal = "major" },
	{ min = 1000000000, name = "Divine",    color = Color3.fromRGB(255, 250, 220), announce = true,  reveal = "cinematic" },
}

function RarityBands.forDenominator(denominator: number)
	local band = RarityBands.Bands[1]
	for _, b in ipairs(RarityBands.Bands) do
		if denominator >= b.min then band = b end
	end
	return band
end

return RarityBands
