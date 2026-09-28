--!strict
-- Number / text formatting shared by every UI label in the game.

local Format = {}

local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
}

-- Two decimals under 10, one under 100, none above: 1625 -> "1.63K",
-- 16625000 -> "16.6M", 350000000000000 -> "350T".
function Format.short(n: number): string
	if n ~= n or n == math.huge then return "?" end
	local neg = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = (n % 1 == 0) and tostring(math.floor(n)) or string.format("%.1f", n)
		return neg and ("-" .. s) or s
	end
	local tier = math.floor(math.log(n, 1000))
	tier = math.clamp(tier, 1, #SUFFIXES - 1)
	local scaled = n / (1000 ^ tier)
	local s
	if scaled >= 100 then
		s = string.format("%.0f", scaled)
	elseif scaled >= 10 then
		s = string.format("%.1f", scaled)
	else
		s = string.format("%.2f", scaled)
	end
	-- Trailing zeros are noise only AFTER a decimal point: "1.50" should read
	-- "1.5" and "2.00" should read "2". Stripping them unconditionally ate the
	-- zeros out of whole numbers too, so anything whose three-digit mantissa
	-- ended in a zero came out an order of magnitude small - 150,000 printed as
	-- "15K", 500,000 as "5K", and the 350T in this function's own example above
	-- as "35T". Only touch the fraction.
	if s:find("%.") then
		s = s:gsub("0+$", "")
		s = s:gsub("%.$", "")
	end
	return (neg and "-" or "") .. s .. SUFFIXES[tier + 1]
end

-- 1688705 -> "1,688,705"  (used where exact counts matter, e.g. roll totals)
function Format.comma(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end

-- 0.000004 -> "1 in 250,000"
function Format.odds(chance: number): string
	if chance <= 0 then return "never" end
	return "1 in " .. Format.comma(math.round(1 / chance))
end

-- 125 -> "2m 5s"
function Format.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then return string.format("%dh %dm", h, m) end
	if m > 0 then return string.format("%dm %ds", m, s) end
	return string.format("%ds", s)
end

return Format
