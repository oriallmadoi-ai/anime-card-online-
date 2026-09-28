--!strict
-- Rarity is shown as an exact denominator, never abbreviated: reading the
-- actual number is most of the appeal of the genre.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Format = require(ReplicatedStorage.Shared.Util.Format)

local RarityFormat = {}

-- 25000 -> "1 / 25,000"
function RarityFormat.denominator(n: number): string
	return "1 / " .. Format.comma(math.round(n))
end

return RarityFormat
